#!/usr/bin/env bash
# ส่ง backup 1 ไฟล์ขึ้น off-site (Cloudflare R2 ผ่าน rclone) แล้วตรวจว่าขนาดตรงกัน
# ใช้: ./offsite.sh <kind> <file>      kind = postgres | volumes | secrets
# ปลายทาง: <remote>:<R2_BUCKET_BACKUP>/<BACKUP_HOST>/<kind>/<ไฟล์>
#   remote = BACKUP_RCLONE_REMOTE (default r2), BACKUP_HOST (default hostname) — แยกโฟลเดอร์ต่อเครื่อง
# ยังไม่ได้ตั้ง rclone / bucket → เตือนดัง ๆ แล้ว exit 0 (backup ในเครื่องยังใช้ได้)
# ตั้งแล้วแต่ upload / ตรวจไม่ผ่าน → exit 1
set -euo pipefail

KIND="${1:?usage: offsite.sh <postgres|volumes|secrets> <file>}"
FILE="${2:?usage: offsite.sh <postgres|volumes|secrets> <file>}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
env_val() { grep -E "^$1=" "$ROOT/.env" 2>/dev/null | head -1 | cut -d= -f2- | sed -E 's/^"(.*)"$/\1/' || true; }

[ -f "$FILE" ] || { echo "[offsite] ERROR: ไม่มีไฟล์ $FILE" >&2; exit 1; }

REMOTE="$(env_val BACKUP_RCLONE_REMOTE)"; REMOTE="${REMOTE:-r2}"
BUCKET="$(env_val R2_BUCKET_BACKUP)"
HOST="$(env_val BACKUP_HOST)"; HOST="${HOST:-$(hostname -s)}"

not_configured() {
  echo "[offsite] ⚠️  $1 — backup อยู่แค่ในเครื่องนี้ ถ้าเครื่องพังจะหายไปด้วย (ตั้งตาม docs/12-r2.md)"
  exit 0
}
command -v rclone >/dev/null 2>&1 || not_configured "ไม่มี rclone"
rclone listremotes 2>/dev/null | grep -qx "${REMOTE}:" || not_configured "ยังไม่มี rclone remote '${REMOTE}'"
[ -n "$BUCKET" ] && [ "$BUCKET" != "CHANGE_ME" ] || not_configured "R2_BUCKET_BACKUP ใน .env ยังไม่ตั้ง"

DST="${REMOTE}:${BUCKET}/${HOST}/${KIND}/$(basename "$FILE")"
echo "[offsite] → $DST"
rclone copyto "$FILE" "$DST"

# ตรวจว่าไฟล์ถึงจริงและขนาดเท่ากัน — copy สำเร็จแต่ไฟล์ปลายทางไม่ครบ = backup ที่กู้ไม่ได้
LOCAL_SIZE="$(stat -c %s "$FILE")"
REMOTE_SIZE="$(rclone lsjson "$DST" 2>/dev/null | grep -o '"Size":[0-9]*' | head -1 | cut -d: -f2 || true)"
if [ "$REMOTE_SIZE" != "$LOCAL_SIZE" ]; then
  echo "[offsite] ERROR: ขนาดไม่ตรง (local=$LOCAL_SIZE remote=${REMOTE_SIZE:-ไม่พบไฟล์}) — $DST" >&2
  exit 1
fi
echo "[offsite] ✅ ตรวจแล้ว $LOCAL_SIZE bytes"
