#!/usr/bin/env bash
# Deploy project หนึ่งตัว — CI/CD แบบไม่ใช้ GitHub Actions (build บนเครื่องเอง ฟรี)
# ใช้: ./scripts/deploy.sh <project>
#
# สองโหมดอัตโนมัติ:
#   1. มี projects/<name>/src/ (git clone ของ app) → git pull + docker compose build
#   2. ไม่มี src/ → docker compose pull (ใช้ pre-built image จาก registry)
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="${1:?usage: deploy.sh <project>}"
DIR="projects/$NAME"
[ -f "$DIR/docker-compose.yml" ] || { echo "ERROR: $DIR not found (create with create-project.sh)" >&2; exit 1; }

cd "$DIR"

if [ -d src/.git ]; then
  echo "[deploy:$NAME] pulling source…"
  BEFORE="$(git -C src rev-parse HEAD)"
  git -C src pull --ff-only
  AFTER="$(git -C src rev-parse HEAD)"
  echo "[deploy:$NAME] $BEFORE → $AFTER"
  echo "[deploy:$NAME] building image on server…"
  docker compose build
else
  echo "[deploy:$NAME] pulling image from registry…"
  docker compose pull
fi

echo "[deploy:$NAME] restarting…"
docker compose up -d

# queue/scheduler containers รันโค้ดเก่าค้างใน memory — force restart
for C in "$NAME-queue" "$NAME-scheduler"; do
  docker ps -q -f "name=^${C}$" | grep -q . && docker restart "$C" >/dev/null && echo "[deploy:$NAME] restarted $C"
done || true

docker image prune -f >/dev/null
echo "✅ [deploy:$NAME] done — $(date '+%F %T')"
