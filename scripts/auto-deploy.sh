#!/usr/bin/env bash
# Auto deploy — poll git ของทุก project ที่มี src/ ถ้ามี commit ใหม่ → deploy
# ฟรี 100% ไม่ต้องใช้ GitHub Actions / ไม่ต้องเปิด webhook endpoint
#
# ตั้ง cron (ทุก 2 นาที):
#   */2 * * * * /opt/infra-stack/scripts/auto-deploy.sh >> /var/log/infra-deploy.log 2>&1
set -euo pipefail
cd "$(dirname "$0")/.."

for SRC in projects/*/src; do
  [ -d "$SRC/.git" ] || continue
  NAME="$(basename "$(dirname "$SRC")")"

  git -C "$SRC" fetch --quiet
  LOCAL="$(git -C "$SRC" rev-parse HEAD)"
  REMOTE="$(git -C "$SRC" rev-parse '@{u}' 2>/dev/null || echo "$LOCAL")"

  if [ "$LOCAL" != "$REMOTE" ]; then
    echo "[auto-deploy] $NAME: new commits ($LOCAL → $REMOTE) — deploying…"
    ./scripts/deploy.sh "$NAME"
  fi
done
