# Redis 7

Cache / Queue / Session กลางของทุก project — ต่อผ่าน network `backend`
(host = `redis`, port = `6379`, ต้องใช้ password จาก `REDIS_PASSWORD`)

## ใช้กับอะไร

- **Laravel**: `CACHE_STORE=redis`, `QUEUE_CONNECTION=redis`, `SESSION_DRIVER=redis`
- **Next.js**: rate limit / cache API response
- **n8n**: queue mode (`EXECUTIONS_MODE=queue`)

## Start / Test

```bash
# จาก repo root — Redis อยู่ใน database stack
docker compose --env-file .env -f docker/docker-compose.database.yml up -d redis
docker exec -it redis sh -c 'redis-cli -a "$REDIS_PASSWORD" ping'   # → PONG
```

## หมายเหตุ production

- `maxmemory 512mb` + `volatile-lru` — ปรับตาม RAM เครื่อง (แนะนำ ~10-15% ของ RAM)
  ไล่ทิ้งเฉพาะ key ที่มี TTL → job ใน queue ไม่ถูกลบตอน RAM เต็ม
- AOF เปิดอยู่ → queue ไม่หายตอน restart
- `FLUSHALL` / `CONFIG` ถูกปิดใน production (`FLUSHDB` เปิดไว้ — Laravel `cache:clear` ต้องใช้)
