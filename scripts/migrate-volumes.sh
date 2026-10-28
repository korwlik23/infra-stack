#!/usr/bin/env bash
# ย้าย volume ชื่อเดิม (docker_<name>) → ชื่อที่ pin ใหม่ (<name>) — รันครั้งเดียวต่อเครื่อง
# ใช้กับเครื่องที่ติดตั้งก่อนแยก compose project ต่อ stack (infra-core, infra-database, …)
# ใช้: ./scripts/migrate-volumes.sh
#
# เดิมทุก stack รันใต้ project "docker" (ชื่อโฟลเดอร์ docker/) → volume ชื่อ docker_postgres_data ฯลฯ
# ตอนนี้ volume ถูก pin เป็น postgres_data ฯลฯ — ถ้า up stack โดยไม่ย้าย จะได้ volume ใหม่ว่างเปล่า
#
# สิ่งที่ script ทำ (หลังพิมพ์ยืนยัน):
#   1. stop + rm container ของ project เดิม (ข้อมูลอยู่ใน volume — ไม่หาย)
#   2. copy ข้อมูล docker_<name> → <name> (volume เดิมเก็บไว้ ไม่ลบ)
set -euo pipefail
cd "$(dirname "$0")/.."

OLD_PROJECT="${OLD_PROJECT:-docker}"
VOLUMES=(
  portainer_data
  postgres_data redis_data
  prometheus_data alertmanager_data grafana_data loki_data promtail_positions
  uptime_kuma_data netdata_config netdata_lib netdata_cache beszel_data
  pgadmin_data redisinsight_data
  rabbitmq_data minio_data
)

PENDING=()
for VOL in "${VOLUMES[@]}"; do
  OLD="${OLD_PROJECT}_${VOL}"
  docker volume inspect "$OLD" >/dev/null 2>&1 || continue
  if docker volume inspect "$VOL" >/dev/null 2>&1; then
    # มีทั้งคู่ = เคย up stack ใหม่ไปแล้ว (volume ใหม่อาจว่าง) — ไม่เขียนทับให้ ต้องตัดสินใจเอง
    echo "⚠️  skip $OLD → $VOL: มี '$VOL' อยู่แล้ว — ตรวจเองว่าตัวไหนมีข้อมูลจริง"
    continue
  fi
  PENDING+=("$VOL")
done

if [ ${#PENDING[@]} -eq 0 ]; then
  echo "✅ ไม่มี volume ต้องย้าย"
  exit 0
fi

CONTAINERS="$(docker ps -aq --filter "label=com.docker.compose.project=$OLD_PROJECT")"

echo "จะย้าย volume:"
for VOL in "${PENDING[@]}"; do echo "  ${OLD_PROJECT}_${VOL} → $VOL"; done
if [ -n "$CONTAINERS" ]; then
  echo "และจะ stop + rm container ของ project '$OLD_PROJECT':"
  docker ps -a --filter "label=com.docker.compose.project=$OLD_PROJECT" --format '  {{.Names}}'
fi
echo "แนะนำ backup ก่อน: ./scripts/backup.sh"
read -rp "Type 'migrate' to continue: " CONFIRM
[ "$CONFIRM" = "migrate" ] || { echo "aborted"; exit 1; }

if [ -n "$CONTAINERS" ]; then
  # หยุดก่อน copy — กันไฟล์ database เขียนค้างระหว่าง copy
  # shellcheck disable=SC2086
  docker stop $CONTAINERS >/dev/null
  # shellcheck disable=SC2086
  docker rm $CONTAINERS >/dev/null
fi

for VOL in "${PENDING[@]}"; do
  echo "[migrate-volumes] ${OLD_PROJECT}_${VOL} → $VOL…"
  docker volume create "$VOL" >/dev/null
  docker run --rm -v "${OLD_PROJECT}_${VOL}":/from:ro -v "$VOL":/to alpine \
    sh -c 'cp -a /from/. /to/'
done

echo "✅ ย้ายเสร็จ — up stack ใหม่ตามลำดับ Core → Database → Monitoring (docker/README.md)"
echo "   volume เดิมยังอยู่ ลบเองหลังตรวจว่าข้อมูลครบ: docker volume rm ${OLD_PROJECT}_<name>"
