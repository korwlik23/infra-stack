#!/usr/bin/env bash
# Backup database ของ project เดียว → backup/archives/pre-deploy/<project>/<project>_<stamp>.sql.gz
# ใช้: ./project-db-backup.sh <project>
#   deploy.sh เรียกให้เองก่อน migrate (DEPLOY_MIGRATE=1) — ไว้ย้อนข้อมูลเมื่อ migration ทำของเสีย
#   ปิด: DEPLOY_DB_BACKUP=0 ใน projects/<name>/.env · เก็บกี่ไฟล์: DEPLOY_DB_BACKUP_KEEP (default 5)
#
# ต่างจาก backup รายคืน (pg_dumpall / mysqldump --all-databases):
#   - dump เฉพาะ database ของ project นี้ → ย้อนได้โดยไม่ลาก project อื่นย้อนไปด้วย
#   - ทำก่อน migrate ทุกครั้ง → ข้อมูลหายไม่เกินช่วง deploy (แทนที่จะถอยไปถึง 03:00)
#   - dump มี DROP ก่อน CREATE (--clean / --add-drop-table) → restore ทับ database เดิมได้ (project-db-restore.sh)
# อยู่ในเครื่องเท่านั้น (ไม่ส่ง off-site) — ของ off-site คือ backup รายคืน
#
# หา database จาก projects/<name>/.env: DB_HOST/DB_DATABASE หรือ DATABASE_URL
#   host = postgres → pg_dump · mysql → mysqldump · อื่น ๆ (--external-db) → ข้าม (exit 0)
# exit: 0 = ได้ไฟล์ (พิมพ์ path บรรทัดสุดท้าย) หรือข้าม · 1 = ล้ม
set -euo pipefail

NAME="${1:?usage: project-db-backup.sh <project>}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PENV="$ROOT/projects/$NAME/.env"
[ -f "$PENV" ] || { echo "[db-backup:$NAME] ERROR: ไม่มี $PENV" >&2; exit 1; }

env_val() { grep -E "^$1=" "$ROOT/.env" 2>/dev/null | head -1 | cut -d= -f2- | sed -E 's/^"(.*)"$/\1/' || true; }
penv() { grep -E "^$1=" "$PENV" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '\r' | sed -E 's/^"(.*)"$/\1/; s/^'"'"'(.*)'"'"'$/\1/' || true; }

# shellcheck source=backup/scripts/project-db-lib.sh
. "$ROOT/backup/scripts/project-db-lib.sh"
project_db_resolve || exit 0

DEST="$ROOT/backup/archives/pre-deploy/$NAME"
KEEP="$(penv DEPLOY_DB_BACKUP_KEEP)"; KEEP="${KEEP:-5}"
OUT="$DEST/${NAME}_$(date +%Y%m%d_%H%M%S).sql.gz"
mkdir -p "$DEST"
chmod 700 "$DEST"

echo "[db-backup:$NAME] dumping $DB_ENGINE database '$DB_NAME'…"
# เขียนลง .partial ก่อน — dump ล้มกลางทางจะไม่เหลือไฟล์ครึ่ง ๆ ที่ดูเหมือน backup ล่าสุด
if [ "$DB_ENGINE" = postgres ]; then
  # --clean --if-exists = DROP ก่อน CREATE · ไม่ใส่ --create → restore ลง database ชื่อเดิมที่มีอยู่
  # --no-owner --no-privileges = ไม่พึ่ง role ที่อาจไม่มี (restore ด้วย superuser จาก .env)
  PG_USER="$(env_val POSTGRES_USER)"
  docker exec postgres pg_dump -U "${PG_USER:-infra}" -d "$DB_NAME" \
    --clean --if-exists --no-owner --no-privileges | gzip > "$OUT.partial"
else
  # ชื่อ database ส่งเป็น argument ของ sh (ไม่ต่อ string) — กันชื่อแปลก ๆ ทำ command เพี้ยน
  docker exec mysql sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysqldump -uroot \
    --single-transaction --routines --triggers --events --add-drop-table --set-gtid-purged=OFF \
    --databases "$1"' sh "$DB_NAME" | gzip > "$OUT.partial"
fi
mv "$OUT.partial" "$OUT"
chmod 600 "$OUT"

# เก็บไว้ KEEP ไฟล์ล่าสุด (นับไฟล์ ไม่ใช่วัน — deploy วันละหลายรอบก็ไม่ล้น)
# shellcheck disable=SC2012 # ชื่อไฟล์เป็น <project>_<stamp>.sql.gz ที่ script สร้างเอง
ls -1t "$DEST"/"${NAME}"_*.sql.gz 2>/dev/null | tail -n +"$((KEEP + 1))" | xargs -r rm -f --

echo "[db-backup:$NAME] ✅ $(du -h "$OUT" | cut -f1) → $OUT"
echo "$OUT"
