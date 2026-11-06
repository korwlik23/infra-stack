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
#   - มี ROLLOUT_SERVICE แต่ไม่มี plugin + เว็บรันอยู่ → หยุด (ไม่ restart แบบเว็บดับ)
#     ยอมดับเอง: DEPLOY_ALLOW_DOWNTIME=1 infra deploy <project>
#   - ไม่มี ROLLOUT_SERVICE (n8n / worker) → docker compose up -d (ดับสั้น ๆ ตอน recreate)
#   - service อื่น (queue/scheduler) ที่ยังรัน image เก่า → recreate ให้เสมอ
# กันพัง (ค่าใน projects/<name>/.env — docs/25):
#   - key ใหม่ใน src/.env.example ที่ยังไม่มีใน .env → หยุดก่อน build (DEPLOY_ENV_IGNORE="KEY …" = ข้าม)
#   - smoke test หลังสลับเวอร์ชัน (DEPLOY_SMOKE=0 = ปิด · DEPLOY_SMOKE_PATHS="/login /api/x" = เช็คเพิ่ม)
#   - smoke ล้ม + DEPLOY_AUTO_ROLLBACK=1 → ถอยกลับ :previous ให้เอง (ไม่ย้อน migration)
# แจ้ง Telegram ทุกผล (lib/notify.sh) — สำเร็จ / smoke ล้ม / rollback / ล้มก่อนขึ้นเว็บ
#   ปิดข้อความ "สำเร็จ": NOTIFY_DEPLOY_SUCCESS=0 ใน .env กลาง
# exit: 0 = ขึ้นเว็บแล้ว · 3 = ขึ้นเว็บแล้วแต่ smoke ล้ม · 4 = smoke ล้ม → rollback แล้ว
#       อื่น ๆ = ล้ม (เว็บยังเป็นเวอร์ชันเดิม ยกเว้นล้มหลังสลับ — ข้อความบอก)
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
# shellcheck source=scripts/lib/notify.sh
. "$ROOT/scripts/lib/notify.sh"

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
  echo "ERROR: $DIR ไม่มีอยู่ — สร้างก่อน: infra new $NAME <laravel|nextjs|go|n8n|ai-worker>" >&2
  exit 1
elif [ ! -f "$DIR/docker-compose.yml" ]; then
  echo "ERROR: $DIR มีโฟลเดอร์แต่ไม่มี docker-compose.yml (สร้างด้วยมือ? ข้าม create-project.sh?)" >&2
  echo "       แก้: infra new $NAME <template> — ถ้ามี src/ อยู่แล้วจะถูกเก็บไว้" >&2
  exit 1
fi

cd "$DIR"

# ── lock ต่อ project — deploy ตัวเดียวกันทีละครั้ง ─────
# infra deploy มือ ชนกับ auto-deploy (cron) → git pull / build / docker rollout / migrate ซ้อนกัน
# ตัวที่มาทีหลังรอจนตัวแรกจบ แล้ว deploy ต่อ (project อื่นไม่ต้องรอ — lock แยกต่อโฟลเดอร์)
# fd 8: auto-deploy.sh ใช้ fd 9 เป็น lock ของตัวเอง (สืบทอดมาถึง process นี้)
exec 8>.deploy.lock
if ! flock -n 8; then
  echo "[deploy:$NAME] ⏳ มี deploy ของ $NAME กำลังรันอยู่ — รอให้จบก่อน…"
  flock 8
fi

penv() { grep -E "^$1=" .env 2>/dev/null | head -1 | cut -d= -f2- | tr -d '\r' | sed -E 's/^"(.*)"$/\1/' || true; }
ROLLOUT_SERVICE="$(penv ROLLOUT_SERVICE)"
APP_IMAGE="$(penv APP_IMAGE)"
HAS_ROLLOUT=0
# เช็คไฟล์ plugin ตรง ๆ — `docker rollout --help` exit 0 แม้ไม่มี plugin (Docker 29)
[ -x "$HOME/.docker/cli-plugins/docker-rollout" ] && HAS_ROLLOUT=1
TRIGGER="มือ ($(id -un))"
[ "${DEPLOY_TRIGGER:-}" = auto ] && TRIGGER="auto-deploy"

# ── รายงานผล — ทุกทางออกผ่านที่นี่ ─────────────────────
# STEP = ขั้นที่กำลังทำ (ล้มแล้วบอกได้ว่าตรงไหน) · SWITCHED = สลับ traffic ไปตัวใหม่แล้ว
STEP="เตรียม"
SWITCHED=0
FAIL_DETAIL=""
# จำ commit ที่ล้ม — auto-deploy ไม่ลองซ้ำทุก 2 นาที (deploy มือยังรันได้เสมอ)
# ใช้ @{u} (commit ล่าสุดที่ fetch มา = ตัวที่ auto-deploy เทียบ) — ล้มก่อน pull ก็จำถูกตัว
mark_failed() {
  [ -d src/.git ] || return 0
  { git -C src rev-parse '@{u}' 2>/dev/null || git -C src rev-parse HEAD; } > .deploy-failed
}
commit_info() {   # "<sha> <author>: <subject>" ของ src/ ตอนนี้
  [ -d src/.git ] || return 0
  git -C src log -1 --format='%h %an: %s' 2>/dev/null | cut -c1-120 || true
}
on_exit() {
  local rc=$? where
  # 0 / 3 / 4 รายงานไปแล้วตรงจุดนั้น
  case "$rc" in 0|3|4) return ;; esac
  mark_failed
  if [ "$SWITCHED" = 1 ]; then
    where="⚠️ ล้มหลังสลับเวอร์ชัน — เว็บอาจเป็นเวอร์ชันใหม่แล้ว ตรวจ: infra check $NAME"
  else
    where="เว็บยังเป็นเวอร์ชันเดิม"
  fi
  echo "❌ [deploy:$NAME] ล้มตอน: $STEP — $where" >&2
  notify "❌ $NAME deploy ล้มตอน: $STEP — $where
$(commit_info)${FAIL_DETAIL:+
$FAIL_DETAIL}
ดู log: infra logs auto-deploy (หรือจอที่สั่ง deploy) · แก้แล้ว push ใหม่ หรือ: infra deploy $NAME
โดย: $TRIGGER"
}
trap on_exit EXIT

# ── กันเว็บดับ: มี ROLLOUT_SERVICE แต่ไม่มี plugin ─────
# เดิม fallback เป็น docker compose up -d = ถอดตัวเก่าก่อนตัวใหม่พร้อม + ไม่มี healthcheck gate
# ตัวใหม่ crash = เว็บล่ม → หยุดแทน (deploy ครั้งแรกยังไม่มีอะไรให้ดับ → ทำต่อได้)
if [ -n "$ROLLOUT_SERVICE" ] && [ "$HAS_ROLLOUT" = 0 ] \
   && [ -n "$(docker compose ps -q "$ROLLOUT_SERVICE" 2>/dev/null)" ] \
   && [ "${DEPLOY_ALLOW_DOWNTIME:-$(penv DEPLOY_ALLOW_DOWNTIME)}" != 1 ]; then
  STEP="ตรวจ docker-rollout"
  FAIL_DETAIL="ไม่มี docker-rollout plugin — deploy ต่อ = เว็บดับและไม่มี healthcheck gate
ติดตั้ง: รัน ./install.sh ซ้ำ (docs/25) · ยอมดับครั้งนี้: DEPLOY_ALLOW_DOWNTIME=1 infra deploy $NAME"
  echo "[deploy:$NAME] ❌ $FAIL_DETAIL" >&2
  exit 1
fi

# ── 0. เก็บ image ปัจจุบันเป็น :previous ก่อน build ใหม่ (ไว้ rollback) ──
# tag ไว้ = รอด docker image prune (prune ลบเฉพาะ image ที่ไม่มี tag)
HAS_PREVIOUS=0
if [ -n "$APP_IMAGE" ] && docker image inspect "$APP_IMAGE" >/dev/null 2>&1; then
  docker tag "$APP_IMAGE" "${APP_IMAGE%:*}:previous"
  HAS_PREVIOUS=1
  echo "[deploy:$NAME] เก็บเวอร์ชันปัจจุบันเป็น ${APP_IMAGE%:*}:previous"
fi

# key ใน .env.example (KEY=… / export KEY=…) — อ่านจาก stdin
example_keys() { sed -nE 's/^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)=.*/\2/p' | sort -u; }

# ── 1.0 ตรวจ .env ก่อน build — key ใหม่ที่ app ต้องใช้แต่ยังไม่ได้ใส่บนเครื่องนี้ ─
# หยุดเฉพาะ key ที่ "เพิ่มใน .env.example ตั้งแต่ deploy ล่าสุด" (= dev เพิ่ม env ใหม่แล้วลืมบอก)
# key เก่าที่ขาด (ใช้ค่า default ของ app ได้) แค่เตือน — ไม่งั้น project เดิมจะ deploy ไม่ได้ทั้งหมด
check_env() {
  local base="$1" ignore all new key missing_new="" missing_old=""
  [ -f src/.env.example ] || return 0
  [ "$(penv DEPLOY_ENV_CHECK)" != 0 ] || return 0
  ignore=" $(penv DEPLOY_ENV_IGNORE) "
  all="$(example_keys < src/.env.example)"
  new=""
  # เทียบได้เฉพาะเมื่อ commit เดิมมี .env.example — ไม่มี (เพิ่งเพิ่มไฟล์ / history ถูก force-push) = แค่เตือน
  if [ -n "$base" ] && [ -d src/.git ] && git -C src cat-file -e "$base:.env.example" 2>/dev/null; then
    new="$(comm -13 <(git -C src show "$base:.env.example" | example_keys) <(printf '%s\n' "$all"))"
  fi
  for key in $all; do
    grep -qE "^[[:space:]]*(export[[:space:]]+)?$key=" .env 2>/dev/null && continue
    [[ "$ignore" == *" $key "* ]] && continue
    if printf '%s\n' "$new" | grep -qxF "$key"; then missing_new="$missing_new $key"
    else missing_old="$missing_old $key"; fi
  done
  [ -z "$missing_old" ] || echo "[deploy:$NAME] ℹ️  key ใน src/.env.example ที่ไม่มีใน .env (app ใช้ค่า default):$missing_old"
  # ค่าเชื่อมต่อ database ที่ยังไม่ได้ตั้ง (create-project --external-db) — deploy ไปก็ต่อไม่ได้
  for key in DATABASE_URL DB_HOST; do
    [ "$(penv "$key")" != CHANGE_ME ] || missing_new="$missing_new $key(=CHANGE_ME)"
  done
  if [ -n "$missing_new" ]; then
    FAIL_DETAIL="ยังไม่ได้ตั้งค่าใน projects/$NAME/.env:$missing_new
ใส่ค่า: infra env $NAME แล้ว infra deploy $NAME (ไม่ใช้ key นั้น: DEPLOY_ENV_IGNORE=\"KEY …\")"
    echo "[deploy:$NAME] ❌ $FAIL_DETAIL" >&2
    return 1
  fi
}

# ── 1. เตรียม image ใหม่ ─────────────────────────────
if [ -d src/.git ]; then
  STEP="git pull"
  echo "[deploy:$NAME] pulling source…"
  BEFORE="$(git -C src rev-parse HEAD)"
  # base ของการเทียบ .env.example = commit ที่ขึ้นเว็บล่าสุด (ไม่ใช่ HEAD — pull แล้ว build ล้มก็ยังเทียบถูก)
  ENV_BASE="$(cat .deploy-commit 2>/dev/null || echo "$BEFORE")"
  if ! git -C src pull --ff-only; then
    FAIL_DETAIL="git pull --ff-only ไม่ผ่าน (มีคน force-push / src/ ถูกแก้บนเครื่อง?)
ดู: git -C projects/$NAME/src status · ตรงกับ GitHub: git -C projects/$NAME/src reset --hard @{u}"
    exit 1
  fi
  AFTER="$(git -C src rev-parse HEAD)"
  echo "[deploy:$NAME] source ${BEFORE:0:7} → ${AFTER:0:7}"
  STEP="ตรวจ .env"
  check_env "$ENV_BASE"
  STEP="build"
  echo "[deploy:$NAME] building image on server…"
  docker compose build
elif [ -d src ] && grep -qE '^[[:space:]]*build:' docker-compose.yml; then
  # src/ เป็นไฟล์ที่ copy มาเอง (ไม่ใช่ git clone) — build จากที่มี ไม่ pull โค้ด
  # (เดิมตกไป docker compose pull → "pull access denied" เพราะ image ไม่มีใน registry)
  STEP="ตรวจ .env"
  check_env ""
  STEP="build"
  echo "[deploy:$NAME] src/ ไม่ใช่ git clone — building from local src/ (auto-deploy ใช้ไม่ได้จนกว่าจะ clone)…"
  docker compose build
else
  STEP="pull image"
  echo "[deploy:$NAME] pulling image from registry…"
  docker compose pull
fi

# ── 1.5 Migrate + seed ด้วยโค้ดใหม่ ก่อนสลับ traffic (opt-in: DEPLOY_MIGRATE=1) ─
# ทุก stack — คำสั่งตั้งใน .env ของ project (default = Laravel) ดู scripts/lib/deploy-db.sh
STEP="migrate/seed"
# shellcheck source=scripts/lib/deploy-db.sh
. "$ROOT/scripts/lib/deploy-db.sh"
deploy_db "$NAME" "${ROLLOUT_SERVICE:-$NAME-app}" "$SEED_MODE"

# ── 2. สลับเวอร์ชัน ──────────────────────────────────
if [ -n "$ROLLOUT_SERVICE" ] && [ "$HAS_ROLLOUT" = 1 ]; then
  STEP="rolling deploy (ตัวใหม่ไม่ healthy?)"
  echo "[deploy:$NAME] rolling deploy '$ROLLOUT_SERVICE' (zero downtime)…"
  # เปิดตัวใหม่คู่ตัวเก่า → รอ healthcheck ผ่าน → ถอดตัวเก่า
  # ถ้าตัวใหม่ไม่ healthy: rollout ล้ม ตัวเก่ายังรับ traffic ต่อ (เว็บไม่ดับ)
  docker rollout "$ROLLOUT_SERVICE"
  SWITCHED=1
elif [ -n "$ROLLOUT_SERVICE" ]; then
  # มาถึงตรงนี้ = deploy ครั้งแรก หรือ DEPLOY_ALLOW_DOWNTIME=1
  echo "[deploy:$NAME] ⚠️ ไม่มี docker-rollout plugin — recreate แบบเว็บดับสั้น ๆ (docs/25-zero-downtime.md)"
fi

# ── 3. อัปเดต service ที่เหลือ (queue/scheduler ฯลฯ) ─
# ตัวที่ rollout ไปแล้ว config ตรง compose อยู่แล้ว → up -d ไม่แตะซ้ำ
STEP="อัปเดต service ที่เหลือ"
echo "[deploy:$NAME] updating remaining services…"
SWITCHED=1
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

# ── 4. Smoke test หลังสลับ — ของจริงผ่าน Traefik (scripts/smoke.sh) ─
# ล้มรอบแรก → รอ 20s ลองอีกรอบ (Traefik / cache ของ app อาจยังไม่นิ่ง) กันถอยเพราะจังหวะ
STEP="smoke test"
SMOKE_OK=1
if [ "$(penv DEPLOY_SMOKE)" != 0 ]; then
  # shellcheck disable=SC2046 # DEPLOY_SMOKE_PATHS คั่นด้วยช่องว่างตั้งใจ
  if ! "$ROOT/scripts/smoke.sh" "$NAME" $(penv DEPLOY_SMOKE_PATHS); then
    echo "[deploy:$NAME] smoke ล้ม — รอ 20s แล้วลองอีกรอบ…"
    sleep 20
    # shellcheck disable=SC2046
    "$ROOT/scripts/smoke.sh" "$NAME" $(penv DEPLOY_SMOKE_PATHS) || SMOKE_OK=0
  fi
fi

if [ "$SMOKE_OK" = 0 ]; then
  if [ "$(penv DEPLOY_AUTO_ROLLBACK)" = 1 ] && [ "$HAS_PREVIOUS" = 1 ]; then
    STEP="auto-rollback"
    echo "[deploy:$NAME] ↩️  smoke ล้ม → rollback กลับ :previous (DEPLOY_AUTO_ROLLBACK=1)…"
    "$ROOT/scripts/rollback.sh" "$NAME" previous --yes
    after="$("$ROOT/scripts/smoke.sh" "$NAME" $(penv DEPLOY_SMOKE_PATHS) >/dev/null 2>&1 && echo "smoke หลัง rollback ผ่าน ✅" || echo "⚠️ smoke หลัง rollback ยังล้ม — ตรวจด่วน: infra check $NAME")"
    mark_failed
    notify "↩️ $NAME smoke ล้มหลัง deploy → rollback กลับเวอร์ชันก่อนแล้ว · $after
$(commit_info)
migration ที่รันไปแล้วไม่ถูกย้อน · แก้แล้ว push ใหม่ · โดย: $TRIGGER"
    echo "↩️  [deploy:$NAME] rolled back — $after"
    exit 4
  fi
  # ขึ้นเว็บแล้ว — จำ commit (เป็นของจริงบนเว็บ) แต่แจ้งให้คนตัดสินใจ rollback
  if [ -d src/.git ]; then
    git -C src rev-parse HEAD > .deploy-commit
    git -C src rev-parse HEAD > .deploy-smoke-failed
    rm -f .deploy-failed .deploy-waiting
  fi
  notify "⚠️ $NAME ขึ้นเว็บแล้วแต่ smoke ล้ม — ตรวจ: infra check $NAME · ถอย: infra rollback $NAME
$(commit_info)
(เปิดถอยเอง: DEPLOY_AUTO_ROLLBACK=1 ใน .env ของ project) · โดย: $TRIGGER"
  echo "⚠️  [deploy:$NAME] ขึ้นเว็บแล้วแต่ smoke ล้ม — infra rollback $NAME ถ้าเว็บพัง"
  exit 3
fi

docker image prune -f >/dev/null
# จำ commit ที่ขึ้นเว็บจริงแล้ว — auto-deploy เทียบกับค่านี้ (ไม่ใช่ HEAD ของ src/ ที่ pull แล้วแต่ build อาจล้ม)
if [ -d src/.git ]; then
  git -C src rev-parse HEAD > .deploy-commit
  rm -f .deploy-failed .deploy-waiting .deploy-smoke-failed
fi
if [ "$(grep -E '^NOTIFY_DEPLOY_SUCCESS=' "$ROOT/.env" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '\r')" != 0 ]; then
  notify "✅ $NAME deploy สำเร็จ
$(commit_info)
โดย: $TRIGGER"
fi
echo "✅ [deploy:$NAME] done — $(date '+%F %T')"
