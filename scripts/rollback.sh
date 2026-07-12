#!/usr/bin/env bash
# Rollback project กลับไป image tag ก่อนหน้า (zero-downtime ถ้ามี rollout)
# ใช้: ./scripts/rollback.sh <project> <image-tag>
# เช่น: ./scripts/rollback.sh zennuaflow v1.4.2
#
# ⚠️ rollback ได้เฉพาะ "โค้ด" — database migration ที่รันไปแล้วไม่ย้อนอัตโนมัติ
#    (นี่คือเหตุผลที่ migration ต้องเป็นแบบ expand/contract — docs/25-zero-downtime.md)
set -euo pipefail
cd "$(dirname "$0")/.."

# tag ที่ใช้บ่อยสุดคือ "previous" — deploy.sh เก็บเวอร์ชันก่อนหน้าไว้ให้อัตโนมัติ
# เช่น: ./scripts/rollback.sh automation-ai-seller-chat previous
NAME="${1:?usage: rollback.sh <project> <image-tag>  (เช่น tag=previous)}"
TAG="${2:?usage: rollback.sh <project> <image-tag>  (เช่น tag=previous)}"
DIR="projects/$NAME"
[ -f "$DIR/.env" ] || { echo "ERROR: $DIR/.env not found" >&2; exit 1; }

cd "$DIR"

CURRENT="$(grep -E '^APP_IMAGE=' .env | head -1 | cut -d= -f2-)"
[ -n "$CURRENT" ] || { echo "ERROR: APP_IMAGE not set in $DIR/.env" >&2; exit 1; }
BASE="${CURRENT%:*}"
TARGET="$BASE:$TAG"

echo "[rollback:$NAME] $CURRENT → $TARGET"
read -rp "Type 'rollback' to continue: " CONFIRM
[ "$CONFIRM" = "rollback" ] || { echo "aborted"; exit 1; }

sed -i "s|^APP_IMAGE=.*|APP_IMAGE=$TARGET|" .env

# image อาจอยู่บนเครื่องแล้ว (โหมด build-on-server) — pull ล้มไม่เป็นไร
docker compose pull 2>/dev/null || true

ROLLOUT_SERVICE="$(grep -E '^ROLLOUT_SERVICE=' .env 2>/dev/null | head -1 | cut -d= -f2- || true)"
if [ -n "$ROLLOUT_SERVICE" ] && [ -x "$HOME/.docker/cli-plugins/docker-rollout" ]; then
  echo "[rollback:$NAME] rolling back '$ROLLOUT_SERVICE' (zero downtime)…"
  docker rollout "$ROLLOUT_SERVICE"
fi
docker compose up -d

echo "✅ [rollback:$NAME] now on $TARGET — $(date '+%F %T')"
echo "⚠️  ถ้าเวอร์ชันใหม่รัน migration ไปแล้ว เช็ค schema ว่าโค้ดเก่ายังอ่านได้"
