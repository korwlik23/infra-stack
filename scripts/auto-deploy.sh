#!/usr/bin/env bash
# Auto deploy — poll git ของทุก project ที่ src/ เป็น git clone ถ้ามี commit ใหม่ → deploy
# ฟรี 100% ไม่ต้องใช้ GitHub Actions / ไม่ต้องเปิด webhook endpoint
# deploy เฉพาะ branch ที่ clone ไว้ (setup-git.sh <project> <owner/repo> [branch] — default main)
#
# commit ที่แก้ไฟล์ seeder → ไม่ deploy เอง "พักรอคำตอบ" (cron ไม่มีคนตอบว่าจะ seed ไหม):
#   แจ้งใน log + Telegram (ถ้าตั้ง — lib/notify.sh) แล้วให้คนรัน ./scripts/deploy.sh <project>
#   (ถาม seed y/N ตามปกติ · หรือ --seed / --no-seed) · project ที่ตั้ง DEPLOY_AUTO_SEED=1 ไม่พัก
#
# ตั้ง cron (ทุก 2 นาที — log อยู่ในเครื่อง ไม่ต้องใช้ sudo):
#   */2 * * * * /opt/infra-stack/scripts/auto-deploy.sh >> /opt/infra-stack/logs/auto-deploy.log 2>&1
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
ROOT="$PWD"
# shellcheck source=scripts/lib/notify.sh
. "$ROOT/scripts/lib/notify.sh"

# กันรันซ้อน: deploy หนึ่งตัวใช้ 1–2 นาที (build + drain 35s) — cron รอบถัดไปมาถึงก่อนจบได้
exec 9>.auto-deploy.lock
flock -n 9 || exit 0

penv() { grep -E "^$2=" "$1/.env" 2>/dev/null | head -1 | cut -d= -f2- | sed -E 's/^"(.*)"$/\1/' || true; }

# ไฟล์ seeder ที่เปลี่ยนระหว่าง commit ที่ขึ้นเว็บกับ commit ใหม่ (ว่าง = ไม่ต้องพัก)
# ใช้ git diff — รู้ก่อน build · DEPLOY_SEED_PATHS เป็น path ใน repo (= WORKDIR ของ image)
seed_changes() {
  local dir="$1" src="$2" from="$3" to="$4" seed_cmd paths
  [ "$(penv "$dir" DEPLOY_MIGRATE)" = "1" ] || return 0
  [ "$(penv "$dir" DEPLOY_AUTO_SEED)" = "1" ] && return 0
  seed_cmd="$(penv "$dir" DEPLOY_SEED_CMD)"
  [ "$seed_cmd" = "none" ] && return 0
  paths="$(penv "$dir" DEPLOY_SEED_PATHS)"; paths="${paths:-database/seeders}"
  # shellcheck disable=SC2086 # paths คั่นด้วยช่องว่างตั้งใจ
  git -C "$src" diff --name-only "$from" "$to" -- $paths 2>/dev/null || true
}

for SRC in projects/*/src; do
  [ -d "$SRC/.git" ] || continue
  DIR="$(dirname "$SRC")"
  NAME="$(basename "$DIR")"

  git -C "$SRC" fetch --quiet || { echo "[auto-deploy] $(date '+%F %T') $NAME: fetch ล้ม (deploy key / network?)"; continue; }
  REMOTE="$(git -C "$SRC" rev-parse '@{u}' 2>/dev/null)" || continue
  # เทียบกับ commit ที่ขึ้นเว็บแล้ว (deploy.sh เขียน) — ไม่มีไฟล์ = ยังไม่เคย deploy จาก git → ถือว่า HEAD
  DEPLOYED="$(cat "$DIR/.deploy-commit" 2>/dev/null || git -C "$SRC" rev-parse HEAD)"
  [ "$REMOTE" = "$DEPLOYED" ] && continue
  # commit นี้ deploy ล้มไปแล้ว — ไม่ลองซ้ำทุก 2 นาที รอ commit ใหม่ (หรือ deploy มือ)
  [ "$(cat "$DIR/.deploy-failed" 2>/dev/null)" = "$REMOTE" ] && continue

  SEEDS="$(seed_changes "$DIR" "$SRC" "$DEPLOYED" "$REMOTE")"
  if [ -n "$SEEDS" ]; then
    # แจ้งครั้งเดียวต่อ commit — รอบถัดไปเงียบจนกว่าจะมีคนตอบ หรือมี commit ใหม่
    if [ "$(cat "$DIR/.deploy-waiting" 2>/dev/null)" != "$REMOTE" ]; then
      echo "$REMOTE" > "$DIR/.deploy-waiting"
      echo "[auto-deploy] $(date '+%F %T') $NAME: ⏸ ${DEPLOYED:0:7} → ${REMOTE:0:7} แก้ seeder — ยังไม่ deploy รอคำตอบ:"
      printf '%s\n' "$SEEDS" | sed 's/^/               /'
      echo "               ตอบ: ./scripts/deploy.sh $NAME   (ถาม seed y/N · หรือ --seed / --no-seed)"
      notify "⏸ $NAME รอคำตอบก่อน deploy ${REMOTE:0:7} — แก้ seeder: $(printf '%s ' "$SEEDS")
ssh แล้วรัน: cd /opt/infra-stack && ./scripts/deploy.sh $NAME"
    fi
    continue
  fi

  echo "[auto-deploy] $(date '+%F %T') $NAME: ${DEPLOYED:0:7} → ${REMOTE:0:7} — deploying…"
  if ./scripts/deploy.sh "$NAME"; then
    echo "[auto-deploy] $(date '+%F %T') $NAME: ✅ ${REMOTE:0:7}"
  else
    echo "$REMOTE" > "$DIR/.deploy-failed"
    echo "[auto-deploy] $(date '+%F %T') $NAME: ❌ deploy ${REMOTE:0:7} ล้ม — เว็บยังเป็นเวอร์ชันเดิม · ดู log ด้านบน"
    echo "               แก้แล้ว push ใหม่ หรือ: ./scripts/deploy.sh $NAME"
    notify "❌ $NAME deploy ${REMOTE:0:7} ล้ม — เว็บยังเป็นเวอร์ชันเดิม · ดู /opt/infra-stack/logs/auto-deploy.log"
  fi
done
