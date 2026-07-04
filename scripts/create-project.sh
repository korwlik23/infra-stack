#!/usr/bin/env bash
# สร้าง project ใหม่จาก template
# ใช้: ./scripts/create-project.sh <name> <laravel|nextjs|n8n>
# ผลลัพธ์: projects/<name>/ พร้อม docker-compose.yml + .env (แก้ค่าแล้ว up ได้เลย)
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="${1:?usage: create-project.sh <name> <laravel|nextjs|n8n>}"
TEMPLATE="${2:?usage: create-project.sh <name> <laravel|nextjs|n8n>}"

[[ "$NAME" =~ ^[a-z0-9-]+$ ]] || { echo "ERROR: name must be lowercase [a-z0-9-]" >&2; exit 1; }
[ -d "templates/$TEMPLATE" ] || { echo "ERROR: unknown template '$TEMPLATE' (have: $(ls templates))" >&2; exit 1; }
[ ! -e "projects/$NAME" ] || { echo "ERROR: projects/$NAME already exists" >&2; exit 1; }

mkdir -p "projects/$NAME"
cp -r "templates/$TEMPLATE/." "projects/$NAME/"

# แทนที่ placeholder __PROJECT__ ทุกไฟล์
find "projects/$NAME" -type f -exec sed -i "s/__PROJECT__/$NAME/g" {} +

# เตรียม .env จาก example
if [ -f "projects/$NAME/.env.example" ]; then
  cp "projects/$NAME/.env.example" "projects/$NAME/.env"
fi

echo "✅ created projects/$NAME from template '$TEMPLATE'"
echo "next:"
echo "  1. nano projects/$NAME/.env          # ใส่ค่าจริง"
echo "  2. cd projects/$NAME && docker compose up -d"
echo "  3. เพิ่ม DNS record: $NAME.<BASE_DOMAIN> → server IP (Cloudflare)"
