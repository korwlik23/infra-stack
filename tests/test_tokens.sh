# shellcheck shell=bash
# token ใน .env ของ project (scripts/lib/project-tokens.sh)

_tokens_setup() {
  mk_sandbox
  cd "$SANDBOX"
  # shellcheck source=scripts/lib/project-tokens.sh
  . scripts/lib/project-tokens.sh
  PENV="$SANDBOX/projects/t.env"
}

test_generate_b64_each_value_unique() {
  _tokens_setup
  printf 'A=v1:__GENERATE_B64__\nB=v1:__GENERATE_B64__\n' > "$PENV"
  tokens_generate "$PENV"
  local a b
  a="$(env_get A "$PENV")"; b="$(env_get B "$PENV")"
  assert_match "$a" '^v1:[A-Za-z0-9+/]{43}=$' "A is base64 of 32 bytes"
  assert_match "$b" '^v1:[A-Za-z0-9+/]{43}=$' "B is base64 of 32 bytes"
  [ "$a" != "$b" ] || { echo "    ✗ A and B must differ"; return 1; }
}

test_generate_hex_still_works_next_to_b64() {
  _tokens_setup
  printf 'H=__GENERATE__\nK=v1:__GENERATE_B64__\n' > "$PENV"
  tokens_generate "$PENV"
  assert_match "$(env_get H "$PENV")" '^[0-9a-f]{48}$' "hex token"
  assert_match "$(env_get K "$PENV")" '^v1:[A-Za-z0-9+/]{43}=$' "b64 token"
}

test_db_runtime_user() {
  _tokens_setup
  printf 'DB_USERNAME=__DB_USER__\nDB_PASSWORD=__DB_PASSWORD__\nDB_RUNTIME_USER=__DB_RUNTIME_USER__\nDB_RUNTIME_PASSWORD=__DB_RUNTIME_PASSWORD__\n' > "$PENV"
  tokens_db_user my-shop "$PENV"
  assert_eq "$(env_get DB_USERNAME "$PENV")" my_shop "owner role"
  assert_eq "$(env_get DB_RUNTIME_USER "$PENV")" my_shop_rt "runtime role"
  assert_match "$(env_get DB_RUNTIME_PASSWORD "$PENV")" '^[0-9a-f]{48}$' "runtime password"
  [ "$(env_get DB_RUNTIME_PASSWORD "$PENV")" != "$(env_get DB_PASSWORD "$PENV")" ] \
    || { echo "    ✗ runtime and owner passwords must differ"; return 1; }
}

test_db_runtime_user_alone() {
  _tokens_setup
  printf 'DB_RUNTIME_USER=__DB_RUNTIME_USER__\nDB_RUNTIME_PASSWORD=__DB_RUNTIME_PASSWORD__\n' > "$PENV"
  tokens_db_user shop "$PENV"
  assert_eq "$(env_get DB_RUNTIME_USER "$PENV")" shop_rt "runtime role without owner token"
}

test_suite_origins_and_hosts() {
  _tokens_setup
  cat > "$PENV" <<'EOF'
API=__SUITE_ORIGIN:api__/api/v1
ADMIN=__SUITE_ORIGIN:admin__
SITE=__SUITE_ORIGIN:site__
H_API=__SUITE_HOST:api__
H_SITE=__SUITE_HOST:site__
EOF
  tokens_suite "$PENV" shop >/dev/null
  assert_eq "$(env_get API "$PENV")" https://shop-api.example.com/api/v1 "api origin"
  assert_eq "$(env_get ADMIN "$PENV")" https://shop-admin.example.com "admin origin"
  assert_eq "$(env_get SITE "$PENV")" https://shop.example.com "site origin"
  assert_eq "$(env_get H_API "$PENV")" shop-api.example.com "api host"
  assert_eq "$(env_get H_SITE "$PENV")" shop.example.com "site host"
}

test_suite_tokens_without_suite_become_change_me() {
  _tokens_setup
  printf 'API=__SUITE_ORIGIN:api__/api/v1\nH=__SUITE_HOST:admin__\n' > "$PENV"
  local out
  out="$(tokens_suite "$PENV" "")"
  assert_eq "$(env_get API "$PENV")" CHANGE_ME/api/v1 "origin without suite"
  assert_eq "$(env_get H "$PENV")" CHANGE_ME "host without suite"
  assert_contains "$out" "CHANGE_ME" "warns about CHANGE_ME"
}

test_proxy_cidr_from_docker() {
  _tokens_setup
  printf '#!/usr/bin/env bash\necho 172.20.0.0/16\n' > "$SANDBOX/bin/docker"
  printf 'TRUSTED_PROXY_CIDRS=__PROXY_CIDR__\n' > "$PENV"
  tokens_proxy_cidr "$PENV" >/dev/null
  assert_eq "$(env_get TRUSTED_PROXY_CIDRS "$PENV")" 172.20.0.0/16 "cidr"
}

test_proxy_cidr_without_docker() {
  _tokens_setup
  printf 'TRUSTED_PROXY_CIDRS=__PROXY_CIDR__\n' > "$PENV"
  local out
  out="$(tokens_proxy_cidr "$PENV")"
  assert_eq "$(env_get TRUSTED_PROXY_CIDRS "$PENV")" CHANGE_ME "cidr without docker"
  assert_contains "$out" "proxy" "warns"
}

test_proxy_cidr_rejects_garbage() {
  _tokens_setup
  printf '#!/usr/bin/env bash\necho "0.0.0.0/0; rm -rf /"\n' > "$SANDBOX/bin/docker"
  printf 'TRUSTED_PROXY_CIDRS=__PROXY_CIDR__\n' > "$PENV"
  tokens_proxy_cidr "$PENV" >/dev/null
  assert_eq "$(env_get TRUSTED_PROXY_CIDRS "$PENV")" CHANGE_ME "non-cidr output ignored"
}

test_suite_base_domain_with_crlf() {
  _tokens_setup
  printf 'BASE_DOMAIN=example.com\r\n' > .env
  printf 'H=__SUITE_HOST:api__\n' > "$PENV"
  tokens_suite "$PENV" shop >/dev/null
  assert_eq "$(env_get H "$PENV")" shop-api.example.com ".env กลางแบบ CRLF"
}
