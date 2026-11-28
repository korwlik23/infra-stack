# shellcheck shell=bash
# หา database ของ project จาก projects/<name>/.env — ใช้ร่วมโดย project-db-backup.sh / project-db-restore.sh / scripts/db-user.sh
# ต้องมี: NAME, penv() (อ่านค่าใน .env ของ project)
# project_db_resolve → ตั้ง DB_ENGINE (postgres|mysql) + DB_NAME แล้ว return 0
#                     database ไม่ได้อยู่ในเครื่องนี้ / ไม่มี database → บอกเหตุผลแล้ว return 1

project_db_resolve() {
  local url host db
  host="$(penv DB_HOST)"
  db="$(penv DB_DATABASE)"
  url="$(penv DATABASE_URL)"
  # DATABASE_URL (nextjs / go): scheme://user:pass@host:port/db?params
  if [ -n "$url" ] && [ "$url" != CHANGE_ME ]; then
    local rest="${url#*://}"
    rest="${rest##*@}"                  # ตัด user:pass@ (รหัสมี @ ได้ → ตัดถึง @ ตัวสุดท้าย)
    [ -n "$host" ] || host="${rest%%[:/]*}"
    if [ -z "$db" ] || [ "$db" = CHANGE_ME ]; then
      db="${rest#*/}"; db="${db%%\?*}"
      [ "$db" != "$rest" ] || db=""
    fi
  fi

  # n8n: host/database อยู่ใน docker-compose.yml (DB_POSTGRESDB_HOST=postgres) ไม่ใช่ .env
  local compose="${ROOT:-.}/projects/$NAME/docker-compose.yml"
  if [ -z "$host" ] && [ -z "$url" ] && grep -qE 'DB_POSTGRESDB_HOST[=:][[:space:]]*postgres([[:space:]]|$)' "$compose" 2>/dev/null; then
    host=postgres
    if [ -z "$db" ]; then
      db="$(grep -oE 'DB_DATABASE:-[a-z0-9_-]+' "$compose" | head -1 | cut -d- -f2-)"   # ${DB_DATABASE:-n8n_db} → n8n_db
    fi
  fi
  case "$host" in
    postgres) DB_ENGINE=postgres ;;
    mysql)    DB_ENGINE=mysql ;;
    "")       echo "[db:$NAME] ไม่มี DB_HOST / DATABASE_URL — project นี้ไม่มี database ในเครื่อง ข้าม"; return 1 ;;
    *)        echo "[db:$NAME] database อยู่ที่ '$host' (ไม่ใช่ container ในเครื่องนี้) — ข้าม · backup ฝั่งนั้นเอง (docs/26)"; return 1 ;;
  esac
  if [ -z "$db" ] || [ "$db" = CHANGE_ME ]; then
    echo "[db:$NAME] หาชื่อ database ไม่เจอ (DB_DATABASE / DATABASE_URL) — ข้าม"
    return 1
  fi
  if [ "$(docker inspect -f '{{.State.Running}}' "$DB_ENGINE" 2>/dev/null || true)" != "true" ]; then
    echo "[db:$NAME] ERROR: container $DB_ENGINE ไม่ได้รันอยู่" >&2
    exit 1
  fi
  DB_NAME="$db"
  return 0
}

# ── user ของ database (แยกต่อ project — scripts/db-user.sh) ─────────────
# project_db_creds → ตั้ง DB_USER / DB_PASS จาก DB_USERNAME/DB_PASSWORD หรือ user:pass ใน DATABASE_URL
project_db_creds() {
  local url rest userinfo
  DB_USER="$(penv DB_USERNAME)"
  DB_PASS="$(penv DB_PASSWORD)"
  url="$(penv DATABASE_URL)"
  if [ -z "$DB_USER" ] && [[ "$url" == *://*@* ]]; then
    rest="${url#*://}"
    userinfo="${rest%@*}"               # รหัสมี @ ได้ → ตัดที่ @ ตัวสุดท้าย
    DB_USER="${userinfo%%:*}"
    DB_PASS=""
    [[ "$userinfo" != *:* ]] || DB_PASS="${userinfo#*:}"
  fi
}

# ชื่อ role ของ project ใน Postgres: my-app → my_app (ขึ้นต้นด้วยตัวเลข → p_3dshop)
project_db_role_name() {
  local r="${1//-/_}"
  [[ ! "$r" =~ ^[0-9] ]] || r="p_$r"
  printf '%s' "${r:0:63}"
}

# SQL: ให้ role เป็นเจ้าของ schema public + ทุก object ข้างใน (ตาราง / sequence / view / function / type)
# ใช้หลัง restore (superuser สร้าง object ใหม่ → เจ้าของเป็น superuser แอปแก้ตารางไม่ได้) และตอนย้าย project เดิม
# ข้าม object ของ extension และ sequence ที่ผูกกับคอลัมน์ (ย้ายตามตารางเอง)
# role ต้องผ่าน ^[a-z_][a-z0-9_]*$ ก่อนเรียก (ต่อเข้า SQL ตรง ๆ)
pg_reown_sql() {
  local role="$1"
  cat <<SQL
DO \$reown\$
DECLARE r record;
BEGIN
  EXECUTE format('ALTER SCHEMA public OWNER TO %I', '$role');
  FOR r IN
    SELECT c.oid::regclass AS obj, c.relkind
      FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p', 'v', 'm', 'S', 'f')
       AND NOT EXISTS (SELECT 1 FROM pg_catalog.pg_depend d
                        WHERE d.classid = 'pg_catalog.pg_class'::regclass AND d.objid = c.oid
                          AND (d.deptype = 'e' OR (c.relkind = 'S' AND d.deptype IN ('a', 'i'))))
  LOOP
    EXECUTE format('ALTER %s %s OWNER TO %I',
      CASE r.relkind WHEN 'v' THEN 'VIEW' WHEN 'm' THEN 'MATERIALIZED VIEW'
                     WHEN 'S' THEN 'SEQUENCE' WHEN 'f' THEN 'FOREIGN TABLE' ELSE 'TABLE' END,
      r.obj, '$role');
  END LOOP;
  FOR r IN
    SELECT p.oid::regprocedure AS fn
      FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND NOT EXISTS (SELECT 1 FROM pg_catalog.pg_depend d
                        WHERE d.classid = 'pg_catalog.pg_proc'::regclass AND d.objid = p.oid AND d.deptype = 'e')
  LOOP
    EXECUTE format('ALTER ROUTINE %s OWNER TO %I', r.fn, '$role');
  END LOOP;
  FOR r IN
    SELECT t.oid::regtype AS typ
      FROM pg_catalog.pg_type t JOIN pg_catalog.pg_namespace n ON n.oid = t.typnamespace
     WHERE n.nspname = 'public'
       AND (t.typtype IN ('e', 'd', 'r')
            OR (t.typtype = 'c' AND (SELECT c.relkind FROM pg_catalog.pg_class c WHERE c.oid = t.typrelid) = 'c'))
       AND NOT EXISTS (SELECT 1 FROM pg_catalog.pg_depend d
                        WHERE d.classid = 'pg_catalog.pg_type'::regclass AND d.objid = t.oid AND d.deptype = 'e')
  LOOP
    EXECUTE format('ALTER TYPE %s OWNER TO %I', r.typ, '$role');
  END LOOP;
END
\$reown\$;
SQL
}

# SQL: สิทธิ์ของ runtime role (DB_RUNTIME_USER — scripts/db-user.sh) — อ่าน/เขียนข้อมูล ไม่แก้โครงสร้าง
# รันใน database ของ project · default privileges ผูกกับ schema public → หลัง DROP SCHEMA (restore) ต้องรันใหม่
# ทั้งสอง role ต้องผ่าน ^[a-z_][a-z0-9_]*$ ก่อนเรียก (ต่อเข้า SQL ตรง ๆ)
pg_runtime_grant_sql() {
  local owner="$1" rt="$2"
  cat <<SQL
GRANT USAGE ON SCHEMA public TO "$rt";
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO "$rt";
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO "$rt";
ALTER DEFAULT PRIVILEGES FOR ROLE "$owner" IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO "$rt";
ALTER DEFAULT PRIVILEGES FOR ROLE "$owner" IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO "$rt";
SQL
}
