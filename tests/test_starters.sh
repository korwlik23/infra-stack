# shellcheck shell=bash
# alias / suite ใน templates/starters.list (scripts/lib/starters.sh)

_starters_setup() {
  mk_sandbox
  cd "$SANDBOX"
  # shellcheck source=scripts/lib/starters.sh
  . scripts/lib/starters.sh
}

test_starter_repo_from_real_list() {
  _starters_setup
  assert_eq "$(starter_repo cms-api-go)" korwlik23/go-api-starter "cms-api-go"
  assert_eq "$(starter_repo cms-admin)" korwlik23/vue-vite-admin-starter "cms-admin"
  assert_eq "$(starter_repo cms-site)" korwlik23/astro-site-starter "cms-site"
}

test_starter_suite_from_real_list() {
  _starters_setup
  assert_eq "$(starter_suite cms-go)" $'api cms-api-go\nadmin cms-admin\nsite cms-site' "cms-go members in deploy order"
}

test_unknown_names() {
  _starters_setup
  assert_fail "unknown alias" starter_repo nope
  assert_fail "unknown suite" starter_suite nope
  assert_fail "built-in template is not an alias" starter_repo go
  assert_fail "alias is not a suite" starter_suite cms-api-go
  assert_fail "suite is not an alias" starter_repo cms-go
}

test_comments_and_blank_lines_ignored() {
  _starters_setup
  cat > templates/starters.list <<'EOF'
# comment

x-api    acme/x-api     # ท้ายบรรทัด
s = api:x-api
EOF
  assert_eq "$(starter_repo x-api)" acme/x-api "alias with trailing comment"
  assert_eq "$(starter_suite s)" "api x-api" "suite"
}

test_suite_member_must_be_known_alias() {
  _starters_setup
  printf 's = api:missing\n' > templates/starters.list
  assert_fail "suite with unknown alias" starter_suite s
}

test_starter_names_lists_aliases_and_suites() {
  _starters_setup
  local out; out="$(starter_names)"
  assert_contains "$out" cms-api-go "alias listed"
  assert_contains "$out" cms-go "suite listed"
}
