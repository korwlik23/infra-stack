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

echo "✅ created projects/$NAME from template '$TEMPLATE'"
echo "next:"
echo "  1. nano projects/$NAME/.env          # ใส่ค่าจริง"
echo "  2. cd projects/$NAME && docker compose up -d"
echo "  3. เพิ่ม DNS record: $NAME.<BASE_DOMAIN> → server IP (Cloudflare)"
