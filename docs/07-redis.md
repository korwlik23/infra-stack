# 07 — Redis

🎯 Cache / Queue / Session กลางของทุก project

🤔 Redis ใช้ทำอะไรจริง ๆ:

| งาน | ใคร | ผล |
|-----|-----|----|
| Cache | Laravel `CACHE_STORE=redis`, Next.js API cache | ลด query ซ้ำ, หน้าเว็บเร็วขึ้น |
| Queue | Laravel `QUEUE_CONNECTION=redis`, n8n queue mode | งานหนัก (ส่งเมล, สร้างคลิป) ไปทำหลังบ้าน |
| Session | Laravel `SESSION_DRIVER=redis` | scale หลาย container ได้ session ไม่หลุด |
| Rate limit | ทุก API | กัน spam / abuse |

## ⚙️ วิธีทำ

อยู่ใน database stack แล้ว — config ที่ `services/redis/redis.conf`
(AOF persistence, maxmemory 512mb + LRU, ปิด FLUSHALL/FLUSHDB/CONFIG)

## 🧪 ทดสอบ

```bash
docker exec -it redis redis-cli -a "$REDIS_PASSWORD" ping     # PONG
docker exec -it redis redis-cli -a "$REDIS_PASSWORD" info memory | head -5
```

## ⚠️ ระวัง

- ต้องมี password เสมอ (ตั้งใน `.env`) — Redis ไม่มี auth คือถูกยึดได้ในไม่กี่นาทีถ้าหลุด
- `maxmemory` ปรับตามเครื่อง: ~10–15% ของ RAM (เครื่อง 8GB → 512mb–1gb)
- Queue อยู่ใน Redis — ถ้าลบ volume `redis_data` งานใน queue หายหมด
