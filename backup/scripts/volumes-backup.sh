#!/usr/bin/env bash
# Backup Docker named volumes → backup/archives/volumes/
# ใช้: ./volumes-backup.sh [volume1 volume2 …]  (ไม่ใส่ = ชุด default)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEST="$ROOT/backup/archives/volumes"
STAMP="$(date +%Y%m%d_%H%M%S)"
# อ่านค่าจาก .env ทีละ key แทน `source` — source รันไฟล์เป็น bash: รหัสผ่านที่มี
# $ ช่องว่าง & ; ทำ script พัง (set -u → unbound variable) หรือได้ค่าผิด
env_val() { grep -E "^$1=" "$ROOT/.env" 2>/dev/null | head -1 | cut -d= -f2- | sed -E 's/^"(.*)"$/\1/' || true; }
KEEP_DAYS="$(env_val BACKUP_KEEP_DAYS)"; KEEP_DAYS="${KEEP_DAYS:-7}"

VOLUMES=("$@")
if [ ${#VOLUMES[@]} -eq 0 ]; then
  VOLUMES=(portainer_data grafana_data uptime_kuma_data redis_data)
fi

mkdir -p "$DEST"

for VOL in "${VOLUMES[@]}"; do
  if ! docker volume inspect "$VOL" >/dev/null 2>&1; then
    echo "[volumes-backup] skip missing volume: $VOL"
    continue
  fi
  echo "[volumes-backup] $VOL…"
  docker run --rm -v "$VOL":/data:ro -v "$DEST":/backup alpine \
    tar czf "/backup/${VOL}_${STAMP}.tar.gz" -C /data .
done

find "$DEST" -name "*.tar.gz" -mtime +"$KEEP_DAYS" -delete
echo "[volumes-backup] done → $DEST"
