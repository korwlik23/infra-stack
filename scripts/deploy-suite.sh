#!/usr/bin/env bash
# deploy ทั้ง suite ตามลำดับใน projects/<suite>.suite (สร้างโดย infra new <suite> <ชุด starter> — docs/32)
# ใช้: ./scripts/deploy-suite.sh <suite> [argument ของ deploy.sh เช่น --seed]   (infra deploy <suite>)
# ตัวใดล้ม → หยุดทันที ไม่ deploy ตัวถัดไป (เช่น api ล้ม → admin/site ยังเป็นเวอร์ชันเดิมที่คุยกับ api เดิมได้)
set -euo pipefail
cd "$(dirname "$0")/.."

SUITE="${1:?usage: deploy-suite.sh <suite> [deploy args]}"
shift
LIST="projects/$SUITE.suite"
[ -f "$LIST" ] || { echo "ERROR: ไม่มี suite ชื่อ $SUITE ($LIST)" >&2; exit 1; }

mapfile -t MEMBERS < <(tr -d '\r' < "$LIST" | grep -v '^[[:space:]]*$')
[ ${#MEMBERS[@]} -gt 0 ] || { echo "ERROR: $LIST ว่าง" >&2; exit 1; }

for i in "${!MEMBERS[@]}"; do
  m="${MEMBERS[$i]}"
  echo "━━ [$((i + 1))/${#MEMBERS[@]}] deploy $m ━━"
  if ! ./scripts/deploy.sh "$m" "$@"; then
    echo >&2
    echo "❌ suite $SUITE หยุดที่ $m" >&2
    rest=("${MEMBERS[@]:$((i + 1))}")
    [ ${#rest[@]} -eq 0 ] || echo "   ยังไม่ได้ deploy: ${rest[*]} (ยังเป็นเวอร์ชันเดิม)" >&2
    echo "   แก้แล้วรันซ้ำ: infra deploy $SUITE · หรือทีละตัว: infra deploy $m" >&2
    exit 1
  fi
done
echo "✅ suite $SUITE: deploy ครบ ${#MEMBERS[@]} ตัว (${MEMBERS[*]})"
