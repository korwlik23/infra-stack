# Redis 7

Cache / Queue / Session กลางของทุก project — ต่อผ่าน network `backend`
(host = `redis`, port = `6379`, ต้องใช้ password จาก `REDIS_PASSWORD`)

## ใช้กับอะไร

- **Laravel**: `CACHE_STORE=redis`, `QUEUE_CONNECTION=redis`, `SESSION_DRIVER=redis`
- **Next.js**: rate limit / cache API response
- **n8n**: queue mode (`EXECUTIONS_MODE=queue`)

## Start / Test

```bash
docker compose --env-file ../../.env up -d
docker exec -it redis redis-cli -a "$REDIS_PASSWORD" ping   # → PONG
```

## หมายเหตุ production

- `maxmemory 512mb` + `allkeys-lru` — ปรับตาม RAM เครื่อง (แนะนำ ~10-15% ของ RAM)
- AOF เปิดอยู่ → queue ไม่หายตอน restart
- `FLUSHALL` / `FLUSHDB` / `CONFIG` ถูกปิดใน production
