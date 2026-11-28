# shellcheck shell=bash
# แทน token ใน .env ของ project ใหม่ — ใช้โดย scripts/create-project.sh
# ต้องรันจาก root ของ infra-stack (อ่าน .env กลาง และ backup/scripts/project-db-lib.sh)
#
#   __ROOT:<KEY>__                  ค่า KEY จาก .env กลาง (ไม่มี/CHANGE_ME → CHANGE_ME + เตือน)
#   __DB_USER__ / __DB_PASSWORD__   user ของ project ใน Postgres กลาง + รหัสสุ่ม (ไม่ใช่ superuser — docs/31)
#   __DB_RUNTIME_USER__ / __DB_RUNTIME_PASSWORD__
#                                   user ของแอปตอนรัน (<role>_rt) — scripts/db-user.sh ให้แค่สิทธิ์อ่าน/เขียนข้อมูล
#   __GENERATE__                    secret สุ่มใหม่ต่อค่า (hex 48 ตัว)
#   __GENERATE_B64__                secret สุ่มใหม่ต่อค่า (32 byte เป็น base64 — สำหรับ keyring เช่น v1:<base64>)
#   __SUITE_ORIGIN:api|admin|site__ https://<suite>-api.<BASE_DOMAIN> / -admin / <suite>.<BASE_DOMAIN>
#   __SUITE_HOST:api|admin|site__   เหมือนบรรทัดบนแต่ไม่มี https:// (ใช้กับ APP_DOMAIN)
#   __PROXY_CIDR__                  subnet ของ docker network proxy (Traefik) — ใช้เป็น trusted proxy
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
  [ -f "$penv" ] && grep -q '__DB_USER__\|__DB_PASSWORD__\|__DB_RUNTIME_USER__\|__DB_RUNTIME_PASSWORD__' "$penv" || return 0
  penv() { :; }   # project-db-lib.sh ต้องมี penv — ใช้แค่ project_db_role_name
  # shellcheck source=backup/scripts/project-db-lib.sh
  . backup/scripts/project-db-lib.sh
  role="$(project_db_role_name "$name")"
  [ "$role" != "$(grep -E '^POSTGRES_USER=' .env 2>/dev/null | head -1 | cut -d= -f2- | tr -d ' ')" ] || role="${role}_app"
  # runtime ก่อน owner — __DB_USER__ ไม่ใช่ส่วนหนึ่งของ __DB_RUNTIME_USER__ แต่กันไว้ไม่ให้ลำดับสำคัญ
  sed -i -e "s/__DB_RUNTIME_USER__/${role}_rt/g" -e "s/__DB_RUNTIME_PASSWORD__/$(openssl rand -hex 24)/g" \
    -e "s/__DB_USER__/$role/g" -e "s/__DB_PASSWORD__/$(openssl rand -hex 24)/g" "$penv"
}

# __GENERATE__ = สุ่ม secret ใหม่ต่อค่า (เช่น N8N_ENCRYPTION_KEY) — ไม่ต้องพิมพ์ openssl เอง
# hex ล้วน → แทนด้วย sed ได้ปลอดภัย; ทีละบรรทัดเพื่อให้แต่ละค่าไม่ซ้ำกัน
# __GENERATE_B64__ มี / + = → แทนด้วย bash (ไม่ใช้ sed) ทีละตัว
tokens_generate() {
  local penv="$1" content
  while grep -q '__GENERATE__' "$penv" 2>/dev/null; do
    sed -i "0,/__GENERATE__/s//$(openssl rand -hex 24)/" "$penv"
  done
  grep -q '__GENERATE_B64__' "$penv" 2>/dev/null || return 0
  content="$(cat "$penv")"
  while [[ "$content" == *__GENERATE_B64__* ]]; do
    content="${content/__GENERATE_B64__/$(openssl rand -base64 32)}"
  done
  printf '%s\n' "$content" > "$penv"
}

# __SUITE_ORIGIN:<role>__ / __SUITE_HOST:<role>__ — URL ข้ามกันระหว่าง api / admin / site ของ suite เดียวกัน
# subdomain ชั้นเดียว (shop-api.example.com) — Cloudflare Universal SSL ครอบแค่ชั้นเดียว
# ไม่มี suite (สร้างทีละตัว) หรือไม่มี BASE_DOMAIN → CHANGE_ME ให้ตั้งเองด้วย infra env
tokens_suite() {
  local penv="$1" suite="${2:-}" base role host
  [ -f "$penv" ] && grep -qE '__SUITE_(ORIGIN|HOST):' "$penv" || return 0
  base="$(grep -E '^BASE_DOMAIN=' .env 2>/dev/null | head -1 | cut -d= -f2- | tr -d ' \r' || true)"
  for role in api admin site; do
    if [ -z "$suite" ] || [ -z "$base" ] || [ "$base" = CHANGE_ME ]; then
      sed -i -e "s|__SUITE_ORIGIN:${role}__|CHANGE_ME|g" -e "s|__SUITE_HOST:${role}__|CHANGE_ME|g" "$penv"
      continue
    fi
    case "$role" in site) host="$suite.$base" ;; *) host="$suite-$role.$base" ;; esac
    sed -i -e "s|__SUITE_ORIGIN:${role}__|https://$host|g" -e "s|__SUITE_HOST:${role}__|$host|g" "$penv"
  done
  if [ -z "$suite" ]; then
    echo "⚠️  URL ของ api/admin/site ตั้งเป็น CHANGE_ME (สร้างทีละตัว ไม่ใช่ suite) — ตั้งเองด้วย infra env"
  elif [ -z "$base" ] || [ "$base" = CHANGE_ME ]; then
    echo "⚠️  ไม่มี BASE_DOMAIN ใน .env กลาง — URL ของ suite ตั้งเป็น CHANGE_ME"
  fi
}

# __PROXY_CIDR__ = subnet ของ network proxy (Traefik อยู่ในนั้น) — แอปเชื่อ X-Forwarded-For จากช่วงนี้เท่านั้น
tokens_proxy_cidr() {
  local penv="$1" cidr
  [ -f "$penv" ] && grep -q '__PROXY_CIDR__' "$penv" || return 0
  cidr="$(docker network inspect proxy -f '{{(index .IPAM.Config 0).Subnet}}' 2>/dev/null || true)"
  # รับเฉพาะ IPv4 CIDR ที่ไม่ใช่ทั้งโลก — ผลแปลก ๆ ไม่ใส่ลงไฟล์
  if ! [[ "$cidr" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}/([89]|[12][0-9]|3[0-2])$ ]]; then
    cidr=CHANGE_ME
    echo "⚠️  อ่าน subnet ของ docker network proxy ไม่ได้ — TRUSTED_PROXY_CIDRS=CHANGE_ME"
    echo "    ตั้งเองทีหลัง: docker network inspect proxy → infra env <project>"
  fi
  sed -i "s|__PROXY_CIDR__|$cidr|g" "$penv"
}
