#!/usr/bin/env bash
# Auto deploy — poll git ของทุก project ที่ src/ เป็น git clone ถ้ามี commit ใหม่ → deploy
# ฟรี 100% ไม่ต้องใช้ GitHub Actions / ไม่ต้องเปิด webhook endpoint
# deploy เฉพาะ branch ที่ clone ไว้ (setup-git.sh <project> <owner/repo> [branch] — default main)
#
# seed (lib/deploy-db.sh): project เดิมที่ push seeder ใหม่ → deploy + seed เองเลย
# ต้องมีคนตอบก่อน → ไม่ deploy เอง "พักรอคำตอบ" (cron ถามใครไม่ได้):
#   - project ใหม่บนเครื่องนี้ ยังไม่เคยตอบเรื่อง seed (ไม่มี .deploy-seeders.sha256)
#   - project ที่ตั้ง DEPLOY_AUTO_SEED=0 แล้ว commit แก้ seeder
#   แจ้งใน log + Telegram (ถ้าตั้ง — lib/notify.sh) แล้วให้คนรัน ./scripts/deploy.sh <project>
#   (ถาม seed y/N · หรือ --seed / --no-seed)
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

# เหตุผลที่ต้องพักรอคนตอบเรื่อง seed (ว่าง = deploy ได้เลย)
# ใช้ git — รู้ก่อน build · DEPLOY_SEED_PATHS เป็น path ใน repo (= WORKDIR ของ image)
needs_answer() {
  local dir="$1" src="$2" from="$3" to="$4" paths changed
  [ "$(penv "$dir" DEPLOY_MIGRATE)" = "1" ] || return 0
  [ "$(penv "$dir" DEPLOY_SEED_CMD)" = "none" ] && return 0
  paths="$(penv "$dir" DEPLOY_SEED_PATHS)"; paths="${paths:-database/seeders}"
  # shellcheck disable=SC2086 # paths คั่นด้วยช่องว่างตั้งใจ
  [ -n "$(git -C "$src" ls-tree -r --name-only "$to" -- $paths 2>/dev/null)" ] || return 0   # ไม่มี seeder
  if [ ! -f "$dir/.deploy-seeders.sha256" ]; then
    echo "project ใหม่บนเครื่องนี้ — ยังไม่เคยตอบว่าจะ seed ไหม"
    return 0
  fi
  if [ "$(penv "$dir" DEPLOY_AUTO_SEED)" = "0" ]; then
    # shellcheck disable=SC2086
    changed="$(git -C "$src" diff --name-only "$from" "$to" -- $paths 2>/dev/null || true)"
    # shellcheck disable=SC2086 # แตกรายชื่อไฟล์ออกเป็นบรรทัดเดียว
    [ -z "$changed" ] || printf 'แก้ seeder (DEPLOY_AUTO_SEED=0): %s\n' "$(printf '%s ' $changed)"
  fi
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
  # มีคน deploy มืออยู่ (deploy.sh ถือ lock) → ไม่ต่อคิว รอบถัดไปค่อยเทียบใหม่
  # (deploy มือจะ pull ไปถึง commit ล่าสุดอยู่แล้ว — ส่วนใหญ่รอบหน้าไม่มีอะไรต้องทำ)
  if [ -f "$DIR/.deploy.lock" ] && ! flock -n "$DIR/.deploy.lock" true; then
    echo "[auto-deploy] $(date '+%F %T') $NAME: ⏳ มี deploy กำลังรันอยู่ — ข้ามรอบนี้"
    continue
  fi

  REASON="$(needs_answer "$DIR" "$SRC" "$DEPLOYED" "$REMOTE")"
  if [ -n "$REASON" ]; then
    # แจ้งครั้งเดียวต่อ commit — รอบถัดไปเงียบจนกว่าจะมีคนตอบ หรือมี commit ใหม่
    if [ "$(cat "$DIR/.deploy-waiting" 2>/dev/null)" != "$REMOTE" ]; then
      echo "$REMOTE" > "$DIR/.deploy-waiting"
      echo "[auto-deploy] $(date '+%F %T') $NAME: ⏸ ${DEPLOYED:0:7} → ${REMOTE:0:7} ยังไม่ deploy รอคำตอบเรื่อง seed:"
      echo "               $REASON"
      echo "               ตอบ: infra deploy $NAME   (ถาม seed y/N · หรือ --seed / --no-seed)"
      notify "⏸ $NAME รอคำตอบก่อน deploy ${REMOTE:0:7} — $REASON
ssh แล้วรัน: infra deploy $NAME"
    fi
    continue
  fi

  echo "[auto-deploy] $(date '+%F %T') $NAME: ${DEPLOYED:0:7} → ${REMOTE:0:7} — deploying…"
  if ./scripts/deploy.sh "$NAME"; then
    echo "[auto-deploy] $(date '+%F %T') $NAME: ✅ ${REMOTE:0:7}"
  else
    echo "$REMOTE" > "$DIR/.deploy-failed"
    echo "[auto-deploy] $(date '+%F %T') $NAME: ❌ deploy ${REMOTE:0:7} ล้ม — เว็บยังเป็นเวอร์ชันเดิม · ดู log ด้านบน"
    echo "               แก้แล้ว push ใหม่ หรือ: infra deploy $NAME"
    notify "❌ $NAME deploy ${REMOTE:0:7} ล้ม — เว็บยังเป็นเวอร์ชันเดิม · ดู /opt/infra-stack/logs/auto-deploy.log"
  fi
done
