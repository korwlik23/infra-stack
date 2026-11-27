# shellcheck shell=bash
# แทน token ใน .env ของ project ใหม่ — ใช้โดย scripts/create-project.sh
# ต้องรันจาก root ของ infra-stack (อ่าน .env กลาง และ backup/scripts/project-db-lib.sh)
#
#   __ROOT:<KEY>__                  ค่า KEY จาก .env กลาง (ไม่มี/CHANGE_ME → CHANGE_ME + เตือน)
#   __DB_USER__ / __DB_PASSWORD__   user ของ project ใน Postgres กลาง + รหัสสุ่ม (ไม่ใช่ superuser — docs/31)
#   __GENERATE__                    secret สุ่มใหม่ต่อค่า (hex 48 ตัว)
# ⚠️ แทนที่เฉพาะไฟล์ .env (ค่าจริง) — .env.example คง token ไว้เป็นแม่แบบ

# เติมค่าจาก .env กลาง (token __ROOT:KEY__) — ค่าที่ share กัน (DB/Redis/domain) ดึงจากที่เดียว
# ใช้ bash string replacement ล้วน (ไม่ใช้ sed) — รองรับรหัสผ่านที่มี & | \ ทุกแบบ
tokens_resolve_root() {
  local penv="$1"
  [ -f "$penv" ] && [ -f .env ] || return 0
  # bash 5.2+ ตีความ & ในค่าแทนที่ของ ${//} เป็น "ข้อความที่ match" (เหมือน sed)
  # ปิดทิ้งเพื่อให้รหัสผ่านที่มี & ถูกแทนที่แบบ literal (bash <5.2 ไม่มี option นี้)
  shopt -u patsub_replacement 2>/dev/null || true
  local tokens tok key val content missing=""
  tokens="$(grep -oE '__ROOT:[A-Za-z0-9_]+__' "$penv" | sort -u || true)"
  [ -n "$tokens" ] || return 0
  content="$(cat "$penv")"
  while IFS= read -r tok; do
    [ -n "$tok" ] || continue
    key="${tok#__ROOT:}"; key="${key%__}"
    val="$(grep -E "^${key}=" .env | head -1 | cut -d= -f2- || true)"
    if [ -z "$val" ] || [ "$val" = "CHANGE_ME" ]; then
      val="CHANGE_ME"; missing="$missing $key"
    fi
    content="${content//$tok/$val}"   # bash literal replace — ปลอดภัยกับ & | \ ทุกแบบ
  done <<EOF
$tokens
EOF
  printf '%s\n' "$content" > "$penv"
  [ -z "$missing" ] || echo "⚠️  ไม่มีค่าใน .env กลาง (ตั้งเป็น CHANGE_ME):$missing"
}

# __DB_USER__ / __DB_PASSWORD__ = user ของ project นี้ใน Postgres กลาง (ไม่ใช่ superuser — docs/31)
# project หนึ่งโดนเจาะ → เข้าได้แค่ database ตัวเอง · role สร้างจริงตอน ensure_project_db (scripts/db-user.sh)
# --mysql / --external-db เขียนทับบรรทัดพวกนี้ทีหลังอยู่แล้ว
tokens_db_user() {
  local name="$1" penv="$2" role
  [ -f "$penv" ] && grep -q '__DB_USER__\|__DB_PASSWORD__' "$penv" || return 0
  penv() { :; }   # project-db-lib.sh ต้องมี penv — ใช้แค่ project_db_role_name
  # shellcheck source=backup/scripts/project-db-lib.sh
  . backup/scripts/project-db-lib.sh
  role="$(project_db_role_name "$name")"
  [ "$role" != "$(grep -E '^POSTGRES_USER=' .env 2>/dev/null | head -1 | cut -d= -f2- | tr -d ' ')" ] || role="${role}_app"
  sed -i -e "s/__DB_USER__/$role/g" -e "s/__DB_PASSWORD__/$(openssl rand -hex 24)/g" "$penv"
}

# __GENERATE__ = สุ่ม secret ใหม่ต่อค่า (เช่น N8N_ENCRYPTION_KEY) — ไม่ต้องพิมพ์ openssl เอง
# hex ล้วน → แทนด้วย sed ได้ปลอดภัย; ทีละบรรทัดเพื่อให้แต่ละค่าไม่ซ้ำกัน
tokens_generate() {
  local penv="$1"
  while grep -q '__GENERATE__' "$penv" 2>/dev/null; do
    sed -i "0,/__GENERATE__/s//$(openssl rand -hex 24)/" "$penv"
  done
}
