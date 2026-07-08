# 15 — Deploy Laravel

🎯 Laravel ขึ้น production พร้อม queue + scheduler + HTTPS ใน 10 นาที

## ⚙️ วิธีทำ

```bash
# 1. สร้าง project จาก template
./scripts/create-project.sh zennuaflow laravel

# 2. สร้าง database
docker exec -it postgres psql -U $POSTGRES_USER -c "CREATE DATABASE zennuaflow_db;"

# 3. ตั้งค่า
nano projects/zennuaflow/.env    # APP_KEY, domain, DB, Redis, R2

# 4. DNS: เพิ่ม A record zennuaflow.<domain> ใน Cloudflare

# 5. Start + migrate
cd projects/zennuaflow
docker compose up -d
docker compose exec zennuaflow-app php artisan migrate --force
```

ได้ 3 containers: `-app` (HTTP, ไม่มี container_name — เพื่อ rolling deploy),
`-queue` (worker), `-scheduler` (cron)

Deploy ครั้งถัดไป: `./scripts/deploy.sh zennuaflow` — zero-downtime อัตโนมัติ
(ดู [25-zero-downtime.md](25-zero-downtime.md))

## Image มาจากไหน

Template ใช้ pre-built image (`ghcr.io/...`) — build จาก CI ของ repo แอปเอง
(GitHub Actions: build → push ghcr → ssh มา `docker compose pull && up -d`)

## ⚠️ ระวัง

- `APP_DEBUG=false` เสมอใน production
- migration ต้องเป็นแบบ expand/contract (backward-compatible) —
  ดู [25-zero-downtime.md](25-zero-downtime.md)
- queue/scheduler ถูก recreate อัตโนมัติโดย deploy.sh เมื่อ image เปลี่ยน

## 🧪 ทดสอบ

```bash
curl -I https://zennuaflow.<domain>                                   # 200
./scripts/artisan.sh zennuaflow queue:monitor redis                   # queue ทำงาน
```

💡 คำสั่ง artisan ทุกตัวใช้ทางลัดนี้ได้ (รันจากที่ไหนก็ได้ ไม่ต้องจำ compose):
`./scripts/artisan.sh <project> <คำสั่ง>` เช่น `migrate --force`, `db:seed --force`

## 🩹 ปัญหาที่เจอจริงตอน deploy Laravel ครั้งแรก (2026-07)

**1. `Class "Redis" not found`** — image ไม่มี PHP extension `phpredis`
ทางแก้ (เลือกหนึ่ง):
- เร็วสุด: ใน `.env` ตั้ง `REDIS_CLIENT=predis` (ต้องมี package `predis/predis` ใน composer)
- ถูกต้องระยะยาว: เพิ่ม `pecl install redis && docker-php-ext-enable redis` ใน Dockerfile

**2. `ERR unknown command 'FLUSHDB'` ตอน `cache:clear`/`optimize:clear`** —
redis.conf เวอร์ชันเก่าของ stack ปิด FLUSHDB ไว้ → แก้แล้วใน v2.1.2
(เครื่องเดิม: ลบบรรทัด `rename-command FLUSHDB ""` ใน `services/redis/redis.conf`
แล้ว `docker restart redis`)

**3. ย้ายเว็บจากเครื่องเก่า — อย่าตั้ง APP_DOMAIN เป็นโดเมนจริงก่อนสลับ DNS**
เพราะ Traefik จะขอ cert ของโดเมนที่ยังชี้เครื่องเก่า → fail ซ้ำจนโดน
Let's Encrypt rate limit ทำแบบนี้แทน:

```text
1. เพิ่ม A record ชั่วคราว: zennuaflow-new.<domain> → เครื่องใหม่
2. ตั้ง APP_DOMAIN=zennuaflow-new.<domain> → deploy → ทดสอบจนพอใจ
3. วันสลับ: แก้ APP_DOMAIN เป็นโดเมนจริง + สลับ DNS record → deploy อีกรอบ
4. ลบ record ชั่วคราว
```
