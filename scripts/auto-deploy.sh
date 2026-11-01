#!/usr/bin/env bash
# Auto deploy — poll git ของทุก project ที่ src/ เป็น git clone ถ้ามี commit ใหม่ → deploy
# ฟรี 100% ไม่ต้องใช้ GitHub Actions / ไม่ต้องเปิด webhook endpoint
# deploy เฉพาะ branch ที่ clone ไว้ (setup-git.sh <project> <owner/repo> [branch] — default main)
#
# ตั้ง cron (ทุก 2 นาที — log อยู่ในเครื่อง ไม่ต้องใช้ sudo):
#   */2 * * * * /opt/infra-stack/scripts/auto-deploy.sh >> /opt/infra-stack/logs/auto-deploy.log 2>&1
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

# กันรันซ้อน: deploy หนึ่งตัวใช้ 1–2 นาที (build + drain 35s) — cron รอบถัดไปมาถึงก่อนจบได้
exec 9>.auto-deploy.lock
flock -n 9 || exit 0

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

  echo "[auto-deploy] $(date '+%F %T') $NAME: ${DEPLOYED:0:7} → ${REMOTE:0:7} — deploying…"
  if ./scripts/deploy.sh "$NAME"; then
    echo "[auto-deploy] $(date '+%F %T') $NAME: ✅ ${REMOTE:0:7}"
  else
    echo "$REMOTE" > "$DIR/.deploy-failed"
    echo "[auto-deploy] $(date '+%F %T') $NAME: ❌ deploy ${REMOTE:0:7} ล้ม — เว็บยังเป็นเวอร์ชันเดิม · ดู log ด้านบน"
    echo "               แก้แล้ว push ใหม่ หรือ: ./scripts/deploy.sh $NAME"
  fi
done
