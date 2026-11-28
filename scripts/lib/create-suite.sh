# shellcheck shell=bash
# สร้าง suite (ชุด starter) — ใช้โดย scripts/create-project.sh
#
# create_suite <name> <suite> <members> <flag>
#   members = บรรทัด "<ส่วนต่อท้าย> <alias>" จาก starter_suite (เรียงตามลำดับ deploy)
#   สร้าง projects/<name>-<ส่วนต่อท้าย> ทีละตัว (INFRA_SUITE=<name> → token __SUITE_*__ ต่อ URL ข้ามกัน)
#   สำเร็จครบ → projects/<name>.suite (รายชื่อตามลำดับ deploy — infra deploy <name>)
#   ล้มกลางทาง (เช่น repo private รอ deploy key) → projects/.<name>.suite-pending
#     รันคำสั่งเดิมซ้ำ = ทำต่อจากตัวที่ยังไม่ได้สร้าง

create_suite() {
  local name="$1" suite="$2" members="$3" flag="$4"
  local pending="projects/.$name.suite-pending" suffix alias member taken="" list="" rc
  [ -z "$flag" ] || { echo "ERROR: $flag ใช้กับ suite ไม่ได้" >&2; exit 1; }
  [ ! -f "projects/$name.suite" ] || { echo "ERROR: มี suite ชื่อ $name อยู่แล้ว (projects/$name.suite)" >&2; exit 1; }
  [ ! -f "projects/$name/docker-compose.yml" ] \
    || { echo "ERROR: มี project ชื่อ $name อยู่แล้ว — suite ต้องใช้ชื่ออื่น" >&2; exit 1; }

  # ตรวจชื่อทุกตัวก่อนเริ่ม — ไม่สร้างครึ่ง ๆ กลาง ๆ เพราะชื่อชน (ยกเว้นกำลังทำต่อจากรอบก่อน)
  if [ ! -f "$pending" ]; then
    while read -r suffix _; do
      [ ! -f "projects/$name-$suffix/docker-compose.yml" ] || taken="$taken $name-$suffix"
    done <<< "$members"
    [ -z "$taken" ] || { echo "ERROR: มี project ชื่อนี้อยู่แล้ว:$taken — ใช้ชื่อ suite อื่น" >&2; exit 1; }
  fi

  mkdir -p projects
  touch "$pending"
  while read -r suffix alias; do
    member="$name-$suffix"
    list="$list$member"$'\n'
    if [ -f "projects/$member/docker-compose.yml" ]; then
      echo "ℹ️  $member สร้างไว้แล้วจากรอบก่อน — ข้าม"
      continue
    fi
    echo "── $member ($alias) ──"
    rc=0
    INFRA_SUITE="$name" bash scripts/create-project.sh "$member" "$alias" || rc=$?
    if [ "$rc" != 0 ]; then
      echo >&2
      echo "⏸  suite $name ยังไม่ครบ — หยุดที่ $member" >&2
      echo "   แก้ตามข้อความด้านบนแล้วรันซ้ำ: infra new $name $suite (ตัวที่สร้างแล้วจะถูกข้าม)" >&2
      exit "$rc"
    fi
  done <<< "$members"

  printf '%s' "$list" > "projects/$name.suite"
  rm -f "$pending"

  echo
  echo "✅ suite $name ($suite): $(printf '%s' "$list" | xargs)"
  echo "next:"
  echo "  1. เพิ่ม DNS record (Cloudflare, Proxied) ชี้ server IP:"
  while read -r member; do
    [ -n "$member" ] || continue
    echo "       $(grep -E '^APP_DOMAIN=' "projects/$member/.env" 2>/dev/null | head -1 | cut -d= -f2- || echo "$member")"
  done <<< "$list"
  echo "  2. infra deploy $name                # deploy ทั้งชุดตามลำดับ (หยุดถ้าตัวไหนล้ม)"
}
