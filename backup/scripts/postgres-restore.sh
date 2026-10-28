#!/usr/bin/env bash
# Restore PostgreSQL จากไฟล์ backup (pg_dumpall gzip)
# ใช้: ./postgres-restore.sh backup/archives/postgres/all_YYYYMMDD_HHMMSS.sql.gz
set -euo pipefail

FILE="${1:?usage: postgres-restore.sh <backup-file.sql.gz>}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# อ่านค่าจาก .env ทีละ key แทน `source` — source รันไฟล์เป็น bash: รหัสผ่านที่มี
# $ ช่องว่าง & ; ทำ script พัง (set -u → unbound variable) หรือได้ค่าผิด
env_val() { grep -E "^$1=" "$ROOT/.env" 2>/dev/null | head -1 | cut -d= -f2- | sed -E 's/^"(.*)"$/\1/' || true; }
POSTGRES_USER="$(env_val POSTGRES_USER)"

[ -f "$FILE" ] || { echo "ERROR: file not found: $FILE" >&2; exit 1; }

echo "⚠️  This will OVERWRITE data in the running postgres container."
read -rp "Type 'restore' to continue: " CONFIRM
[ "$CONFIRM" = "restore" ] || { echo "aborted"; exit 1; }

gunzip -c "$FILE" | docker exec -i postgres psql -U "${POSTGRES_USER:-infra}" -d postgres

echo "[postgres-restore] done."
