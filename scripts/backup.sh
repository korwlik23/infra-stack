#!/usr/bin/env bash
# Backup ทั้งหมด — PostgreSQL + Docker volumes
# ใช้: ./scripts/backup.sh
set -euo pipefail
cd "$(dirname "$0")/.."

./backup/scripts/postgres-backup.sh
./backup/scripts/volumes-backup.sh

echo "✅ full backup complete → backup/archives/"
