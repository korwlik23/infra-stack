#!/usr/bin/env bash
# Backup Docker named volumes → backup/archives/volumes/<volume>_<stamp>.tar.gz (+ off-site)
# ใช้: ./volumes-backup.sh [volume1 volume2 …]  (ไม่ใส่ = ทุก named volume ในเครื่อง)
#
# ไม่ใส่ชื่อ = ค้นทุก volume ที่มีอยู่จริง แทนรายการตายตัว — volume ของ project ใหม่
# (เช่น n8n) และ service ที่เพิ่มทีหลังถูก backup เองโดยไม่ต้องจำแก้ script
# ข้ามเสมอ:
#   - postgres_data, mysql_data — ใช้ pg_dumpall / mysqldump แทน (copy ไฟล์ database ขณะรัน = ไฟล์เสีย)
#   - docker_*            — volume ชื่อเก่าที่เหลือหลัง migrate-volumes.sh (ข้อมูลซ้ำ)
#   - anonymous (64 hex)  — volume ชั่วคราวที่ไม่มีชื่อ
#   - BACKUP_EXCLUDE_VOLUMES ใน .env — default: ประวัติ metrics/log ที่ใหญ่และสร้างใหม่ได้
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEST="$ROOT/backup/archives/volumes"
STAMP="$(date +%Y%m%d_%H%M%S)"
# อ่านค่าจาก .env ทีละ key แทน `source` — source รันไฟล์เป็น bash: รหัสผ่านที่มี
# $ ช่องว่าง & ; ทำ script พัง (set -u → unbound variable) หรือได้ค่าผิด
env_val() { grep -E "^$1=" "$ROOT/.env" 2>/dev/null | head -1 | cut -d= -f2- | sed -E 's/^"(.*)"$/\1/' || true; }
KEEP_DAYS="$(env_val BACKUP_KEEP_DAYS)"; KEEP_DAYS="${KEEP_DAYS:-7}"
EXCLUDE=" postgres_data mysql_data $(env_val BACKUP_EXCLUDE_VOLUMES) "

VOLUMES=("$@")
if [ ${#VOLUMES[@]} -eq 0 ]; then
  for VOL in $(docker volume ls -q); do
    [[ "$VOL" =~ ^[0-9a-f]{64}$ ]] && continue
    [[ "$VOL" == docker_* ]] && continue
    [[ "$EXCLUDE" == *" $VOL "* ]] && continue
    VOLUMES+=("$VOL")
  done
fi

mkdir -p "$DEST"

FAILED=0
for VOL in "${VOLUMES[@]}"; do
  if ! docker volume inspect "$VOL" >/dev/null 2>&1; then
    echo "[volumes-backup] skip missing volume: $VOL"
    continue
  fi
  OUT="${VOL}_${STAMP}.tar.gz"
  echo "[volumes-backup] $VOL…"
  # ไฟล์ .partial ก่อน แล้ว rename — tar ล้มกลางทางจะไม่เหลือไฟล์ครึ่ง ๆ
  if docker run --rm -v "$VOL":/data:ro -v "$DEST":/backup alpine \
       tar czf "/backup/$OUT.partial" -C /data . \
     && mv "$DEST/$OUT.partial" "$DEST/$OUT"; then
    "$ROOT/backup/scripts/offsite.sh" volumes "$DEST/$OUT" || FAILED=1
  else
    echo "[volumes-backup] ERROR: backup $VOL ไม่สำเร็จ" >&2
    rm -f "$DEST/$OUT.partial"
    FAILED=1
  fi
done

find "$DEST" -name "*.tar.gz" -mtime +"$KEEP_DAYS" -delete
echo "[volumes-backup] done (${#VOLUMES[@]} volumes) → $DEST"
exit "$FAILED"
