# Dozzle

ดู Docker logs ทุก container แบบ real-time ผ่าน Browser — ไม่ต้อง `docker logs`
เปิดที่ `https://logs.<BASE_DOMAIN>` (มี basicauth — เปลี่ยน hash ก่อนใช้)

```bash
# จาก repo root (/opt/infra-stack) — อยู่ใน monitoring stack
docker compose --env-file .env -f docker/docker-compose.monitoring.yml up -d dozzle
```
