# shellcheck shell=bash
# helper ของ test — source โดย tests/run.sh
# assert ล้ม → พิมพ์เหตุผลแล้ว return 1 (run.sh นับเป็น test ที่ล้ม)

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

assert_eq() {
  [ "$1" == "$2" ] && return 0
  printf '    ✗ %s\n      got:  %q\n      want: %q\n' "${3:-assert_eq}" "$1" "$2"
  return 1
}

assert_match() {
  [[ "$1" =~ $2 ]] && return 0
  printf '    ✗ %s\n      got:   %q\n      regex: %s\n' "${3:-assert_match}" "$1" "$2"
  return 1
}

assert_contains() {
  [[ "$1" == *"$2"* ]] && return 0
  printf '    ✗ %s\n      text does not contain: %s\n' "${3:-assert_contains}" "$2"
  return 1
}

# assert_fail <msg> <cmd…> — คำสั่งต้อง exit ≠ 0
assert_fail() {
  local msg="$1"; shift
  if "$@" >/dev/null 2>&1; then
    printf '    ✗ %s\n      command succeeded but should fail: %s\n' "$msg" "$*"
    return 1
  fi
}

# ค่าบรรทัด KEY= ในไฟล์ .env
env_get() { grep -E "^$1=" "$2" | head -1 | cut -d= -f2-; }

# mk_sandbox → ตั้ง SANDBOX = สำเนา repo ขนาดเล็ก (scripts/ templates/ backup/scripts/)
# + .env กลางปลอม + stub docker (ไม่มี daemon) ใน $SANDBOX/bin ที่อยู่หน้า PATH
mk_sandbox() {
  SANDBOX="$(mktemp -d)"
  mkdir -p "$SANDBOX/backup" "$SANDBOX/bin" "$SANDBOX/projects"
  cp -r "$REPO_ROOT/scripts" "$REPO_ROOT/templates" "$SANDBOX/"
  cp -r "$REPO_ROOT/backup/scripts" "$SANDBOX/backup/"
  cat > "$SANDBOX/.env" <<'EOF'
BASE_DOMAIN=example.com
POSTGRES_USER=infra
REDIS_PASSWORD=r&|\x
EOF
  stub_docker_absent
  export PATH="$SANDBOX/bin:$PATH"
}

# docker ไม่มี daemon — ทุกคำสั่งล้ม
stub_docker_absent() {
  printf '#!/usr/bin/env bash\nexit 1\n' > "$SANDBOX/bin/docker"
  chmod +x "$SANDBOX/bin/docker"
}

rm_sandbox() { [ -n "${SANDBOX:-}" ] && rm -rf "$SANDBOX"; SANDBOX=""; }
