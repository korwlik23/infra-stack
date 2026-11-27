#!/usr/bin/env bash
# รัน test ของ infra-stack: bash tests/run.sh [ชื่อไฟล์ test_*.sh …]
# แต่ละไฟล์ tests/test_*.sh นิยามฟังก์ชัน test_* — run.sh เรียกทีละตัวใน subshell
# (sandbox / PATH / ตัวแปรไม่รั่วข้าม test) · มี test ล้ม → exit 1
set -uo pipefail
cd "$(dirname "$0")"
# shellcheck source=tests/lib.sh
. ./lib.sh

pass=0; fail=0; failed=()
files=("$@")
[ ${#files[@]} -gt 0 ] || files=(test_*.sh)

for f in "${files[@]}"; do
  [ -f "$f" ] || continue
  for t in $(bash -c ". ./lib.sh; . ./$f; declare -F" | awk '{print $3}' | grep '^test_'); do
    # ไม่ใส่ subshell ใน if — set -e ถูกปิดในเงื่อนไขของ if (assert ที่ล้มกลางทางจะไม่หยุด test)
    ( . ./lib.sh; . "./$f"; trap rm_sandbox EXIT; set -e; "$t" ); rc=$?
    if [ "$rc" = 0 ]; then
      pass=$((pass + 1)); echo "  ✓ $f :: $t"
    else
      fail=$((fail + 1)); failed+=("$f :: $t"); echo "  ✗ $f :: $t"
    fi
  done
done

echo
echo "$pass passed, $fail failed"
[ "$fail" = 0 ] || { printf '  failed: %s\n' "${failed[@]}"; exit 1; }
