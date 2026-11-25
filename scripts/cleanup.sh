#!/usr/bin/env bash
# ล้างขยะที่สะสมจากการ deploy — ไม่แตะของที่ใช้อยู่ / ข้อมูล
# ใช้: ./scripts/cleanup.sh             (cron รายวัน 04:00 — infra cron · refresh.sh เรียกซ้ำหลัง build เสร็จ)
#      ./scripts/cleanup.sh --dry-run   ดูว่าจะลบ image ที่เลิกใช้ / /tmp อะไรบ้าง (ไม่ลบอะไร)
#
# ลบ:
#   - build cache ที่ไม่ได้ใช้เกิน CLEANUP_CACHE_AGE (default 72h) — ของใหม่เก็บไว้ให้ build ถัดไปเร็ว
#     + รวมแล้วไม่เกิน CLEANUP_CACHE_MAX (default 2gb — ตั้งใน .env กลางได้)
#   - image ที่ไม่มี tag (<none>) — :previous มี tag จึงรอด → rollback ได้เหมือนเดิม
#   - image ที่เลิกใช้: ไม่มี container ไหนใช้ (รวมที่หยุดอยู่ เช่น project ที่ pause) และไม่ได้ pull ใหม่
#     เกิน CLEANUP_IMAGE_DAYS (default 7 · 0 = ปิด) เช่น uptime-kuma:1 หลังขึ้น v2
#     ยกเว้น: :previous (rollback) · base / build stage ใน Dockerfile ของ project (build / refresh ใช้) ·
#     TRIVY_IMAGE · alpine (backup ใช้) · CLEANUP_KEEP_IMAGES (คั่นด้วยช่องว่าง)
#   - container ที่หยุดแล้วเกิน 24 ชม. ที่ไม่ใช่ของ compose (เช่น docker run ที่ลืม --rm)
#   - ไฟล์ / โฟลเดอร์ของ user นี้ใน /tmp ที่ไม่มีอะไรข้างในถูกแก้เกิน CLEANUP_TMP_DAYS (default 7 · 0 = ปิด)
#     ไม่แตะของ user อื่น / tmux / ssh-agent / systemd
# ไม่ลบ volume เด็ดขาด (มีข้อมูล) — ดูเองด้วย: docker volume ls -f dangling=true
set -uo pipefail
cd "$(dirname "$(readlink -f "$0")")/.." || exit 1
ROOT="$PWD"
# shellcheck source=scripts/lib/base-images.sh
. "$ROOT/scripts/lib/base-images.sh"

env_val() { grep -E "^$1=" .env 2>/dev/null | head -1 | cut -d= -f2- | tr -d '\r' | sed -E 's/^"(.*)"$/\1/' || true; }
AGE="${CLEANUP_CACHE_AGE:-72h}"
IMG_DAYS="$(env_val CLEANUP_IMAGE_DAYS)"; IMG_DAYS="${IMG_DAYS:-7}"
TMP_DAYS="$(env_val CLEANUP_TMP_DAYS)"; TMP_DAYS="${TMP_DAYS:-7}"
DRY=0
[ "${1:-}" = --dry-run ] && DRY=1
used() { df -h / | awk 'NR==2 {print $3 " / " $2 " (" $5 ")"}'; }

echo "=== InfraStack cleanup $(date '+%F %T') — ก่อน: $(used) ==="
FAILED=""
if [ "$DRY" = 1 ]; then
  echo "(dry-run — ไม่ลบอะไร · build cache ตอนนี้: $(docker system df --format '{{.Type}} {{.Size}}' | awk '/^Build Cache/ {print $3}'))"
else
docker builder prune -f --filter "until=$AGE" | tail -n 1 || FAILED="$FAILED builder"
# เพดานขนาด: เครื่องที่ deploy ทุกวัน cache ใหม่อยู่ตลอดจนไม่เคยเกิน 72h → โตไม่หยุด (เจอ 13GB บนเครื่องจริง)
# เกิน CLEANUP_CACHE_MAX → ลบตัวที่ใช้ล่าสุดนานสุดออกจนเหลือเท่านี้ · Docker 29+ ใช้ --max-used-space / เก่ากว่า --keep-storage
MAX="${CLEANUP_CACHE_MAX:-$(env_val CLEANUP_CACHE_MAX)}"
MAX="${MAX:-2gb}"
if docker builder prune --help 2>/dev/null | grep -q -- '--max-used-space'; then
  docker builder prune -f --max-used-space "$MAX" | tail -n 1 || FAILED="$FAILED builder-max"
else
  docker builder prune -f --keep-storage "$MAX" | tail -n 1 || FAILED="$FAILED builder-max"
fi
docker image prune -f | tail -n 1 || FAILED="$FAILED image"
fi

# ── image ที่เลิกใช้ ──
if [ "$IMG_DAYS" != 0 ]; then
  KEEP=" alpine:latest $(env_val TRIVY_IMAGE) $(env_val CLEANUP_KEEP_IMAGES) "
  for d in projects/*/; do
    d="${d%/}"
    [ -f "$d/docker-compose.yml" ] || continue
    info="$(project_build_info "$d")"
    for b in $(dockerfile_all_bases "${info%%|*}"); do
      case "$b" in *:*|*@*) ;; *) b="$b:latest" ;; esac
      KEEP="$KEEP$b "
    done
  done
  IN_USE=" $(docker ps -aq | xargs -r docker inspect -f '{{.Image}}' 2>/dev/null | sort -u | tr '\n' ' ') "
  CUTOFF="$(date -d "-$IMG_DAYS days" +%s)"
  REMOVED=0
  while read -r id ref; do
    case "$ref" in *:previous|*'<none>'*) continue ;; esac
    case "$KEEP" in *" $ref "*) continue ;; esac
    case "$IN_USE" in *" $id "*) continue ;; esac
    # วันที่ pull / tag ล่าสุด (ไม่มี = วันที่สร้าง image)
    t="$(docker image inspect -f '{{.Metadata.LastTagTime}}' "$id" 2>/dev/null | cut -d. -f1)"
    case "$t" in ""|0001-*) t="$(docker image inspect -f '{{.Created}}' "$id" | cut -d. -f1)" ;; esac
    [ "$(date -d "${t/T/ }" +%s 2>/dev/null || echo 0)" -lt "$CUTOFF" ] || continue
    if [ "$DRY" = 1 ]; then
      echo "  จะลบ image: $ref ($(docker image inspect -f '{{.Size}}' "$id" | awk '{printf "%.0fMB", $1/1048576}') · ล่าสุด ${t%%T*})"; REMOVED=$((REMOVED + 1))
    elif docker rmi "$ref" >/dev/null 2>&1; then echo "  ลบ image ที่เลิกใช้: $ref"; REMOVED=$((REMOVED + 1)); fi
  done < <(docker images --no-trunc --format '{{.ID}} {{.Repository}}:{{.Tag}}')
  echo "image ที่เลิกใช้เกิน $IMG_DAYS วัน: ลบ $REMOVED ตัว"
  [ "$REMOVED" = 0 ] || [ "$DRY" = 1 ] || docker image prune -f >/dev/null 2>&1 || true
fi

[ "$DRY" = 1 ] || docker container prune -f --filter "until=24h" \
  --filter "label!=com.docker.compose.project" | tail -n 1 || FAILED="$FAILED container"

# ── /tmp ──
if [ "$TMP_DAYS" != 0 ]; then
  n=0
  while IFS= read -r -d '' f; do
    case "${f##*/}" in tmux-*|ssh-*|.X*|.ICE*|systemd-*|snap-*|.font-unix|.Test-unix) continue ;; esac
    # ข้ามถ้ามีอะไรข้างในถูกแก้ภายใน N วัน (โฟลเดอร์ที่ยังใช้อยู่ เช่น CI workspace)
    [ -z "$(find "$f" -newermt "-$TMP_DAYS days" -print -quit 2>/dev/null)" ] || continue
    if [ "$DRY" = 1 ]; then echo "  จะลบ /tmp: ${f##*/} ($(du -sh "$f" 2>/dev/null | cut -f1))"; n=$((n + 1)); continue; fi
    rm -rf -- "$f" 2>/dev/null && { echo "  ลบ /tmp: ${f##*/}"; n=$((n + 1)); }
  done < <(find /tmp -mindepth 1 -maxdepth 1 -user "$(id -u)" ! -newermt "-$TMP_DAYS days" -print0 2>/dev/null)
  echo "/tmp ที่ไม่ได้แตะเกิน $TMP_DAYS วัน: ลบ $n รายการ"
fi

if [ -n "$FAILED" ]; then
  echo "❌ cleanup ไม่สำเร็จ:$FAILED" >&2
  exit 1
fi
echo "✅ หลัง: $(used)"
