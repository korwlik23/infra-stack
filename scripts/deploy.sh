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
DEPLOY_MIGRATE="$(grep -E '^DEPLOY_MIGRATE=' .env 2>/dev/null | head -1 | cut -d= -f2- || true)"
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

# ── 1.5 Migrate ก่อนสลับ traffic (opt-in ต่อ project ด้วย DEPLOY_MIGRATE=1) ─
# รันด้วย image ใหม่ที่เพิ่ง build บน container ชั่วคราว — ทำ "ก่อน" rollout เสมอ
# เพื่อให้ schema พร้อมก่อนโค้ดใหม่รับ traffic (กัน 500 แบบที่เจอ 2026-07-12)
# ⚠️ migration ต้องเป็น expand/contract — ระหว่าง rolling โค้ดเก่ายังรันกับ schema ใหม่ได้
# ถ้า migrate ล้ม: set -e หยุดทันที ไม่ rollout → เว็บเก่ายังอยู่
if [ "$DEPLOY_MIGRATE" = "1" ]; then
  MIGRATE_SVC="${ROLLOUT_SERVICE:-$NAME-app}"
  echo "[deploy:$NAME] running migrations on '$MIGRATE_SVC'…"
  docker compose run --rm --no-deps --entrypoint php "$MIGRATE_SVC" artisan migrate --force

  # ── 1.6 Seed — ถามเมื่อ seeder ใหม่หรือเปลี่ยนจาก deploy ครั้งก่อน ──
  # db:seed เติมข้อมูลลง DB เดิม ไม่ล้างตาราง (ไม่ใช่ migrate:fresh) — seeder จึงต้องรันซ้ำได้
  # (firstOrCreate / updateOrCreate / upsert) ไม่งั้นข้อมูลซ้ำทุกครั้งที่ seed
  # จำ hash ของไฟล์ seeder ที่ seed/ตอบไปแล้วใน .deploy-seeders.sha256 — ไม่เปลี่ยน = ไม่ถามซ้ำ
  SEED_STATE=.deploy-seeders.sha256
  CURRENT_SEEDERS="$(docker compose run --rm --no-deps -T --entrypoint sh "$MIGRATE_SVC" -c \
    '[ -d database/seeders ] && find database/seeders -type f -name "*.php" | sort | xargs sha256sum' 2>/dev/null || true)"
  if [ -n "$CURRENT_SEEDERS" ]; then
    CHANGED="$(printf '%s\n' "$CURRENT_SEEDERS" | grep -vxF -f "$SEED_STATE" 2>/dev/null | awk '{print $2}' || true)"
    [ -f "$SEED_STATE" ] || CHANGED="$(printf '%s\n' "$CURRENT_SEEDERS" | awk '{print $2}')"
    run_seed=no
    if [ "$SEED_MODE" = yes ]; then
      run_seed=yes
    elif [ "$SEED_MODE" = ask ] && [ -n "$CHANGED" ]; then
      echo "[deploy:$NAME] seeder $([ -f "$SEED_STATE" ] && echo 'ใหม่/เปลี่ยน' || echo 'ยังไม่เคย seed บนเครื่องนี้'):"
      printf '%s\n' "$CHANGED" | sed 's/^/    /'
      if [ -t 0 ]; then
        read -r -p "[deploy:$NAME] รัน db:seed ด้วยไหม? (เติมข้อมูล ไม่ล้าง DB เดิม) [y/N] " answer || answer=""
        case "$answer" in
          [Yy]*) run_seed=yes ;;
          *) printf '%s\n' "$CURRENT_SEEDERS" > "$SEED_STATE"
             echo "[deploy:$NAME] ข้าม seed — จะถามอีกเมื่อ seeder เปลี่ยน (รันเอง: ./scripts/deploy.sh $NAME --seed)" ;;
        esac
      else
        # auto-deploy (cron) ไม่มีคนตอบ — ไม่ seed เอง และไม่จำ hash เพื่อให้ deploy มือครั้งหน้าถามอีก
        echo "[deploy:$NAME] ⚠️ ไม่มีคนตอบ (auto-deploy) — ยังไม่ seed: รัน ./scripts/deploy.sh $NAME --seed เมื่อพร้อม"
      fi
    fi
    if [ "$run_seed" = yes ]; then
      echo "[deploy:$NAME] running db:seed on '$MIGRATE_SVC' (ไม่ล้างข้อมูลเดิม)…"
      docker compose run --rm --no-deps --entrypoint php "$MIGRATE_SVC" artisan db:seed --force
      printf '%s\n' "$CURRENT_SEEDERS" > "$SEED_STATE"
    fi
  fi
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
echo "✅ [deploy:$NAME] done — $(date '+%F %T')"
