# shellcheck shell=bash
# template ในตัว (go, laravel, …) ต้องได้ไฟล์เหมือนเดิมทุกไบต์ — กันการแก้ create-project.sh ทำของเดิมพัง
# golden สร้างจากโค้ดก่อนเพิ่ม starter: UPDATE_GOLDEN=1 bash tests/run.sh test_create_project_builtin.sh

BUILTIN_TEMPLATES=(go laravel nextjs n8n ai-worker)

# พิมพ์ทุกไฟล์ใน projects/<name> (เรียงชื่อ) — ค่าสุ่ม hex 48 ตัว → <HEX>
_dump_project() {
  local dir="$1" f
  (cd "$dir" && find . -type f | LC_ALL=C sort) | while IFS= read -r f; do
    printf '=== %s\n' "$f"
    sed -E 's/[0-9a-f]{48}/<HEX>/g' "$dir/$f"
  done
}

test_builtin_templates_unchanged() {
  mk_sandbox
  local t got golden
  for t in "${BUILTIN_TEMPLATES[@]}"; do
    (cd "$SANDBOX" && bash scripts/create-project.sh "p-$t" "$t" >/dev/null 2>&1)
    got="$(_dump_project "$SANDBOX/projects/p-$t")"
    golden="$REPO_ROOT/tests/golden/$t.txt"
    if [ "${UPDATE_GOLDEN:-0}" = 1 ]; then
      mkdir -p "$(dirname "$golden")"
      printf '%s\n' "$got" > "$golden"
    fi
    assert_eq "$got" "$(cat "$golden")" "template $t"
  done
}

test_builtin_env_is_mode_600() {
  mk_sandbox
  (cd "$SANDBOX" && bash scripts/create-project.sh p-go go >/dev/null 2>&1)
  # Windows (Git Bash) ไม่มี permission แบบ unix — ตรวจเฉพาะบน Linux
  [ "$(uname -s)" = Linux ] || return 0
  assert_eq "$(stat -c %a "$SANDBOX/projects/p-go/.env")" 600 ".env mode"
}
