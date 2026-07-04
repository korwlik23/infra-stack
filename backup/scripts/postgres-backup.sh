#!/usr/bin/env bash
# Backup ทุก database ใน PostgreSQL container → backup/archives/postgres/
# ใช้: ./postgres-backup.sh   (หรือใส่ cron: 0 3 * * *)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/.env"

DEST="$ROOT/backup/archives/postgres"
STAMP="$(date +%Y%m%d_%H%M%S)"
KEEP_DAYS="${BACKUP_KEEP_DAYS:-7}"

mkdir -p "$DEST"

echo "[postgres-backup] dumping all databases…"
docker exec postgres pg_dumpall -U "$POSTGRES_USER" | gzip > "$DEST/all_${STAMP}.sql.gz"

echo "[postgres-backup] pruning backups older than ${KEEP_DAYS} days…"
find "$DEST" -name "all_*.sql.gz" -mtime +"$KEEP_DAYS" -delete

# Optional: sync to Cloudflare R2 (ต้องติดตั้ง rclone และ config remote ชื่อ r2)
if command -v rclone >/dev/null 2>&1 && [ "${R2_BUCKET_BACKUP:-}" != "" ] && [ "${R2_BUCKET_BACKUP}" != "CHANGE_ME" ]; then
  echo "[postgres-backup] syncing to R2 bucket ${R2_BUCKET_BACKUP}…"
  rclone copy "$DEST/all_${STAMP}.sql.gz" "r2:${R2_BUCKET_BACKUP}/postgres/"
fi

echo "[postgres-backup] done → $DEST/all_${STAMP}.sql.gz"
