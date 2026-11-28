# shellcheck shell=bash
# ดึง starter (repo ที่มี deploy/infra-stack/) เข้า projects/<name>/src — ใช้โดย scripts/create-project.sh
#
# fetch_starter <name> <owner/repo> <ชื่อที่ผู้ใช้พิมพ์>
#   clone (public https / deploy key — scripts/lib/git-clone.sh) แล้วตรวจว่า repo มี
#   Dockerfile ที่ root + deploy/infra-stack/docker-compose.yml ที่ผ่าน compose_guard
#   ล้ม → ลบ projects/<name> ที่เพิ่งสร้าง (ไม่แตะโฟลเดอร์ที่มีอยู่ก่อน) แล้ว exit 1
#   repo private ที่ยังไม่ได้เพิ่ม deploy key → exit 2 (รันคำสั่งเดิมซ้ำหลังเพิ่ม key)
# ข้อตกลงของ repo: docs/32-starters.md

# shellcheck source=scripts/lib/git-clone.sh
. scripts/lib/git-clone.sh
# shellcheck source=scripts/lib/compose-guard.sh
. scripts/lib/compose-guard.sh

fetch_starter() {
  local name="$1" repo="$2" typed="$3" dir="projects/$1" created=0 tpl
  [ -d "$dir" ] || created=1
  _starter_fail() {
    echo "ERROR: $*" >&2
    if [ "$created" = 1 ]; then rm -rf "$dir"; fi
    exit 1
  }

  if [ -d "$dir/src/.git" ]; then
    echo "ℹ️  $dir/src เป็น git clone อยู่แล้ว — ใช้ของเดิม"
  else
    [ ! -e "$dir/src" ] || _starter_fail "$dir/src มีอยู่แล้วแต่ไม่ใช่ git clone — ย้ายออกก่อน"
    git_resolve_url "$name" "$repo" main "infra new $name $typed"
    mkdir -p "$dir"
    git_clone_to "$GIT_URL" main "$dir/src.new" || _starter_fail "clone $repo ไม่สำเร็จ"
    mv "$dir/src.new" "$dir/src"
  fi

  tpl="$dir/src/deploy/infra-stack"
  [ -f "$tpl/docker-compose.yml" ] || _starter_fail "$repo ไม่มี deploy/infra-stack/docker-compose.yml
  repo ที่จะใช้เป็น starter ต้องมีโฟลเดอร์ deploy/infra-stack/ (docker-compose.yml + .env.example)
  ดูข้อตกลง: docs/32-starters.md · หรือใช้ template ในตัว: infra new $name go แล้ว infra git $name $repo"
  [ -f "$dir/src/Dockerfile" ] || _starter_fail "$repo ไม่มี Dockerfile ที่ root (docs/32-starters.md)"
  compose_guard "$tpl/docker-compose.yml" || _starter_fail "ไม่ใช้ template ของ $repo (ดูเหตุผลด้านบน)"
  echo "✅ $repo — ใช้ template จาก deploy/infra-stack/"
}
