# Dozzle

ดู Docker logs ทุก container แบบ real-time ผ่าน Browser — ไม่ต้อง `docker logs`
เปิดที่ `https://logs.<BASE_DOMAIN>` (login ด้วย `DASHBOARD_USER` / `DASHBOARD_PASSWORD` ใน `.env`)

```bash
# จาก repo root (/opt/infra-stack) — อยู่ใน monitoring stack
infra up monitoring dozzle
```
