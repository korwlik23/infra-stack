#!/usr/bin/env bash
# Deploy project — zero-downtime rolling deploy อัตโนมัติเมื่อทำได้
# (ดู docs/25-zero-downtime.md) — CI/CD ฟรี ไม่ใช้ GitHub Actions
# ใช้: ./scripts/deploy.sh <project>
#
# โหมด image:
#   - มี projects/<name>/src/ (git clone ของ app) → git pull + build บนเครื่อง
#   - มี src/ แต่ไม่ใช่ git + compose เปิด build: → build จาก src/ ที่มี
#   - ไม่มี src/ → docker compose pull จาก registry
# โหมด deploy:
#   - .env มี ROLLOUT_SERVICE + มี docker-rollout plugin → rolling (เว็บไม่ดับ)
#   - ไม่งั้น → docker compose up -d (ดับสั้น ๆ ตอน recreate)
#   - service อื่น (queue/scheduler) ที่ยังรัน image เก่า → recreate ให้เสมอ
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"

NAME="${1:?usage: deploy.sh <project> [--seed|--no-seed]}"
# seed: ask (default) = ถามเมื่อ seeder ใหม่/เปลี่ยน · --seed = รันเลยไม่ถาม · --no-seed = ไม่รัน
SEED_MODE=ask
case "${2:-}" in
  --seed) SEED_MODE=yes ;;
  --no-seed) SEED_MODE=no ;;
  "") ;;
  *) echo "usage: deploy.sh <project> [--seed|--no-seed]" >&2; exit 1 ;;
esac
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
APP_IMAGE="$(grep -E '^APP_IMAGE=' .env 2>/dev/null | head -1 | cut -d= -f2- || true)"

# ── 0. เก็บ image ปัจจุบันเป็น :previous ก่อน build ใหม่ (ไว้ rollback) ──
# tag ไว้ = รอด docker image prune (prune ลบเฉพาะ image ที่ไม่มี tag)
if [ -n "$APP_IMAGE" ] && docker image inspect "$APP_IMAGE" >/dev/null 2>&1; then
  docker tag "$APP_IMAGE" "${APP_IMAGE%:*}:previous"
  echo "[deploy:$NAME] เก็บเวอร์ชันปัจจุบันเป็น ${APP_IMAGE%:*}:previous"
fi

# ── 1. เตรียม image ใหม่ ─────────────────────────────
if [ -d src/.git ]; then
  echo "[deploy:$NAME] pulling source…"
  BEFORE="$(git -C src rev-parse --short HEAD)"
  git -C src pull --ff-only
  AFTER="$(git -C src rev-parse --short HEAD)"
  echo "[deploy:$NAME] source $BEFORE → $AFTER"
  echo "[deploy:$NAME] building image on server…"
  docker compose build
elif [ -d src ] && grep -qE '^[[:space:]]*build:' docker-compose.yml; then
  # src/ เป็นไฟล์ที่ copy มาเอง (ไม่ใช่ git clone) — build จากที่มี ไม่ pull โค้ด
  # (เดิมตกไป docker compose pull → "pull access denied" เพราะ image ไม่มีใน registry)
  echo "[deploy:$NAME] src/ ไม่ใช่ git clone — building from local src/ (auto-deploy ใช้ไม่ได้จนกว่าจะ clone)…"
  docker compose build
else
  echo "[deploy:$NAME] pulling image from registry…"
  docker compose pull
fi

# ── 1.5 Migrate + seed ด้วยโค้ดใหม่ ก่อนสลับ traffic (opt-in: DEPLOY_MIGRATE=1) ─
# ทุก stack — คำสั่งตั้งใน .env ของ project (default = Laravel) ดู scripts/lib/deploy-db.sh
# shellcheck source=scripts/lib/deploy-db.sh
. "$ROOT/scripts/lib/deploy-db.sh"
deploy_db "$NAME" "${ROLLOUT_SERVICE:-$NAME-app}" "$SEED_MODE"

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

# up -d ไม่ recreate ถ้า tag ใน compose เท่าเดิม (APP_IMAGE=x:latest) แม้ image ข้างในเปลี่ยน
# → queue/scheduler ค้างโค้ดเก่า (เจอ 2026-10-31) — เทียบ image ที่ container รันกับที่ tag ชี้อยู่
STALE=""
for svc in $(docker compose ps --services); do
  for cid in $(docker compose ps -q "$svc"); do
    ref="$(docker inspect -f '{{.Config.Image}}' "$cid")"
    if [ "$(docker inspect -f '{{.Image}}' "$cid")" != "$(docker image inspect -f '{{.Id}}' "$ref" 2>/dev/null)" ]; then
      STALE="$STALE $svc"
      break
    fi
  done
done
if [ -n "$STALE" ]; then
  echo "[deploy:$NAME] recreating on new image:$STALE"
  # shellcheck disable=SC2086
  docker compose up -d --force-recreate --no-deps $STALE
fi

docker image prune -f >/dev/null
# จำ commit ที่ขึ้นเว็บจริงแล้ว — auto-deploy เทียบกับค่านี้ (ไม่ใช่ HEAD ของ src/ ที่ pull แล้วแต่ build อาจล้ม)
if [ -d src/.git ]; then
  git -C src rev-parse HEAD > .deploy-commit
  rm -f .deploy-failed .deploy-waiting
fi
echo "✅ [deploy:$NAME] done — $(date '+%F %T')"
