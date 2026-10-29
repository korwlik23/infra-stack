#!/usr/bin/env bash
# Restore secrets + config เฉพาะเครื่อง จากไฟล์ที่ secrets-backup.sh สร้าง
# ใช้: ./secrets-restore.sh [--yes] backup/archives/secrets/secrets_YYYYMMDD_HHMMSS.tar.gz.gpg
#   รหัสถอด: env BACKUP_ENCRYPTION_PASSWORD ถ้าตั้งไว้ ไม่งั้นถามตอนรัน (รหัสที่จดไว้นอกเครื่อง)
#   --yes = ข้ามการพิมพ์ยืนยัน (ใช้โดย scripts/restore-server.sh)
# .env เดิม (ถ้ามี) ถูกเก็บเป็น .env.before-restore-<stamp> ก่อนเขียนทับ
# ~/.ssh: ไฟล์ที่มีอยู่แล้วไม่ถูกทับ — crontab: ติดตั้งให้เฉพาะเมื่อ crontab ปัจจุบันว่าง
set -euo pipefail

YES=0
if [ "${1:-}" = "--yes" ]; then YES=1; shift; fi
FILE="${1:?usage: secrets-restore.sh [--yes] <secrets_*.tar.gz.gpg>}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
STAMP="$(date +%Y%m%d_%H%M%S)"

[ -f "$FILE" ] || { echo "ERROR: file not found: $FILE" >&2; exit 1; }
command -v gpg >/dev/null 2>&1 || { echo "ERROR: ไม่มี gpg — sudo apt-get install -y gnupg" >&2; exit 1; }

if [ "$YES" -ne 1 ]; then
  echo "⚠️  จะเขียนทับ .env, projects/*, acme.json, alertmanager.yml ของเครื่องนี้ด้วยค่าจาก backup"
  read -rp "Type 'restore' to continue: " CONFIRM
  [ "$CONFIRM" = "restore" ] || { echo "aborted"; exit 1; }
fi

PASS="${BACKUP_ENCRYPTION_PASSWORD:-}"
if [ -z "$PASS" ]; then
  read -rsp "BACKUP_ENCRYPTION_PASSWORD (รหัสที่จดไว้ตอนติดตั้งเครื่องเดิม): " PASS; echo
fi

umask 077
mkdir -p "$ROOT/backup/archives"
STAGE="$(mktemp -d "$ROOT/backup/archives/.restore-stage.XXXXXX")"
# gpg home ชั่วคราว — เครื่องใหม่ยังไม่มี ~/.gnupg และไม่ทิ้ง agent ที่ cache รหัสไว้
GNUPGHOME="$(mktemp -d)"; export GNUPGHOME
trap 'gpgconf --kill gpg-agent >/dev/null 2>&1 || true; rm -rf -- "$STAGE" "$GNUPGHOME"' EXIT

if ! gpg --batch --quiet --pinentry-mode loopback --passphrase-fd 3 -d "$FILE" 3<<<"$PASS" \
     | tar xzf - -C "$STAGE"; then
  echo "ERROR: ถอดรหัสไม่ได้ — รหัสผิด หรือไฟล์เสีย" >&2
  exit 1
fi

# ── repo ──
if [ -f "$STAGE/repo/.env" ]; then
  if [ -f "$ROOT/.env" ]; then
    mv "$ROOT/.env" "$ROOT/.env.before-restore-$STAMP"
    echo "[secrets-restore] .env เดิม → .env.before-restore-$STAMP"
  fi
  cp -a "$STAGE/repo/.env" "$ROOT/.env"
  chmod 600 "$ROOT/.env"
  echo "[secrets-restore] ✅ .env"
fi
for REL in services/traefik/acme.json services/alertmanager/alertmanager.yml; do
  [ -f "$STAGE/repo/$REL" ] || continue
  cp -a "$STAGE/repo/$REL" "$ROOT/$REL"
  echo "[secrets-restore] ✅ $REL"
done
[ -f "$ROOT/services/traefik/acme.json" ] && chmod 600 "$ROOT/services/traefik/acme.json"
if [ -d "$STAGE/repo/projects" ]; then
  for P in "$STAGE"/repo/projects/*/; do
    [ -d "$P" ] || continue
    NAME="$(basename "$P")"
    mkdir -p "$ROOT/projects/$NAME"
    cp -a "$P/." "$ROOT/projects/$NAME/"
    echo "[secrets-restore] ✅ projects/$NAME"
  done
fi

# ── ~/.ssh (deploy keys) — ไม่ทับของที่มีอยู่ ──
if [ -d "$STAGE/home/.ssh" ] && [ -n "$(ls -A "$STAGE/home/.ssh")" ]; then
  mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"
  for F in "$STAGE"/home/.ssh/*; do
    B="$(basename "$F")"
    if [ -e "$HOME/.ssh/$B" ]; then
      echo "[secrets-restore] skip ~/.ssh/$B — มีอยู่แล้ว (ของใน backup: ไม่ได้ทับ)"
      continue
    fi
    cp -a "$F" "$HOME/.ssh/$B"
    case "$B" in *.pub) chmod 644 "$HOME/.ssh/$B" ;; *) chmod 600 "$HOME/.ssh/$B" ;; esac
    echo "[secrets-restore] ✅ ~/.ssh/$B"
  done
fi

# ── crontab ──
if [ -s "$STAGE/crontab.txt" ]; then
  if [ -z "$(crontab -l 2>/dev/null || true)" ]; then
    crontab "$STAGE/crontab.txt"
    echo "[secrets-restore] ✅ crontab ($(grep -cv '^ *#' "$STAGE/crontab.txt" || true) บรรทัด)"
  else
    cp "$STAGE/crontab.txt" "$ROOT/backup/archives/crontab.restored-$STAMP.txt"
    echo "[secrets-restore] crontab ปัจจุบันไม่ว่าง — ไม่ทับ; ของเดิมอยู่ที่ backup/archives/crontab.restored-$STAMP.txt"
  fi
  if grep -q '/var/log/infra-' "$STAGE/crontab.txt"; then
    echo "   cron เขียน log ลง /var/log — สร้างไฟล์ให้ user นี้ (docs/13):"
    echo "   sudo touch /var/log/infra-backup.log /var/log/infra-deploy.log && sudo chown $(id -un): /var/log/infra-*.log"
  fi
fi
echo "[secrets-restore] done"
