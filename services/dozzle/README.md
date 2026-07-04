# Dozzle

ดู Docker logs ทุก container แบบ real-time ผ่าน Browser — ไม่ต้อง `docker logs`
เปิดที่ `https://logs.<BASE_DOMAIN>` (มี basicauth — เปลี่ยน hash ก่อนใช้)

```bash
docker compose --env-file ../../.env up -d
```
