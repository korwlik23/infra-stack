#!/usr/bin/env bash
# Deploy project — zero-downtime rolling deploy อัตโนมัติเมื่อทำได้
# (ดู docs/25-zero-downtime.md) — CI/CD ฟรี ไม่ใช้ GitHub Actions
# ใช้: ./scripts/deploy.sh <project>
#
# โหมด image:
#   - มี projects/<name>/src/ (git clone ของ app) → git pull + build บนเครื่อง
#   - ไม่มี src/ → docker compose pull จาก registry
# โหมด deploy:
#   - .env มี ROLLOUT_SERVICE + มี docker-rollout plugin → rolling (เว็บไม่ดับ)
#   - ไม่งั้น → docker compose up -d (ดับสั้น ๆ ตอน recreate)
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="${1:?usage: deploy.sh <project>}"
DIR="projects/$NAME"
if [ ! -d "$DIR" ]; then
  echo "ERROR: $DIR ไม่มีอยู่ — สร้างก่อน: ./scripts/create-project.sh $NAME <laravel|nextjs|n8n|ai-worker>" >&2
  exit 1
elif [ ! -f "$DIR/docker-compose.yml" ]; then
  echo "ERROR: $DIR มีโฟลเดอร์แต่ไม่มี docker-compose.yml (สร้างด้วยมือ? ข้าม create-project.sh?)" >&2
  echo "       แก้: ./scripts/create-project.sh $NAME <template> — ถ้ามี src/ อยู่แล้วจะถูกเก็บไว้" >&2
  exit 1
fi

cd "$DIR"

ROLLOUT_SERVICE="$(grep -E '^ROLLOUT_SERVICE=' .env 2>/dev/null | head -1 | cut -d= -f2- || true)"

# ── 1. เตรียม image ใหม่ ─────────────────────────────
if [ -d src/.git ]; then
  echo "[deploy:$NAME] pulling source…"
  BEFORE="$(git -C src rev-parse --short HEAD)"
  git -C src pull --ff-only
  AFTER="$(git -C src rev-parse --short HEAD)"
  echo "[deploy:$NAME] source $BEFORE → $AFTER"
  echo "[deploy:$NAME] building image on server…"
  docker compose build
else
  echo "[deploy:$NAME] pulling image from registry…"
  docker compose pull
fi

# ── 2. สลับเวอร์ชัน ──────────────────────────────────
# เช็คไฟล์ plugin ตรง ๆ — `docker rollout --help` exit 0 แม้ไม่มี plugin (Docker 29)
if [ -n "$ROLLOUT_SERVICE" ] && [ -x "$HOME/.docker/cli-plugins/docker-rollout" ]; then
  echo "[deploy:$NAME] rolling deploy '$ROLLOUT_SERVICE' (zero downtime)…"
  # เปิดตัวใหม่คู่ตัวเก่า → รอ healthcheck ผ่าน → ถอดตัวเก่า
  # ถ้าตัวใหม่ไม่ healthy: rollout ล้ม ตัวเก่ายังรับ traffic ต่อ (เว็บไม่ดับ)
  docker rollout "$ROLLOUT_SERVICE"
else
  if [ -n "$ROLLOUT_SERVICE" ]; then
    echo "[deploy:$NAME] ⚠️ docker-rollout plugin not found — falling back to restart deploy"
    echo "               (install: rerun ./install.sh or see docs/25-zero-downtime.md)"
  fi
fi

# ── 3. อัปเดต service ที่เหลือ (queue/scheduler ฯลฯ) ─
# ตัวที่ rollout ไปแล้ว config ตรง compose อยู่แล้ว → up -d ไม่แตะซ้ำ
echo "[deploy:$NAME] updating remaining services…"
docker compose up -d

docker image prune -f >/dev/null
echo "✅ [deploy:$NAME] done — $(date '+%F %T')"
