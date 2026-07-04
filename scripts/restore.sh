#!/usr/bin/env bash
# Restore PostgreSQL จาก backup ล่าสุด (หรือไฟล์ที่ระบุ)
# ใช้: ./scripts/restore.sh [backup-file.sql.gz]
set -euo pipefail
cd "$(dirname "$0")/.."

FILE="${1:-}"
if [ -z "$FILE" ]; then
  FILE="$(ls -1t backup/archives/postgres/all_*.sql.gz 2>/dev/null | head -1 || true)"
  [ -n "$FILE" ] || { echo "no backup found under backup/archives/postgres/" >&2; exit 1; }
  echo "using latest backup: $FILE"
fi

./backup/scripts/postgres-restore.sh "$FILE"
