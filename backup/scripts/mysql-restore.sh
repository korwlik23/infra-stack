#!/usr/bin/env bash
# Restore MySQL จากไฟล์ backup (mysqldump --all-databases gzip)
# ใช้: ./mysql-restore.sh [--yes] backup/archives/mysql/all_YYYYMMDD_HHMMSS.sql.gz
#   --yes = ข้ามการพิมพ์ยืนยัน (ใช้โดย scripts/restore-server.sh ที่ยืนยันไปแล้ว)
#
# ได้ผลถูกต้องเมื่อ restore ลง MySQL ที่ "ยังว่าง" (เครื่องใหม่ / volume ใหม่)
# dump มี DROP TABLE ก่อน CREATE — restore ทับ database ที่มีอยู่ = ข้อมูลเดิมหายแทนด้วยของใน backup
set -euo pipefail

YES=0
if [ "${1:-}" = "--yes" ]; then YES=1; shift; fi
FILE="${1:?usage: mysql-restore.sh [--yes] <backup-file.sql.gz>}"

[ -f "$FILE" ] || { echo "ERROR: file not found: $FILE" >&2; exit 1; }
gunzip -t "$FILE" || { echo "ERROR: ไฟล์ backup เสีย (gzip ไม่ผ่าน): $FILE" >&2; exit 1; }
[ "$(docker inspect -f '{{.State.Health.Status}}' mysql 2>/dev/null || true)" = "healthy" ] \
  || { echo "ERROR: mysql container ไม่ healthy — เปิดก่อน: docker compose --env-file .env -f docker/docker-compose.mysql.yml up -d" >&2; exit 1; }

if [ "$YES" -ne 1 ]; then
  echo "⚠️  This will OVERWRITE every database in the backup on the running mysql container."
  read -rp "Type 'restore' to continue: " CONFIRM
  [ "$CONFIRM" = "restore" ] || { echo "aborted"; exit 1; }
fi

echo "[mysql-restore] restoring $(basename "$FILE")…"
# รหัส root อ่านจาก env ใน container — ไม่ส่งผ่าน argument (ไม่โผล่ใน ps)
gunzip -c "$FILE" | docker exec -i mysql sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysql -uroot'
# user ของ project อยู่ใน dump (ตาราง mysql.*) — โหลดสิทธิ์ใหม่ให้ใช้ได้ทันที
docker exec mysql sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysql -uroot -e "FLUSH PRIVILEGES"'
echo "[mysql-restore] ✅ done."
