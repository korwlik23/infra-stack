#!/usr/bin/env bash
# ล้างขยะ Docker ที่สะสมจากการ deploy — ไม่แตะของที่ใช้อยู่ / ข้อมูล
# ใช้: ./scripts/cleanup.sh      (cron รายวัน 04:00 — infra cron)
#
# ลบ:
#   - build cache ที่ไม่ได้ใช้เกิน CLEANUP_CACHE_AGE (default 72h) — ของใหม่เก็บไว้ให้ build ถัดไปเร็ว
#   - image ที่ไม่มี tag (<none>) — :previous มี tag จึงรอด → rollback ได้เหมือนเดิม
#   - container ที่หยุดแล้วเกิน 24 ชม. ที่ไม่ใช่ของ compose (เช่น docker run ที่ลืม --rm)
# ไม่ลบ volume เด็ดขาด (มีข้อมูล) — ดูเองด้วย: docker volume ls -f dangling=true
set -uo pipefail
cd "$(dirname "$0")/.."

AGE="${CLEANUP_CACHE_AGE:-72h}"
used() { df -h / | awk 'NR==2 {print $3 " / " $2 " (" $5 ")"}'; }

echo "=== InfraStack cleanup $(date '+%F %T') — ก่อน: $(used) ==="
FAILED=""
docker builder prune -f --filter "until=$AGE" | tail -n 1 || FAILED="$FAILED builder"
docker image prune -f | tail -n 1 || FAILED="$FAILED image"
docker container prune -f --filter "until=24h" \
  --filter "label!=com.docker.compose.project" | tail -n 1 || FAILED="$FAILED container"

if [ -n "$FAILED" ]; then
  echo "❌ cleanup ไม่สำเร็จ:$FAILED" >&2
  exit 1
fi
echo "✅ หลัง: $(used)"
