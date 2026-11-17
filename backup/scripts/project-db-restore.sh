#!/usr/bin/env bash
# ย้อน database ของ project เดียวจาก backup ก่อน deploy (project-db-backup.sh)
# ใช้: ./project-db-restore.sh [--yes] <project> [ไฟล์]     (ไม่ใส่ไฟล์ = ล่าสุดของ project นี้)
#   ใช้คู่ rollback: migration ทำข้อมูลเสีย → infra rollback <p> แล้ว infra restore db <p>
#
# ทับเฉพาะ database ของ project นี้ (project อื่นไม่โดน) — ข้อมูลที่เขียนหลังเวลา backup หาย
# ก่อนทับ: dump สถานะปัจจุบันเก็บไว้อีกชุด (ย้อนการ restore ได้ถ้าเลือกไฟล์ผิด)
# ควร stop app ก่อน (container ยังเขียนระหว่าง restore = ข้อมูลปน) — script ถามให้
set -euo pipefail

YES=0
if [ "${1:-}" = "--yes" ]; then YES=1; shift; fi
NAME="${1:?usage: project-db-restore.sh [--yes] <project> [backup-file.sql.gz]}"
FILE="${2:-}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PENV="$ROOT/projects/$NAME/.env"
[ -f "$PENV" ] || { echo "ERROR: ไม่มี $PENV" >&2; exit 1; }

env_val() { grep -E "^$1=" "$ROOT/.env" 2>/dev/null | head -1 | cut -d= -f2- | sed -E 's/^"(.*)"$/\1/' || true; }
penv() { grep -E "^$1=" "$PENV" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '\r' | sed -E 's/^"(.*)"$/\1/; s/^'"'"'(.*)'"'"'$/\1/' || true; }

# shellcheck source=backup/scripts/project-db-lib.sh
. "$ROOT/backup/scripts/project-db-lib.sh"
project_db_resolve || exit 1

DEST="$ROOT/backup/archives/pre-deploy/$NAME"
if [ -z "$FILE" ]; then
  # shellcheck disable=SC2012
  FILE="$(ls -1t "$DEST"/"${NAME}"_*.sql.gz 2>/dev/null | head -1 || true)"
  [ -n "$FILE" ] || { echo "ERROR: ไม่มี backup ใน $DEST" >&2; exit 1; }
fi
[ -f "$FILE" ] || { echo "ERROR: file not found: $FILE" >&2; exit 1; }
gunzip -t "$FILE" || { echo "ERROR: ไฟล์ backup เสีย (gzip ไม่ผ่าน): $FILE" >&2; exit 1; }

echo "จะย้อน $DB_ENGINE database '$DB_NAME' ของ $NAME ← $(basename "$FILE")"
echo "  backup เมื่อ: $(date -r "$FILE" '+%F %T')  — ข้อมูลที่เขียนหลังจากนี้จะหาย"
echo "  project อื่นไม่โดน"
RUNNING="$(cd "$ROOT/projects/$NAME" && docker compose ps -q 2>/dev/null || true)"
if [ "$YES" -ne 1 ]; then
  read -rp "Type 'restore' to continue: " CONFIRM
  [ "$CONFIRM" = "restore" ] || { echo "aborted"; exit 1; }
  if [ -n "$RUNNING" ]; then
    read -rp "stop container ของ $NAME ระหว่าง restore (เว็บดับชั่วคราว — แนะนำ)? [Y/n] " ans || ans=n
    [[ "$ans" =~ ^[Nn] ]] && RUNNING=""
  fi
fi

# กันพลาด: เก็บสถานะก่อนทับ — ใส่ชื่อ before-restore ให้ไม่ถูกนับเป็น backup ก่อน deploy
SAFETY="$("$ROOT/backup/scripts/project-db-backup.sh" "$NAME" | tail -1)"
case "$SAFETY" in
  *.sql.gz) mv "$SAFETY" "${SAFETY%.sql.gz}.before-restore.sql.gz"
            SAFETY="${SAFETY%.sql.gz}.before-restore.sql.gz"
            echo "[db-restore:$NAME] สถานะก่อนทับ → $SAFETY" ;;
  *) echo "ERROR: dump สถานะปัจจุบันไม่สำเร็จ — ไม่ทับ" >&2; exit 1 ;;
esac

if [ -n "$RUNNING" ]; then
  echo "[db-restore:$NAME] stopping containers…"
  (cd "$ROOT/projects/$NAME" && docker compose stop)
  trap 'echo "[db-restore:'"$NAME"'] starting containers…"; (cd "$ROOT/projects/$NAME" && docker compose start) || true' EXIT
fi

echo "[db-restore:$NAME] restoring…"
if [ "$DB_ENGINE" = postgres ]; then
  # ล้าง schema public ก่อน — ตารางที่ migration ใหม่เพิ่ม (ไม่อยู่ใน dump) จะไม่ค้าง
  #   (ค้าง = deploy ครั้งหน้า migrate ล้มด้วย "already exists")
  # ON_ERROR_STOP=1 + --single-transaction → ล้มกลางทาง = rollback ทั้งหมด ไม่มีอะไรเปลี่ยน
  PG_USER="$(env_val POSTGRES_USER)"
  { echo 'DROP SCHEMA IF EXISTS public CASCADE; CREATE SCHEMA public;'; gunzip -c "$FILE"; } \
    | docker exec -i postgres psql -U "${PG_USER:-infra}" -d "$DB_NAME" \
        -v ON_ERROR_STOP=1 --single-transaction -q >/dev/null
else
  # dump ชุดนี้มี DROP TABLE ต่อตาราง — ตารางที่เพิ่มหลัง backup (migration ใหม่) ไม่ถูกลบ → ลบ database ทั้งก้อนก่อน
  # (MySQL DDL ไม่อยู่ใน transaction — ล้มกลางทาง: ย้อนด้วยไฟล์ before-restore ด้านบน · สิทธิ์ user ใน mysql.db ไม่หาย)
  docker exec mysql sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysql -uroot -e "DROP DATABASE IF EXISTS \`$1\`"' sh "$DB_NAME"
  gunzip -c "$FILE" | docker exec -i mysql sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysql -uroot'
fi
echo "[db-restore:$NAME] ✅ done · ย้อนการ restore นี้: infra restore db $NAME $SAFETY"
