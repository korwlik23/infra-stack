#!/usr/bin/env bash
# Backup ทั้งเครื่อง — PostgreSQL + Docker volumes + secrets (เข้ารหัส) → backup/archives/ (+ off-site)
# ใช้: ./scripts/backup.sh      (cron รายวัน — docs/13-backup.md)
# แต่ละส่วนรันต่อแม้ส่วนก่อนล้ม (postgres ล้มไม่ควรทำให้ไม่ได้ backup secrets) แล้ว exit 1 ตอนจบ
set -uo pipefail
cd "$(dirname "$0")/.."

echo "=== InfraStack backup $(date '+%F %T') ==="
FAILED=""
for PART in postgres volumes secrets; do
  ./backup/scripts/"$PART"-backup.sh || FAILED="$FAILED $PART"
done

if [ -n "$FAILED" ]; then
  echo "❌ backup ไม่สำเร็จ:$FAILED — ดู error ด้านบน" >&2
  exit 1
fi
echo "✅ full backup complete → backup/archives/"
