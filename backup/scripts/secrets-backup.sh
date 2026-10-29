#!/usr/bin/env bash
# Backup ค่าที่ไม่อยู่ใน Git (secrets + config เฉพาะเครื่อง) แบบเข้ารหัส → backup/archives/secrets/
# ใช้: ./secrets-backup.sh
#
# ไม่มีชุดนี้ = restore ข้อมูลได้แต่ไม่มีรหัสผ่าน/cert/token → กู้เครื่องไม่ได้จริง
# สิ่งที่เก็บ:
#   repo/.env                                 รหัสผ่าน + ค่าตั้งทั้งเครื่อง
#   repo/projects/<name>/ (ยกเว้น src/ data/)  .env + compose ของแต่ละ project
#   repo/services/traefik/acme.json           cert Let's Encrypt — เครื่องใหม่ใช้ HTTPS ได้ก่อนย้าย DNS
#   repo/services/alertmanager/alertmanager.yml   Telegram token (แก้บนเครื่อง ไม่อยู่ใน Git)
#   home/.ssh/config + home/.ssh/deploy_*     deploy key สำหรับ clone source ของ app (docs/19)
#   crontab.txt                               cron ของ user นี้ (backup / auto-deploy)
# เข้ารหัสด้วย gpg AES256 + BACKUP_ENCRYPTION_PASSWORD ใน .env (install.sh สุ่มให้)
# ⚠️ จดรหัสนี้เก็บนอกเครื่อง — เครื่องพังแล้วไม่มีรหัส = เปิดไฟล์นี้ไม่ได้
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEST="$ROOT/backup/archives/secrets"
STAMP="$(date +%Y%m%d_%H%M%S)"
env_val() { grep -E "^$1=" "$ROOT/.env" 2>/dev/null | head -1 | cut -d= -f2- | sed -E 's/^"(.*)"$/\1/' || true; }
KEEP_DAYS="$(env_val BACKUP_KEEP_DAYS)"; KEEP_DAYS="${KEEP_DAYS:-7}"
PASS="$(env_val BACKUP_ENCRYPTION_PASSWORD)"

[ -f "$ROOT/.env" ] || { echo "[secrets-backup] ERROR: ไม่มี .env" >&2; exit 1; }
if [ -z "$PASS" ] || [ "$PASS" = "CHANGE_ME" ]; then
  echo "[secrets-backup] ERROR: BACKUP_ENCRYPTION_PASSWORD ใน .env ยังไม่ตั้ง — รัน ./install.sh (สุ่มให้)" >&2
  exit 1
fi
command -v gpg >/dev/null 2>&1 || { echo "[secrets-backup] ERROR: ไม่มี gpg — sudo apt-get install -y gnupg" >&2; exit 1; }

mkdir -p "$DEST"
chmod 700 "$DEST"
STAGE="$(mktemp -d "$DEST/.stage.XXXXXX")"
# gpg home ชั่วคราว — ไม่พึ่ง ~/.gnupg ของ user, ใช้ได้ใน cron (ไม่มี /run/user) และไม่มี agent
# ค้าง cache รหัสหลังจบ (path สั้นใน /tmp — socket ของ gpg-agent จำกัดความยาว path)
GNUPGHOME="$(mktemp -d)"; export GNUPGHOME
trap 'gpgconf --kill gpg-agent >/dev/null 2>&1 || true; rm -rf -- "$STAGE" "$GNUPGHOME"' EXIT
mkdir -p "$STAGE/repo" "$STAGE/home/.ssh"

copy_repo() {   # copy_repo <path ใน repo> — ข้ามถ้าไม่มี
  [ -e "$ROOT/$1" ] || return 0
  mkdir -p "$STAGE/repo/$(dirname "$1")"
  cp -a "$ROOT/$1" "$STAGE/repo/$1"
}

copy_repo .env
copy_repo services/traefik/acme.json
copy_repo services/alertmanager/alertmanager.yml
for P in "$ROOT"/projects/*/; do
  [ -d "$P" ] || continue
  NAME="$(basename "$P")"
  mkdir -p "$STAGE/repo/projects/$NAME"
  # ทุกอย่างใน project ยกเว้น src/ (git clone ของ app — clone ใหม่ได้) และ data/
  (cd "$P" && tar cf - --exclude=./src --exclude=./data .) | (cd "$STAGE/repo/projects/$NAME" && tar xf -)
done
[ -f "$HOME/.ssh/config" ] && cp -a "$HOME/.ssh/config" "$STAGE/home/.ssh/"
for K in "$HOME"/.ssh/deploy_*; do
  [ -f "$K" ] && cp -a "$K" "$STAGE/home/.ssh/"
done
crontab -l > "$STAGE/crontab.txt" 2>/dev/null || true

OUT="$DEST/secrets_${STAMP}.tar.gz.gpg"
echo "[secrets-backup] encrypting → $OUT"
# ส่งรหัสทาง fd 3 — ไม่โผล่ใน argument (ps เห็น)
tar czf - -C "$STAGE" . \
  | gpg --batch --yes --quiet --pinentry-mode loopback --passphrase-fd 3 \
        --symmetric --cipher-algo AES256 -o "$OUT.partial" 3<<<"$PASS"
mv "$OUT.partial" "$OUT"
chmod 600 "$OUT"

find "$DEST" -name "secrets_*.tar.gz.gpg" -mtime +"$KEEP_DAYS" -delete
"$ROOT/backup/scripts/offsite.sh" secrets "$OUT"
echo "[secrets-backup] done → $OUT"
