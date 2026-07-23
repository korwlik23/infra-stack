#!/usr/bin/env bash
# สร้าง project ใหม่จาก template
# ใช้: ./scripts/create-project.sh <name> <laravel|nextjs|n8n|ai-worker>
# ผลลัพธ์: projects/<name>/ พร้อม docker-compose.yml + .env (แก้ค่าแล้ว up ได้เลย)
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="${1:?usage: create-project.sh <name> <laravel|nextjs|n8n|ai-worker>}"
TEMPLATE="${2:?usage: create-project.sh <name> <laravel|nextjs|n8n|ai-worker>}"

[[ "$NAME" =~ ^[a-z0-9-]+$ ]] || { echo "ERROR: name must be lowercase [a-z0-9-]" >&2; exit 1; }
[ -d "templates/$TEMPLATE" ] || { echo "ERROR: unknown template '$TEMPLATE' (have: $(ls templates))" >&2; exit 1; }
# ยอมรับโฟลเดอร์ที่มีอยู่แล้ว (เช่น clone src/ ไว้ก่อน) — แต่ห้ามมี docker-compose.yml ซ้ำ
if [ -f "projects/$NAME/docker-compose.yml" ]; then
  echo "ERROR: projects/$NAME ถูก setup ไปแล้ว (มี docker-compose.yml)" >&2; exit 1
fi
if [ -d "projects/$NAME" ]; then
  echo "ℹ️  projects/$NAME มีอยู่แล้ว — เติมไฟล์จาก template โดยไม่แตะของเดิม (เช่น src/)"
fi

mkdir -p "projects/$NAME"
cp -r "templates/$TEMPLATE/." "projects/$NAME/"

# แทนที่ placeholder __PROJECT__ ทุกไฟล์ — ยกเว้น src/ (โค้ดแอปของจริง ห้ามแตะ)
find "projects/$NAME" -type d -name src -prune -o -type f -exec sed -i "s/__PROJECT__/$NAME/g" {} +

# เตรียม .env จาก example
if [ -f "projects/$NAME/.env.example" ]; then
  cp "projects/$NAME/.env.example" "projects/$NAME/.env"
fi

# เติมค่าจาก .env กลาง เข้า .env ของ project (token __ROOT:KEY__)
# ลดการพิมพ์ซ้ำ + typo — ค่าที่ share กัน (DB/Redis/domain) ดึงจากที่เดียว
# ⚠️ แทนที่เฉพาะไฟล์ .env (ค่าจริง) — .env.example คง token ไว้เป็นแม่แบบ
# ใช้ bash string replacement ล้วน (ไม่ใช้ sed) — รองรับรหัสผ่านที่มี & | \ ทุกแบบ
resolve_root_tokens() {
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
resolve_root_tokens "projects/$NAME/.env"

echo "✅ created projects/$NAME from template '$TEMPLATE'"
echo "   (ค่า DB/Redis/domain ดึงจาก .env กลางให้แล้ว — เหลือเฉพาะ per-project keys)"
echo "next:"
echo "  1. nano projects/$NAME/.env          # ตั้งเฉพาะที่เหลือ (APP_KEY, API keys, ฯลฯ)"
echo "  2. เปิด build: ./src ใน docker-compose.yml (ถ้า build บนเครื่อง)"
echo "  3. เพิ่ม DNS record: $NAME.<BASE_DOMAIN> → server IP (Cloudflare)"
echo "  4. ./scripts/deploy.sh $NAME"
