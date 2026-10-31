#!/usr/bin/env bash
# Backup ทุก database ใน MySQL container → backup/archives/mysql/
# ใช้: ./mysql-backup.sh   (scripts/backup.sh เรียกให้ทุกวัน)
# ไม่มี MySQL (ไม่มี project ไหนใช้ --mysql) → ข้ามเฉย ๆ ไม่นับว่าล้ม
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# อ่านค่าจาก .env ทีละ key แทน `source` — รหัสผ่านที่มีอักขระพิเศษทำ source พัง
env_val() { grep -E "^$1=" "$ROOT/.env" 2>/dev/null | head -1 | cut -d= -f2- | sed -E 's/^"(.*)"$/\1/' || true; }

if [ "$(docker inspect -f '{{.State.Running}}' mysql 2>/dev/null || true)" != "true" ]; then
  echo "[mysql-backup] ไม่มี mysql container รันอยู่ — ข้าม"
  exit 0
fi

DEST="$ROOT/backup/archives/mysql"
STAMP="$(date +%Y%m%d_%H%M%S)"
KEEP_DAYS="$(env_val BACKUP_KEEP_DAYS)"; KEEP_DAYS="${KEEP_DAYS:-7}"
OUT="$DEST/all_${STAMP}.sql.gz"

mkdir -p "$DEST"

echo "[mysql-backup] dumping all databases…"
# --single-transaction = snapshot ของ InnoDB โดยไม่ lock ตาราง (เว็บใช้งานต่อได้ระหว่าง dump)
# รหัส root อ่านจาก env ใน container — ไม่ส่งผ่าน argument (ไม่โผล่ใน ps)
# เขียนลง .partial ก่อน — dump ล้มกลางทาง จะไม่เหลือไฟล์ครึ่ง ๆ ที่ดูเหมือน backup ล่าสุด
docker exec mysql sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysqldump -uroot --all-databases \
  --single-transaction --routines --triggers --events --set-gtid-purged=OFF' | gzip > "$OUT.partial"
mv "$OUT.partial" "$OUT"

echo "[mysql-backup] pruning backups older than ${KEEP_DAYS} days…"
find "$DEST" -name "all_*.sql.gz" -mtime +"$KEEP_DAYS" -delete

"$ROOT/backup/scripts/offsite.sh" mysql "$OUT"

echo "[mysql-backup] done → $OUT"
