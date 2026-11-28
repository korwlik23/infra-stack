# shellcheck shell=bash
# อ่าน templates/starters.list — alias (ชื่อสั้น → owner/repo) และ suite (ชุดของ alias)
# ต้องรันจาก root ของ infra-stack
#
# starter_repo <alias>   → พิมพ์ owner/repo · ไม่ใช่ alias → exit 1
# starter_suite <suite>  → พิมพ์ "<ส่วนต่อท้าย> <alias>" บรรทัดละตัวตามลำดับ deploy · ไม่ใช่ suite → exit 1
# starter_names          → ชื่อ alias + suite ทั้งหมด (ใช้กับ completion / help)

STARTERS_LIST="${STARTERS_LIST:-templates/starters.list}"

# บรรทัดที่มีความหมาย: ตัด comment + ช่องว่างหัวท้าย · ข้ามบรรทัดว่าง
_starters_lines() {
  [ -f "$STARTERS_LIST" ] || return 0
  sed -E -e 's/(^|[[:space:]])#.*$//' -e 's/^[[:space:]]+//' -e 's/[[:space:]]+$//' "$STARTERS_LIST" \
    | tr -d '\r' | grep -v '^$' || true
}

starter_repo() {
  local name="$1" a r
  while read -r a r _; do
    [ "$a" = "$name" ] && [ -n "$r" ] && [ "$r" != "=" ] || continue
    printf '%s\n' "$r"
    return 0
  done < <(_starters_lines | grep -v '=')
  return 1
}

starter_suite() {
  local name="$1" line members m suffix alias out=""
  line="$(_starters_lines | grep -E "^${name}[[:space:]]*=" | head -1 || true)"
  [ -n "$line" ] || return 1
  members="${line#*=}"
  for m in $members; do
    suffix="${m%%:*}"; alias="${m#*:}"
    [[ "$suffix" =~ ^[a-z0-9]+$ ]] && [ "$suffix" != "$m" ] \
      || { echo "ERROR: suite $name: '$m' ต้องเป็น <ส่วนต่อท้าย>:<alias>" >&2; return 1; }
    starter_repo "$alias" >/dev/null \
      || { echo "ERROR: suite $name: ไม่มี alias '$alias' ใน $STARTERS_LIST" >&2; return 1; }
    out+="$suffix $alias"$'\n'
  done
  [ -n "$out" ] || return 1
  printf '%s' "$out"
}

starter_names() {
  _starters_lines | sed -E 's/[[:space:]]*=.*$//' | awk '{print $1}'
}
