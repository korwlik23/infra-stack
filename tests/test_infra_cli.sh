# shellcheck shell=bash
# infra list / help / Tab completion รู้จัก starter และ suite

_cli_setup() {
  mk_sandbox
  local m
  for m in shop-api shop-admin shop-site; do
    mkdir -p "$SANDBOX/projects/$m" && touch "$SANDBOX/projects/$m/docker-compose.yml"
  done
  printf 'shop-api\nshop-admin\nshop-site\n' > "$SANDBOX/projects/shop.suite"
  printf '#!/usr/bin/env bash\nexec bash "%s/scripts/infra" "$@"\n' "$SANDBOX" > "$SANDBOX/bin/infra"
  chmod +x "$SANDBOX/bin/infra"
}

# _complete <คำ…> → คำที่ Tab completion เสนอสำหรับคำสุดท้าย
_complete() {
  # shellcheck source=scripts/infra-completion.bash
  . "$SANDBOX/scripts/infra-completion.bash"
  COMP_WORDS=(infra "$@"); COMP_CWORD=$#
  readlink() { [ "$1" = -f ] && shift; printf '%s\n' "$1"; }   # Git Bash: readlink -f ของ wrapper
  _infra
  printf '%s\n' "${COMPREPLY[@]}"
}

test_list_shows_suites() {
  _cli_setup
  local out; out="$(cd "$SANDBOX" && bash scripts/infra list 2>&1)"
  assert_match "$out" 'shop[[:space:]]+→[[:space:]]+shop-api shop-admin shop-site' "suite line"
}

test_help_mentions_starters() {
  _cli_setup
  local out; out="$(cd "$SANDBOX" && bash scripts/infra help 2>&1)"
  assert_contains "$out" "new <ชื่อ> <template|starter|suite|owner/repo>" "new syntax"
  assert_contains "$out" "deploy <p|suite>" "deploy syntax"
}

test_completion_new_offers_starters() {
  _cli_setup
  local out; out="$(_complete new shop "")"
  assert_contains "$out" go "built-in template"
  assert_contains "$out" cms-go "suite"
  assert_contains "$out" cms-api-go "alias"
  [[ "$out" != *starters.list* ]] || { echo "    ✗ offers starters.list"; return 1; }
}

test_completion_deploy_offers_suites() {
  _cli_setup
  local out; out="$(_complete deploy "")"
  assert_contains "$out" shop-api "project"
  assert_match "$out" '(^|'$'\n'')shop($|'$'\n'')' "suite name"
}
