#!/usr/bin/env bash
# ทางลัดรัน artisan ใน container ของ project — รันจากที่ไหนก็ได้ ไม่ต้องจำคำสั่งยาว
# (แทน alias ที่หายทุกครั้งที่ ssh ใหม่)
#
# ใช้: ./scripts/artisan.sh <project> <artisan-args...>
# เช่น: ./scripts/artisan.sh zennuaflow migrate --force
#       ./scripts/artisan.sh automation-ai-seller-chat db:seed --force
#       ./scripts/artisan.sh zennuaflow optimize:clear
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="${1:?usage: artisan.sh <project> <artisan-args...>}"
shift
[ -f "projects/$NAME/docker-compose.yml" ] || { echo "ERROR: projects/$NAME not found" >&2; exit 1; }

docker compose --project-directory "projects/$NAME" exec "$NAME-app" php artisan "$@"
