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
docker exec zennuaflow-app php artisan migrate --force
```

ได้ 3 containers: `-app` (HTTP), `-queue` (worker), `-scheduler` (cron)

## Image มาจากไหน

Template ใช้ pre-built image (`ghcr.io/...`) — build จาก CI ของ repo แอปเอง
(GitHub Actions: build → push ghcr → ssh มา `docker compose pull && up -d`)

## ⚠️ ระวัง

- `APP_DEBUG=false` เสมอใน production
- migrate ก่อนสลับ traffic ถ้า schema เปลี่ยนแบบ breaking
- queue worker ต้อง `docker restart zennuaflow-queue` หลัง deploy โค้ดใหม่
  (ไม่งั้นรันโค้ดเก่าค้างใน memory)

## 🧪 ทดสอบ

```bash
curl -I https://zennuaflow.<domain>                          # 200
docker exec zennuaflow-app php artisan queue:monitor redis   # queue ทำงาน
```
