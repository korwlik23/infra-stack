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
docker compose exec zennuaflow-app php artisan queue:monitor redis    # queue ทำงาน
```
