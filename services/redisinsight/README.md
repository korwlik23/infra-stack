# Redis Insight

ดู Redis ผ่าน Browser — Cache / Queue / Session ทั้งหมด — `https://redis.<BASE_DOMAIN>`

⚠️ RedisInsight **ไม่มีระบบ login ของตัวเอง** — ถูกป้องกันด้วย basicauth ที่ Traefik
(เปลี่ยน hash ใน compose ก่อนใช้: `htpasswd -nb admin <password>`, escape `$`→`$$`)

## เพิ่ม database ครั้งแรก

Add Database:

```text
Host:     redis        (ผ่าน network backend)
Port:     6379
Password: $REDIS_PASSWORD
```

## Start

```bash
docker compose --env-file ../../.env up -d
```
