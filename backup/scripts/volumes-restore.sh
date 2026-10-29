#!/usr/bin/env bash
# Restore Docker volumes จาก backup/archives/volumes/<volume>_<stamp>.tar.gz
# ใช้: ./volumes-restore.sh [--yes] [--overwrite] <dir> [volume…]
#   dir        โฟลเดอร์ที่มีไฟล์ .tar.gz (ปกติ backup/archives/volumes)
#   volume…    restore เฉพาะตัวที่ระบุ (ไม่ใส่ = ทุก volume ที่มีไฟล์ — ใช้ไฟล์ล่าสุดของแต่ละตัว)
#   --overwrite  ลบข้อมูลเดิมใน volume ที่มีอยู่แล้วก่อน restore (ต้อง stop container ที่ใช้ก่อน)
#   --yes        ข้ามการพิมพ์ยืนยัน (ใช้โดย scripts/restore-server.sh)
# ค่า default ปลอดภัย: volume ที่มีอยู่และมีข้อมูลแล้ว → ข้าม ไม่เขียนทับ
set -euo pipefail

YES=0; OVERWRITE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --yes) YES=1; shift ;;
    --overwrite) OVERWRITE=1; shift ;;
    *) break ;;
  esac
done
DIR="${1:?usage: volumes-restore.sh [--yes] [--overwrite] <dir> [volume…]}"; shift
DIR="$(cd "$DIR" && pwd)"
WANT=" $* "

# ไฟล์ล่าสุดต่อ volume: <volume>_YYYYMMDD_HHMMSS.tar.gz — ชื่อ volume มี _ ได้ จึงตัดจากท้าย
declare -A LATEST=()
for F in "$DIR"/*.tar.gz; do          # glob เรียงตามชื่อให้แล้ว
  [ -e "$F" ] || continue
  B="$(basename "$F")"
  VOL="$(printf '%s' "$B" | sed -E 's/_[0-9]{8}_[0-9]{6}\.tar\.gz$//')"
  [ "$VOL" != "$B" ] || continue
  [ "$WANT" = "  " ] || [[ "$WANT" == *" $VOL "* ]] || continue
  LATEST[$VOL]="$B"     # เรียงตามชื่อแล้ว → ตัวหลังสุด = stamp ใหม่สุด
done
[ ${#LATEST[@]} -gt 0 ] || { echo "[volumes-restore] ไม่พบไฟล์ backup ใน $DIR"; exit 0; }

has_data() { docker run --rm -v "$1":/v:ro alpine sh -c '[ -n "$(ls -A /v)" ]'; }

echo "[volumes-restore] จะ restore:"
for VOL in $(printf '%s\n' "${!LATEST[@]}" | sort); do echo "  $VOL ← ${LATEST[$VOL]}"; done
if [ "$YES" -ne 1 ]; then
  [ "$OVERWRITE" -eq 1 ] && echo "⚠️  --overwrite: ข้อมูลเดิมใน volume เหล่านี้จะถูกลบ"
  read -rp "Type 'restore' to continue: " CONFIRM
  [ "$CONFIRM" = "restore" ] || { echo "aborted"; exit 1; }
fi

FAILED=0
for VOL in $(printf '%s\n' "${!LATEST[@]}" | sort); do
  if docker volume inspect "$VOL" >/dev/null 2>&1 && has_data "$VOL"; then
    if [ "$OVERWRITE" -ne 1 ]; then
      echo "[volumes-restore] skip $VOL — มีข้อมูลอยู่แล้ว (ใช้ --overwrite ถ้าตั้งใจทับ)"
      continue
    fi
    if [ -n "$(docker ps -q --filter "volume=$VOL")" ]; then
      echo "[volumes-restore] ERROR: $VOL ถูก container ที่รันอยู่ใช้ — stop ก่อนแล้วรันใหม่" >&2
      FAILED=1; continue
    fi
    docker run --rm -v "$VOL":/data alpine find /data -mindepth 1 -delete
  fi
  docker volume create "$VOL" >/dev/null
  echo "[volumes-restore] $VOL…"
  if ! docker run --rm -v "$VOL":/data -v "$DIR":/backup:ro alpine \
         tar xzf "/backup/${LATEST[$VOL]}" -C /data; then
    echo "[volumes-restore] ERROR: แตกไฟล์ ${LATEST[$VOL]} ไม่สำเร็จ" >&2
    FAILED=1
  fi
done
echo "[volumes-restore] done"
exit "$FAILED"
