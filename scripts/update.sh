#!/usr/bin/env bash
# อัปเดต image ของ stack ที่เลือกแบบ manual (ปลอดภัยกว่า auto ทั้งหมด)
# ใช้: ./scripts/update.sh [<stack>|all]      (หรือ infra update …)
#   stack = docker/docker-compose.<stack>.yml — core, database, mysql, monitoring, tools, messaging, storage
#   all   = core + monitoring + stack อื่นที่เปิดอยู่ — ยกเว้น database / mysql (ต้องสั่งแยก มี gate ให้ backup ก่อน)
set -euo pipefail

cd "$(dirname "$0")/.."
TARGET="${1:-all}"

update_stack() {
  local file="docker/docker-compose.$1.yml"
  echo "── updating $1 ──"
  docker compose --env-file .env -f "$file" pull
  docker compose --env-file .env -f "$file" up -d
}

running() { [ -n "$(docker ps -q --filter "label=com.docker.compose.project=infra-$1" 2>/dev/null)" ]; }

case "$TARGET" in
  database|mysql)
    echo "⚠️  $TARGET update — ควร backup ก่อน (infra backup)"
    read -rp "Type 'yes' to continue: " OK; [ "$OK" = "yes" ] || exit 1
    update_stack "$TARGET" ;;
  all)
    update_stack core
    update_stack monitoring
    for s in tools messaging storage; do
      if running "$s"; then update_stack "$s"; fi
    done
    echo "ℹ️  database / mysql stack ข้ามไว้ — รัน 'infra update database' (หรือ mysql) แยก" ;;
  *)
    if [ ! -f "docker/docker-compose.$TARGET.yml" ]; then
      echo "usage: $0 [core|database|mysql|monitoring|tools|messaging|storage|all]" >&2; exit 1
    fi
    update_stack "$TARGET" ;;
esac

echo "pruning unused images…"
docker image prune -f
echo "✅ done"
