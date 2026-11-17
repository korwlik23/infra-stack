#!/usr/bin/env bash
# Backup ทั้งเครื่อง — PostgreSQL + MySQL (ถ้ามี) + Docker volumes + secrets (เข้ารหัส) → backup/archives/ (+ off-site)
# ใช้: ./scripts/backup.sh      (cron รายวัน — docs/13-backup.md)
# แต่ละส่วนรันต่อแม้ส่วนก่อนล้ม (postgres ล้มไม่ควรทำให้ไม่ได้ backup secrets) แล้ว exit 1 ตอนจบ
# แจ้ง Telegram (lib/notify.sh) เมื่อ: ส่วนไหนล้ม · ยังไม่ได้ตั้ง off-site (backup อยู่แค่ในเครื่องนี้)
#   สำเร็จครบ = เงียบ (ตั้ง NOTIFY_BACKUP_SUCCESS=1 ใน .env กลาง ถ้าอยากได้ข้อความทุกคืน)
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
# shellcheck source=scripts/lib/notify.sh
. "$ROOT/scripts/lib/notify.sh"

echo "=== InfraStack backup $(date '+%F %T') ==="
OUT="$(mktemp)"
trap 'rm -f "$OUT"' EXIT
FAILED=""
for PART in postgres mysql volumes secrets; do
  # tee เก็บ output ไว้หาคำเตือน off-site — pipefail ทำให้ได้ exit code ของ script ไม่ใช่ของ tee
  ./backup/scripts/"$PART"-backup.sh 2>&1 | tee -a "$OUT" || FAILED="$FAILED $PART"
done

OFFSITE_WARN="$(grep -m1 -o '\[offsite\] ⚠️.*' "$OUT" || true)"

if [ -n "$FAILED" ]; then
  echo "❌ backup ไม่สำเร็จ:$FAILED — ดู error ด้านบน" >&2
  notify "❌ backup ไม่สำเร็จ:$FAILED
ดู: infra logs backup · รันซ้ำ: infra backup${OFFSITE_WARN:+
$OFFSITE_WARN}"
  exit 1
fi
if [ -n "$OFFSITE_WARN" ]; then
  notify "⚠️ backup สำเร็จแต่อยู่แค่ในเครื่องนี้ — VPS พัง = backup หายด้วย
$OFFSITE_WARN"
elif [ "$(grep -E '^NOTIFY_BACKUP_SUCCESS=' .env 2>/dev/null | head -1 | cut -d= -f2-)" = 1 ]; then
  notify "✅ backup ครบ (postgres · mysql · volumes · secrets) + off-site"
fi
echo "✅ full backup complete → backup/archives/"
