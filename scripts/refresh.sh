#!/usr/bin/env bash
# อัปเดตแพตช์ความปลอดภัยของ PHP / Node / OS ใน image ของ project — แม้ไม่มี commit ใหม่
# ใช้: infra refresh [project…]      (ไม่ใส่ = ทุก project · cron รายวัน 05:00 — infra cron)
#
# ทำไม: image ของ project build ครั้งเดียวตอน push — ถ้าไม่มีใครแตะ repo หลายเดือน
#   php:8.3-fpm / node:20 ข้างในค้างเวอร์ชันเก่า ทั้งที่ Docker Hub ออกแพตช์ CVE ไปแล้ว
# ทำอะไร (ต่อ project):
#   build บนเครื่อง (มี build: ใน compose) → docker pull base image ของ stage ที่รันจริง (FROM สุดท้าย / build.target)
#     แล้วดูว่า image บนเว็บ (APP_IMAGE) build บน base ตัวนี้ไหม (layer ขึ้นต้นด้วย layer ของ base)
#     ไม่ใช่ = base ออกแพตช์ใหม่หลัง build → deploy · stage ที่ใช้แค่ตอน build (node สำหรับ asset) ไม่นับ
#   image จาก registry (ไม่มี build:) → ทำเฉพาะเมื่อตั้ง DEPLOY_REFRESH=1 (เช่น n8n)
#     เทียบ digest ใน registry กับในเครื่อง (ไม่ pull ก่อน — ไม่ทับ image ที่ rollback ใช้)
#   มีแพตช์ → deploy.sh ตามปกติ: build --pull · backup DB · migrate · rolling (เว็บไม่ดับ) · smoke test
#     · smoke ล้ม + DEPLOY_AUTO_ROLLBACK=1 → ถอยกลับเอง · แจ้ง Telegram ทุกผล (โดย: อัปเดตแพตช์ base image)
# ข้าม project ที่:
#   DEPLOY_REFRESH=0 · มี commit ที่ยังไม่ขึ้นเว็บ (auto-deploy ดูแล) · deploy ล่าสุดล้ม / smoke ล้ม / รอคำตอบ seed
#   · ถูก rollback อยู่ (ไม่ rebuild commit ที่พังขึ้นไปทับ) · มี deploy กำลังรัน
# ไม่ได้อัปเดต library ในแอป (composer.lock / package-lock.json) — อยู่ใน repo ของแอป ใช้ Renovate (docs/31)
set -uo pipefail
cd "$(dirname "$(readlink -f "$0")")/.." || exit 1
ROOT="$PWD"
# shellcheck source=scripts/lib/base-images.sh
. "$ROOT/scripts/lib/base-images.sh"

exec 9>.refresh.lock
flock -n 9 || { echo "[refresh] มี refresh รันอยู่แล้ว — ข้าม"; exit 0; }

penv() { grep -E "^$2=" "$1/.env" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '\r' | sed -E 's/^"(.*)"$/\1/' || true; }
log() { echo "[refresh] $(date '+%F %T') $*"; }

# digest ใน registry ตอนนี้ vs digest ของ image ในเครื่อง (ไม่ pull)
remote_digest() { docker buildx imagetools inspect "$1" 2>/dev/null | awk '/^Digest:/ {print $2; exit}'; }
local_digests() { docker image inspect -f '{{range .RepoDigests}}{{println .}}{{end}}' "$1" 2>/dev/null | sed 's/.*@//'; }

if [ $# -gt 0 ]; then
  DIRS=(); for p in "$@"; do DIRS+=("projects/$p"); done
else
  DIRS=(projects/*/)
fi

RC_ALL=0
BUILT=0
for DIR in "${DIRS[@]}"; do
  DIR="${DIR%/}"
  NAME="$(basename "$DIR")"
  [ -f "$DIR/docker-compose.yml" ] || { [ $# -eq 0 ] || log "$NAME: ไม่มี project นี้"; continue; }
  MODE="$(penv "$DIR" DEPLOY_REFRESH)"
  [ "$MODE" != 0 ] || { log "$NAME: ข้าม (DEPLOY_REFRESH=0)"; continue; }
  [ ! -f "$DIR/.paused" ] || { log "$NAME: ข้าม — ปิดไว้ (infra resume $NAME)"; continue; }

  # สถานะที่ต้องมีคนดูก่อน — ไม่ deploy ทับเอง
  skip=""
  [ -f "$DIR/.deploy-rolled-back" ] && skip="ถูก rollback อยู่ (deploy มือเมื่อแก้แล้ว: infra deploy $NAME)"
  [ -f "$DIR/.deploy-failed" ] && skip="deploy ล่าสุดล้ม"
  [ -f "$DIR/.deploy-smoke-failed" ] && skip="smoke ล้มหลัง deploy ล่าสุด"
  [ -f "$DIR/.deploy-waiting" ] && skip="รอคำตอบเรื่อง seed"
  if [ -z "$skip" ] && [ -d "$DIR/src/.git" ]; then
    head="$(git -C "$DIR/src" rev-parse HEAD 2>/dev/null || true)"
    up="$(git -C "$DIR/src" rev-parse '@{u}' 2>/dev/null || echo "$head")"
    [ "$(cat "$DIR/.deploy-commit" 2>/dev/null)" = "$head" ] && [ "$up" = "$head" ] \
      || skip="มี commit ที่ยังไม่ขึ้นเว็บ (auto-deploy ดูแล)"
  fi
  if [ -z "$skip" ] && [ -f "$DIR/.deploy.lock" ] && ! flock -n "$DIR/.deploy.lock" true; then
    skip="มี deploy กำลังรันอยู่"
  fi
  [ -z "$skip" ] || { log "$NAME: ข้าม — $skip"; continue; }

  CHANGED=""
  if grep -qE '^[[:space:]]*build:' "$DIR/docker-compose.yml"; then
    INFO="$(project_build_info "$DIR")"; DF="${INFO%%|*}"; TG="${INFO#*|}"
    [ -f "$DF" ] || { log "$NAME: ข้าม — ไม่เจอ $DF (ตั้ง DEPLOY_DOCKERFILE ใน .env ถ้าอยู่ที่อื่น)"; continue; }
    APP="$(penv "$DIR" APP_IMAGE)"
    if [ -z "$APP" ] || ! docker image inspect "$APP" >/dev/null 2>&1; then
      log "$NAME: ข้าม — ยังไม่มี image ${APP:-(APP_IMAGE ว่าง)} ให้เทียบ (ยังไม่เคย deploy?)"; continue
    fi
    ref="$(dockerfile_runtime_base "$DF" "$TG")"
    [ -n "$ref" ] || { log "$NAME: ข้าม — หา base image ของ stage ที่รันไม่ได้ (FROM ใช้ ARG ที่ไม่มี default?)"; continue; }
    if ! docker pull -q "$ref" >/dev/null 2>&1; then
      log "$NAME: ⚠️ pull $ref ไม่ได้ (registry / network?) — ข้ามรอบนี้"; continue
    fi
    image_built_on "$APP" "$ref" || CHANGED="$ref"
  elif [ "$MODE" = 1 ]; then
    while read -r ref; do
      [ -n "$ref" ] || continue
      rd="$(remote_digest "$ref")"
      [ -n "$rd" ] || { log "$NAME: ⚠️ อ่าน digest ของ $ref จาก registry ไม่ได้ — ข้าม"; continue; }
      local_digests "$ref" | grep -qxF "$rd" || CHANGED="$CHANGED $ref"
    done < <(cd "$DIR" && docker compose config --images 2>/dev/null | sort -u)
  else
    continue   # image จาก registry ที่ไม่ได้เปิด DEPLOY_REFRESH=1 — CI ของแอปเป็นคน push image ใหม่
  fi

  if [ -z "$CHANGED" ]; then
    log "$NAME: ✅ base image ล่าสุดแล้ว"
    continue
  fi
  log "$NAME: มีแพตช์ใหม่ของ:$CHANGED → deploy…"
  RC=0; BUILT=1
  # --no-seed: commit เดิม ไม่มี seeder ใหม่ให้รัน · deploy.sh แจ้ง Telegram ผลเอง
  DEPLOY_TRIGGER=refresh DEPLOY_REFRESH_REASON="${CHANGED# }" ./scripts/deploy.sh "$NAME" --no-seed || RC=$?
  case "$RC" in
    0) log "$NAME: ✅ อัปเดตแล้ว" ;;
    3) log "$NAME: ⚠️ ขึ้นเว็บแล้วแต่ smoke ล้ม — infra check $NAME / infra rollback $NAME"; RC_ALL=1 ;;
    4) log "$NAME: ↩️ smoke ล้ม → rollback แล้ว — base ใหม่อาจไม่เข้ากับแอป ดู log แล้วแก้ Dockerfile"; RC_ALL=1 ;;
    *) log "$NAME: ❌ deploy ล้ม (เว็บยังเป็นเวอร์ชันเดิม) — ดู log ด้านบน"; RC_ALL=1 ;;
  esac
done
# build ใหม่ = build cache โตหลาย GB หลัง cleanup 04:00 ไปแล้ว → ล้างซ้ำเลย (ไม่ค้างทั้งวัน)
if [ "$BUILT" = 1 ]; then
  log "ล้าง build cache / image ที่เลิกใช้หลัง build…"
  ./scripts/cleanup.sh || true
fi
exit "$RC_ALL"
