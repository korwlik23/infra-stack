#!/usr/bin/env bash
# อัปเดต image ของ stack ที่เลือกแบบ manual (ปลอดภัยกว่า auto ทั้งหมด)
# ใช้: ./scripts/update.sh [core|database|monitoring|all]
set -euo pipefail

cd "$(dirname "$0")/.."
TARGET="${1:-all}"

update_stack() {
  local file="$1"
  echo "── updating $file ──"
  docker compose --env-file .env -f "$file" pull
  docker compose --env-file .env -f "$file" up -d
}

case "$TARGET" in
  core)       update_stack docker/docker-compose.core.yml ;;
  database)
    echo "⚠️  Database update — ควร backup ก่อน (./scripts/backup.sh)"
    read -rp "Type 'yes' to continue: " OK; [ "$OK" = "yes" ] || exit 1
    update_stack docker/docker-compose.database.yml ;;
  monitoring) update_stack docker/docker-compose.monitoring.yml ;;
  all)
    update_stack docker/docker-compose.core.yml
    update_stack docker/docker-compose.monitoring.yml
    echo "ℹ️  database stack ข้ามไว้ — รัน './scripts/update.sh database' แยก" ;;
  *) echo "usage: $0 [core|database|monitoring|all]" >&2; exit 1 ;;
esac

echo "pruning unused images…"
docker image prune -f
echo "✅ done"
