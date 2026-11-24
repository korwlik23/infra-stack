#!/usr/bin/env bash
# แยก database user ต่อ project (PostgreSQL) — project หนึ่งโดนเจาะ ไม่ลามไป database ของ project อื่น
# ใช้: infra db-user <project>          (หรือ ./scripts/db-user.sh <project>)
#      infra db-user --all              ทุก project ที่ยังใช้ superuser + restart ให้ (scripts/infra)
#      create-project.sh เรียกให้เองตอนสร้าง project ใหม่ (--quiet)
#      --needs = ไม่แก้อะไร · exit 0 ถ้า project นี้ยังต่อ Postgres กลางด้วย superuser
#
# ปัญหาเดิม (ก่อน v2.15): ทุก project ต่อ Postgres ด้วย POSTGRES_USER (superuser) ตัวเดียวกัน
#   → แอปเดียวโดน SQL injection / RCE = อ่าน/ลบได้ทุก database + สั่งคำสั่งบนเครื่องผ่าน COPY … PROGRAM
# script นี้ (รันซ้ำได้):
#   1. .env ของ project ยังใช้ superuser → สร้าง role ชื่อตาม project + รหัสสุ่ม แล้วแก้ .env ให้
#      .env ใช้ role ของตัวเองอยู่แล้ว → สร้าง role ถ้ายังไม่มี (รหัสจาก .env) / ไม่แตะรหัสถ้ามีแล้ว
#   2. role เป็นเจ้าของ database + schema public + ทุกตาราง/sequence/view/function/type ข้างใน
#   3. role อื่นที่ไม่ใช่ superuser connect database นี้ไม่ได้ (REVOKE CONNECT FROM PUBLIC)
#   4. ทดสอบ login ด้วย user/รหัสใหม่จริงก่อนจบ
# เว็บที่รันอยู่ไม่สะดุด: superuser ยังใช้ได้ตามเดิม — container เปลี่ยนไปใช้ user ใหม่หลัง infra restart <project>
# MySQL (--mysql) แยก user ต่อ project อยู่แล้ว · --external-db = ข้าม
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")/.."
ROOT="$PWD"

USAGE="usage: db-user.sh <project> [--quiet|--needs]"
NAME="${1:?$USAGE}"
QUIET=0; NEEDS=0
case "${2:-}" in --quiet) QUIET=1 ;; --needs) NEEDS=1 ;; "") ;; *) echo "$USAGE" >&2; exit 1 ;; esac
PENV="$ROOT/projects/$NAME/.env"
[ -f "$PENV" ] || { echo "ERROR: ไม่มี $PENV" >&2; exit 1; }

env_val() { grep -E "^$1=" "$ROOT/.env" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '\r' | sed -E 's/^"(.*)"$/\1/' || true; }
penv() { grep -E "^$1=" "$PENV" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '\r' | sed -E 's/^"(.*)"$/\1/; s/^'"'"'(.*)'"'"'$/\1/' || true; }
say() { echo "[db-user:$NAME] $*"; }

# shellcheck source=backup/scripts/project-db-lib.sh
. "$ROOT/backup/scripts/project-db-lib.sh"
if ! project_db_resolve; then [ "$NEEDS" = 0 ] || exit 1; exit 0; fi
if [ "$NEEDS" = 1 ]; then
  [ "$DB_ENGINE" = postgres ] || exit 1
  SUPER="$(env_val POSTGRES_USER)"; project_db_creds
  [ -z "$DB_USER" ] || [ "$DB_USER" = "${SUPER:-infra}" ]
  exit
fi
if [ "$DB_ENGINE" = mysql ]; then
  say "MySQL — แยก user ต่อ project อยู่แล้ว (สร้างตอน infra new … --mysql) ไม่ต้องทำอะไร"
  exit 0
fi
[[ "$DB_NAME" =~ ^[a-z0-9_-]+$ ]] || { echo "ERROR: ชื่อ database '$DB_NAME' ไม่ถูกต้อง" >&2; exit 1; }

SUPER="$(env_val POSTGRES_USER)"; SUPER="${SUPER:-infra}"
# SQL ทาง stdin — รหัสไม่โผล่ใน argument (ps) · -tA = ผลเป็นค่าเปล่า ๆ
pg() { docker exec -i postgres psql -U "$SUPER" -d "${1:-postgres}" -v ON_ERROR_STOP=1 -qtA; }

project_db_creds
NEW_PASS=""
if [ -z "$DB_USER" ] || [ "$DB_USER" = "$SUPER" ]; then
  ROLE="$(project_db_role_name "$NAME")"
  [ "$ROLE" != "$SUPER" ] || ROLE="${ROLE}_app"
  NEW_PASS="$(openssl rand -hex 24)"   # hex ล้วน — ใส่ใน URL / SQL ได้โดยไม่ต้อง escape
  say "ตอนนี้ต่อ database ด้วย superuser ($SUPER) → เปลี่ยนเป็น user ของ project: $ROLE"
else
  ROLE="$DB_USER"
fi
[[ "$ROLE" =~ ^[a-z_][a-z0-9_]*$ ]] || {
  echo "ERROR: ชื่อ user '$ROLE' ใช้ไม่ได้ (ต้องเป็น a-z 0-9 _ ขึ้นต้นด้วยตัวอักษร) — แก้ใน infra env $NAME" >&2; exit 1; }

ATTR="$(echo "SELECT rolsuper FROM pg_roles WHERE rolname = '$ROLE'" | pg)"
if [ -n "$NEW_PASS" ]; then
  if [ "$ATTR" = t ]; then
    # ชื่อชนกับ superuser ที่มีอยู่ — ห้ามลดสิทธิ์ของคนอื่นเงียบ ๆ
    echo "ERROR: มี user ชื่อ $ROLE ที่เป็น superuser อยู่แล้ว — ตั้งชื่ออื่นเอง: DB_USERNAME=<ชื่อ> ใน infra env $NAME แล้วรันซ้ำ" >&2
    exit 1
  elif [ -n "$ATTR" ]; then
    echo "ALTER ROLE \"$ROLE\" WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD '$NEW_PASS';" | pg
  else
    echo "CREATE ROLE \"$ROLE\" WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD '$NEW_PASS';" | pg
  fi
elif [ -z "$ATTR" ]; then
  # .env ระบุ user ที่ยังไม่มีใน Postgres (project ใหม่จาก create-project.sh / ย้ายมาจากเครื่องอื่น)
  [ -n "$DB_PASS" ] || { echo "ERROR: ไม่มีรหัสของ $ROLE ใน .env (DB_PASSWORD / DATABASE_URL)" >&2; exit 1; }
  case "$DB_PASS" in *%*)
    echo "ERROR: รหัสใน DATABASE_URL ถูก URL-encode (%) — ตั้ง user ${ROLE} เองด้วย infra psql แล้วรันซ้ำ" >&2; exit 1 ;;
  esac
  q="'"
  echo "CREATE ROLE \"$ROLE\" WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD '${DB_PASS//$q/$q$q}';" | pg
  say "✅ สร้าง user $ROLE (รหัสตาม .env)"
elif [ "$ATTR" = t ]; then
  echo "ERROR: user $ROLE เป็น superuser — ใช้ไม่ได้ (ต้องเป็น user ธรรมดา) · แก้: ลบ DB_USERNAME/user ใน DATABASE_URL ออกจาก .env แล้วรันซ้ำ" >&2
  exit 1
fi

# เจ้าของ database + ทุก object ข้างใน · ปิด role อื่นไม่ให้ connect
say "ตั้ง $ROLE เป็นเจ้าของ database '$DB_NAME' + ตาราง/sequence/function ทั้งหมด…"
pg <<SQL
ALTER DATABASE "$DB_NAME" OWNER TO "$ROLE";
REVOKE CONNECT, TEMPORARY ON DATABASE "$DB_NAME" FROM PUBLIC;
GRANT CONNECT, TEMPORARY ON DATABASE "$DB_NAME" TO "$ROLE";
SQL
{ echo 'BEGIN;'; pg_reown_sql "$ROLE"; echo 'COMMIT;'; } | pg "$DB_NAME"

# แก้ .env — ทีละบรรทัดด้วย bash (ไม่ใช้ sed: รหัสเดิมมีอักขระพิเศษได้) · เขียนไฟล์ใหม่สิทธิ์ 600 แล้วค่อยแทน
if [ -n "$NEW_PASS" ]; then
  TMP="$(mktemp "$PENV.XXXXXX")"
  chmod 600 "$TMP"
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      DB_USERNAME=*) line="DB_USERNAME=$ROLE" ;;
      DB_PASSWORD=*) line="DB_PASSWORD=$NEW_PASS" ;;
      DATABASE_URL=*://*@postgres[:/]*)
        v="${line#DATABASE_URL=}"; scheme="${v%%://*}"; rest="${v#*://}"; rest="${rest##*@}"
        line="DATABASE_URL=$scheme://$ROLE:$NEW_PASS@$rest" ;;
    esac
    printf '%s\n' "$line"
  done < "$PENV" > "$TMP"
  mv "$TMP" "$PENV"
  DB_PASS="$NEW_PASS"
  say "✅ แก้ projects/$NAME/.env ให้ใช้ user $ROLE แล้ว"
fi

# ทดสอบ login จริงผ่าน TCP (ใช้รหัส ไม่ใช่ trust ของ local socket) — รหัสส่งทาง stdin
if printf '%s' "$DB_PASS" | docker exec -i postgres sh -c \
     'PGPASSWORD="$(cat)" psql -h 127.0.0.1 -U "$1" -d "$2" -qtAc "SELECT 1"' sh "$ROLE" "$DB_NAME" >/dev/null 2>&1; then
  say "✅ ทดสอบ login ด้วย $ROLE ผ่าน"
else
  echo "❌ [db-user:$NAME] login ด้วย $ROLE ไม่ผ่าน — container ยังใช้ค่าเดิมอยู่ (เว็บไม่กระทบ)" >&2
  echo "   ตรวจรหัสใน infra env $NAME แล้วรันซ้ำ: infra db-user $NAME" >&2
  exit 1
fi

if [ "$QUIET" = 0 ] && [ -n "$NEW_PASS" ]; then
  if [ -n "$(cd "$ROOT/projects/$NAME" && docker compose ps -q 2>/dev/null)" ]; then
    echo ""
    echo "เหลือขั้นเดียว — ให้ container ใช้ user ใหม่ (rolling ถ้ามี ROLLOUT_SERVICE เว็บไม่ดับ):"
    echo "  infra restart $NAME"
    echo "  แอปที่ cache config ไว้ใน image (เช่น config:cache ตอน build) ใช้: infra deploy $NAME"
  fi
fi
