# Redis Insight

ดู Redis ผ่าน Browser — Cache / Queue / Session ทั้งหมด — `https://redis.<BASE_DOMAIN>`

⚠️ RedisInsight **ไม่มีระบบ login ของตัวเอง** — ถูกป้องกันด้วย basicauth กลางที่ Traefik
(login ด้วย `DASHBOARD_USER` / `DASHBOARD_PASSWORD` ใน `.env` — install.sh สร้างให้)

## เพิ่ม database ครั้งแรก

Add Database:

```text
Host:     redis        (ผ่าน network backend)
Port:     6379
Password: $REDIS_PASSWORD
```

## Start

```bash
# จาก repo root (/opt/infra-stack) — อยู่ใน tools stack
infra up tools redisinsight
```
