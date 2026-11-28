# shellcheck shell=bash
# infra new <ชื่อ> <alias|suite|owner/repo> — template มาจาก deploy/infra-stack/ ใน repo

# template ของ starter ปลอม: $1 = role (api|admin|site)
_mk_starter_tpl() {
  local role="$1" dir; dir="$(mktemp -d)"
  cat > "$dir/docker-compose.yml" <<'EOF'
services:
  app:
    image: ${APP_IMAGE}
    # build: ./src
    labels:
      - "traefik.http.routers.__PROJECT__.rule=Host(`${APP_DOMAIN}`)"
EOF
  cat > "$dir/.env.example" <<EOF
APP_IMAGE=__PROJECT__:latest
APP_DOMAIN=__SUITE_HOST:${role}__
API_URL=__SUITE_ORIGIN:api__/api/v1
REDIS_PASSWORD=__ROOT:REDIS_PASSWORD__
SECRET=__GENERATE__
KEYRING=v1:__GENERATE_B64__
TRUSTED_PROXY_CIDRS=__PROXY_CIDR__
EOF
  if [ "$role" = api ]; then
    cat >> "$dir/.env.example" <<'EOF'
DB_HOST=postgres
DB_DATABASE=__PROJECT___db
DB_USERNAME=__DB_USER__
DB_PASSWORD=__DB_PASSWORD__
DB_RUNTIME_USER=__DB_RUNTIME_USER__
DB_RUNTIME_PASSWORD=__DB_RUNTIME_PASSWORD__
EOF
  fi
  printf '# __PROJECT__ starter\n' > "$dir/README.md"
  printf '%s\n' "$dir"
}

# sandbox + repo ปลอม acme/{api,admin,site} + starters.list ของ test
_repo_setup() {
  mk_sandbox
  local r
  for r in api admin site; do mk_fake_repo "acme/$r" "$(_mk_starter_tpl $r)"; done
  cat > "$SANDBOX/templates/starters.list" <<'EOF'
t-api    acme/api
t-admin  acme/admin
t-site   acme/site
t-suite = api:t-api admin:t-admin site:t-site
EOF
}

_new() { (cd "$SANDBOX" && bash scripts/create-project.sh "$@"); }

test_new_from_owner_repo() {
  _repo_setup
  _new shop-api acme/api >/dev/null
  local d="$SANDBOX/projects/shop-api"
  [ -f "$d/docker-compose.yml" ] && [ -f "$d/.env" ] && [ -f "$d/src/Dockerfile" ] \
    || { echo "    ✗ missing compose/.env/src"; return 1; }
  command grep -q 'routers.shop-api.rule' "$d/docker-compose.yml" || { echo "    ✗ __PROJECT__ not replaced in compose"; return 1; }
  command grep -qE '^[[:space:]]*build: \./src' "$d/docker-compose.yml" || { echo "    ✗ build not enabled"; return 1; }
  assert_eq "$(env_get APP_IMAGE "$d/.env")" shop-api:latest "APP_IMAGE"
  assert_eq "$(env_get REDIS_PASSWORD "$d/.env")" 'r&|\x' "__ROOT__ token"
  assert_eq "$(env_get DB_DATABASE "$d/.env")" shop-api_db "DB_DATABASE"
  assert_eq "$(env_get DB_RUNTIME_USER "$d/.env")" shop_api_rt "runtime user"
  assert_match "$(env_get KEYRING "$d/.env")" '^v1:[A-Za-z0-9+/]{43}=$' "b64 secret"
  assert_eq "$(env_get APP_DOMAIN "$d/.env")" CHANGE_ME "no suite → CHANGE_ME"
  assert_eq "$(env_get TRUSTED_PROXY_CIDRS "$d/.env")" CHANGE_ME "no docker → CHANGE_ME"
  # src/ ต้องไม่ถูกแตะ (โค้ดแอปจริง)
  command grep -q '__PROJECT__' "$d/src/deploy/infra-stack/README.md" || { echo "    ✗ src/ was modified"; return 1; }
}

test_new_from_alias() {
  _repo_setup
  _new blog t-admin >/dev/null
  [ -f "$SANDBOX/projects/blog/src/Dockerfile" ] || { echo "    ✗ alias not cloned"; return 1; }
}

test_new_repo_without_template_fails_cleanly() {
  _repo_setup
  mk_fake_repo acme/plain
  local out
  out="$(_new plain acme/plain 2>&1)" && { echo "    ✗ should fail"; return 1; }
  assert_contains "$out" "deploy/infra-stack" "explains what the repo needs"
  [ ! -e "$SANDBOX/projects/plain" ] || { echo "    ✗ projects/plain left behind"; return 1; }
}

test_new_rejects_dangerous_compose() {
  _repo_setup
  local tpl; tpl="$(_mk_starter_tpl api)"
  printf '    privileged: true\n' >> "$tpl/docker-compose.yml"
  mk_fake_repo acme/evil "$tpl"
  assert_fail "privileged compose rejected" _new evil acme/evil
  [ ! -e "$SANDBOX/projects/evil" ] || { echo "    ✗ projects/evil left behind"; return 1; }
}

test_new_repo_with_mysql_flag_rejected() {
  _repo_setup
  assert_fail "--mysql with repo template" _new shop-api acme/api --mysql
}

test_new_suite() {
  _repo_setup
  _new shop t-suite >/dev/null
  local r
  for r in api admin site; do
    [ -f "$SANDBOX/projects/shop-$r/docker-compose.yml" ] || { echo "    ✗ shop-$r missing"; return 1; }
    assert_eq "$(env_get API_URL "$SANDBOX/projects/shop-$r/.env")" https://shop-api.example.com/api/v1 "shop-$r api url"
  done
  assert_eq "$(env_get APP_DOMAIN "$SANDBOX/projects/shop-api/.env")" shop-api.example.com "api host"
  assert_eq "$(env_get APP_DOMAIN "$SANDBOX/projects/shop-site/.env")" shop.example.com "site host"
  assert_eq "$(cat "$SANDBOX/projects/shop.suite")" $'shop-api\nshop-admin\nshop-site' ".suite file"
}

test_new_suite_name_taken_creates_nothing() {
  _repo_setup
  mkdir -p "$SANDBOX/projects/shop-admin" && touch "$SANDBOX/projects/shop-admin/docker-compose.yml"
  assert_fail "suite with a taken name" _new shop t-suite
  [ ! -e "$SANDBOX/projects/shop-api" ] || { echo "    ✗ shop-api created anyway"; return 1; }
  [ ! -e "$SANDBOX/projects/shop.suite" ] || { echo "    ✗ .suite written"; return 1; }
}

test_new_suite_name_must_not_clash_with_project() {
  _repo_setup
  mkdir -p "$SANDBOX/projects/shop" && touch "$SANDBOX/projects/shop/docker-compose.yml"
  assert_fail "suite named like an existing project" _new shop t-suite
}

test_unknown_template_lists_starters() {
  _repo_setup
  local out; out="$(_new x nope 2>&1 || true)"
  assert_contains "$out" "t-suite" "lists suites"
  assert_contains "$out" "laravel" "lists built-in templates"
  [[ "$out" != *starters.list* ]] || { echo "    ✗ lists starters.list as a template"; return 1; }
}

test_new_suite_resumes_after_failure() {
  _repo_setup
  # admin ชี้ไป repo ที่ไม่มี → หยุดที่ shop-admin
  sed -i 's|^t-admin .*|t-admin  acme/missing|' "$SANDBOX/templates/starters.list"
  assert_fail "stops at the broken member" _new shop t-suite
  [ -f "$SANDBOX/projects/shop-api/docker-compose.yml" ] || { echo "    ✗ shop-api should exist"; return 1; }
  [ ! -f "$SANDBOX/projects/shop.suite" ] || { echo "    ✗ .suite must not be written yet"; return 1; }
  # แก้แล้วรันซ้ำ → ข้าม shop-api ทำต่อ
  sed -i 's|^t-admin .*|t-admin  acme/admin|' "$SANDBOX/templates/starters.list"
  local out; out="$(_new shop t-suite)"
  assert_contains "$out" "shop-api สร้างไว้แล้ว" "skips the member created before"
  assert_eq "$(cat "$SANDBOX/projects/shop.suite")" $'shop-api\nshop-admin\nshop-site' ".suite after resume"
  [ ! -e "$SANDBOX/projects/.shop.suite-pending" ] || { echo "    ✗ pending marker left"; return 1; }
}
