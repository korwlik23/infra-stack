# shellcheck shell=bash
# scripts/db-user.sh — ไม่มี Postgres ใน test: stub docker จด SQL ที่ส่งเข้า psql ไว้ใน $SQL_LOG
# (ตรวจว่าส่งคำสั่งอะไร · การทำงานจริงของสิทธิ์ทดสอบบน VPS — plan Task A12)

_dbuser_setup() {
  mk_sandbox
  SQL_LOG="$SANDBOX/sql.log"
  cat > "$SANDBOX/bin/docker" <<EOF
#!/usr/bin/env bash
# inspect → postgres รันอยู่ · exec … psql → จด stdin + argument · query คืนค่าว่าง (role ยังไม่มี)
case "\$1 \$2" in
  inspect*) echo true ;;
  "exec -i") { echo "-- \$*"; cat; echo; } >> "$SQL_LOG" ;;   # psql ที่รับ SQL ทาง stdin
  exec*) case "\$*" in *pg_dump*) echo "-- fake dump" ;; esac ;; # ไม่อ่าน stdin — ไม่งั้นค้าง
esac
exit 0
EOF
  chmod +x "$SANDBOX/bin/docker"
  mkdir -p "$SANDBOX/projects/shop-api"
}

_write_env() { printf '%s\n' "$@" > "$SANDBOX/projects/shop-api/.env"; }

test_runtime_role_granted_dml_only() {
  _dbuser_setup
  _write_env DB_HOST=postgres DB_DATABASE=shop_api_db DB_USERNAME=shop_api DB_PASSWORD=ownerpw \
    DB_RUNTIME_USER=shop_api_rt DB_RUNTIME_PASSWORD=rtpw
  (cd "$SANDBOX" && bash scripts/db-user.sh shop-api --quiet >/dev/null)
  local sql; sql="$(cat "$SQL_LOG")"
  assert_contains "$sql" 'CREATE ROLE "shop_api_rt" WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT PASSWORD '"'"'rtpw'"'" "create runtime role"
  assert_contains "$sql" 'GRANT CONNECT ON DATABASE "shop_api_db" TO "shop_api_rt"' "connect"
  assert_contains "$sql" 'GRANT USAGE ON SCHEMA public TO "shop_api_rt"' "schema usage"
  assert_contains "$sql" 'GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO "shop_api_rt"' "dml on tables"
  assert_contains "$sql" 'GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO "shop_api_rt"' "sequences"
  assert_contains "$sql" 'ALTER DEFAULT PRIVILEGES FOR ROLE "shop_api" IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO "shop_api_rt"' "default privileges tables"
  assert_contains "$sql" 'ALTER DEFAULT PRIVILEGES FOR ROLE "shop_api" IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO "shop_api_rt"' "default privileges sequences"
  assert_contains "$sql" 'psql -h 127.0.0.1 -U "$1" -d "$2"' "login test runs"
  [[ "$sql" != *'OWNER TO "shop_api_rt"'* ]] || { echo "    ✗ runtime role must never own anything"; return 1; }
}

test_no_runtime_key_no_runtime_sql() {
  _dbuser_setup
  _write_env DB_HOST=postgres DB_DATABASE=shop_api_db DB_USERNAME=shop_api DB_PASSWORD=ownerpw
  (cd "$SANDBOX" && bash scripts/db-user.sh shop-api --quiet >/dev/null)
  [[ "$(cat "$SQL_LOG")" != *_rt* ]] || { echo "    ✗ runtime SQL without DB_RUNTIME_USER"; return 1; }
}

test_runtime_role_must_differ_from_owner() {
  _dbuser_setup
  _write_env DB_HOST=postgres DB_DATABASE=shop_api_db DB_USERNAME=shop_api DB_PASSWORD=ownerpw \
    DB_RUNTIME_USER=shop_api DB_RUNTIME_PASSWORD=rtpw
  assert_fail "runtime == owner" bash -c "cd '$SANDBOX' && bash scripts/db-user.sh shop-api --quiet"
}

test_runtime_role_name_validated() {
  _dbuser_setup
  _write_env DB_HOST=postgres DB_DATABASE=shop_api_db DB_USERNAME=shop_api DB_PASSWORD=ownerpw \
    'DB_RUNTIME_USER=x";DROP ROLE infra;--' DB_RUNTIME_PASSWORD=rtpw
  assert_fail "bad runtime role name" bash -c "cd '$SANDBOX' && bash scripts/db-user.sh shop-api --quiet"
  [[ "$(cat "$SQL_LOG" 2>/dev/null)" != *'DROP ROLE'* ]] || { echo "    ✗ bad name reached SQL"; return 1; }
}

test_runtime_password_quote_escaped() {
  _dbuser_setup
  _write_env DB_HOST=postgres DB_DATABASE=shop_api_db DB_USERNAME=shop_api DB_PASSWORD=ownerpw \
    DB_RUNTIME_USER=shop_api_rt "DB_RUNTIME_PASSWORD=a'b"
  (cd "$SANDBOX" && bash scripts/db-user.sh shop-api --quiet >/dev/null)
  assert_contains "$(cat "$SQL_LOG")" "PASSWORD 'a''b'" "single quote doubled"
}

# restore ล้าง schema public + dump ไม่มี GRANT (--no-privileges) → ต้องให้สิทธิ์ runtime role ใหม่
test_restore_reapplies_runtime_grants() {
  _dbuser_setup
  _write_env DB_HOST=postgres DB_DATABASE=shop_api_db DB_USERNAME=shop_api DB_PASSWORD=ownerpw \
    DB_RUNTIME_USER=shop_api_rt DB_RUNTIME_PASSWORD=rtpw
  local dest="$SANDBOX/backup/archives/pre-deploy/shop-api"
  mkdir -p "$dest"
  echo "-- dump" | gzip > "$dest/shop-api_20260101_000000.sql.gz"
  (cd "$SANDBOX" && bash backup/scripts/project-db-restore.sh --yes shop-api >/dev/null)
  local sql; sql="$(cat "$SQL_LOG")"
  assert_contains "$sql" 'ALTER SCHEMA public OWNER TO' "owner restored"
  assert_contains "$sql" 'GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO "shop_api_rt"' "runtime grants after restore"
  assert_contains "$sql" 'ALTER DEFAULT PRIVILEGES FOR ROLE "shop_api" IN SCHEMA public' "default privileges after restore"
}

test_restore_without_runtime_user_unchanged() {
  _dbuser_setup
  _write_env DB_HOST=postgres DB_DATABASE=shop_api_db DB_USERNAME=shop_api DB_PASSWORD=ownerpw
  local dest="$SANDBOX/backup/archives/pre-deploy/shop-api"
  mkdir -p "$dest"
  echo "-- dump" | gzip > "$dest/shop-api_20260101_000000.sql.gz"
  (cd "$SANDBOX" && bash backup/scripts/project-db-restore.sh --yes shop-api >/dev/null)
  [[ "$(cat "$SQL_LOG")" != *_rt* ]] || { echo "    ✗ runtime SQL without DB_RUNTIME_USER"; return 1; }
}
