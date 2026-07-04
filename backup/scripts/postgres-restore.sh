#!/usr/bin/env bash
# Restore PostgreSQL จากไฟล์ backup (pg_dumpall gzip)
# ใช้: ./postgres-restore.sh backup/archives/postgres/all_YYYYMMDD_HHMMSS.sql.gz
set -euo pipefail

FILE="${1:?usage: postgres-restore.sh <backup-file.sql.gz>}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/.env"

[ -f "$FILE" ] || { echo "ERROR: file not found: $FILE" >&2; exit 1; }

echo "⚠️  This will OVERWRITE data in the running postgres container."
read -rp "Type 'restore' to continue: " CONFIRM
[ "$CONFIRM" = "restore" ] || { echo "aborted"; exit 1; }

gunzip -c "$FILE" | docker exec -i postgres psql -U "$POSTGRES_USER" -d postgres

echo "[postgres-restore] done."
