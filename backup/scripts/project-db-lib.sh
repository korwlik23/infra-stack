# shellcheck shell=bash
# หา database ของ project จาก projects/<name>/.env — ใช้ร่วมโดย project-db-backup.sh / project-db-restore.sh
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
