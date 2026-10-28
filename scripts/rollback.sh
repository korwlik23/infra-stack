#!/usr/bin/env bash
# Rollback project กลับไป image tag ก่อนหน้า (zero-downtime ถ้ามี rollout)
# ใช้: ./scripts/rollback.sh <project> <image-tag>
# เช่น: ./scripts/rollback.sh app v1.4.2
#
# ⚠️ rollback ได้เฉพาะ "โค้ด" — database migration ที่รันไปแล้วไม่ย้อนอัตโนมัติ
#    (นี่คือเหตุผลที่ migration ต้องเป็นแบบ expand/contract — docs/25-zero-downtime.md)
set -euo pipefail
cd "$(dirname "$0")/.."

# tag ที่ใช้บ่อยสุดคือ "previous" — deploy.sh เก็บเวอร์ชันก่อนหน้าไว้ให้อัตโนมัติ
# เช่น: ./scripts/rollback.sh app previous
NAME="${1:?usage: rollback.sh <project> <image-tag>  (เช่น tag=previous)}"
TAG="${2:?usage: rollback.sh <project> <image-tag>  (เช่น tag=previous)}"
DIR="projects/$NAME"
[ -f "$DIR/.env" ] || { echo "ERROR: $DIR/.env not found" >&2; exit 1; }

cd "$DIR"

CURRENT="$(grep -E '^APP_IMAGE=' .env | head -1 | cut -d= -f2-)"
[ -n "$CURRENT" ] || { echo "ERROR: APP_IMAGE not set in $DIR/.env" >&2; exit 1; }
BASE="${CURRENT%:*}"
TARGET="$BASE:$TAG"

[ "$TARGET" != "$CURRENT" ] || { echo "ERROR: APP_IMAGE ใช้ tag '$TAG' อยู่แล้ว" >&2; exit 1; }

echo "[rollback:$NAME] $CURRENT ← $TARGET"
read -rp "Type 'rollback' to continue: " CONFIRM
[ "$CONFIRM" = "rollback" ] || { echo "aborted"; exit 1; }

# image เป้าหมายต้องอยู่บนเครื่อง — ไม่มี (เช่น tag เวอร์ชันบน registry) ค่อย pull
docker image inspect "$TARGET" >/dev/null 2>&1 || docker pull "$TARGET"

# ชี้ tag ที่ compose ใช้ (APP_IMAGE) ไปที่ image เก่า — ไม่แก้ .env
# (เดิมแก้ APP_IMAGE=…:previous ค้างใน .env → deploy ถัดไป build ทับ :previous
#  ทำ image ดีตัวสุดท้ายหาย และโหมด registry pull …:previous ไม่เจอ)
docker tag "$TARGET" "$CURRENT"

ROLLOUT_SERVICE="$(grep -E '^ROLLOUT_SERVICE=' .env 2>/dev/null | head -1 | cut -d= -f2- || true)"
if [ -n "$ROLLOUT_SERVICE" ] && [ -x "$HOME/.docker/cli-plugins/docker-rollout" ]; then
  echo "[rollback:$NAME] rolling back '$ROLLOUT_SERVICE' (zero downtime)…"
  docker rollout "$ROLLOUT_SERVICE"
fi
# ไม่ pull — ถ้า pull จะได้ :latest ตัวที่พังกลับมาทับ
docker compose up -d

echo "✅ [rollback:$NAME] $CURRENT = image ของ $TARGET แล้ว — $(date '+%F %T')"
echo "ℹ️  deploy ครั้งถัดไปจะ build/pull เวอร์ชันใหม่ทับ tag นี้ตามปกติ — แก้โค้ดก่อน push"
echo "⚠️  ถ้าเวอร์ชันใหม่รัน migration ไปแล้ว เช็ค schema ว่าโค้ดเก่ายังอ่านได้"
