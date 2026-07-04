# __PROJECT__ (Laravel)

3 containers: **app** (HTTP, rolling deploy ได้), **queue** (Redis worker), **scheduler** (cron)

## Deploy

```bash
# 1. สร้าง database
docker exec -it postgres psql -U infra -c "CREATE DATABASE __PROJECT___db;"

# 2. ตั้งค่า .env (APP_KEY: php artisan key:generate --show)
nano .env

# 3. Start + migrate
docker compose up -d
docker compose exec __PROJECT__-app php artisan migrate --force
```

DNS: เพิ่ม record `__PROJECT__.<domain>` ชี้ server IP ใน Cloudflare (Proxied)

## Zero-downtime deploy

Deploy ครั้งถัดไปใช้ `../../scripts/deploy.sh __PROJECT__` — จะ rolling อัตโนมัติ
(เปิดตัวใหม่รอ healthy ก่อน ค่อยถอดตัวเก่า — เว็บไม่ดับ) เงื่อนไข:

- image ต้องมี `curl` (ใช้ใน healthcheck)
- app ต้องมี health route — Laravel 11+ มี `/up` ให้แล้ว
  (เวอร์ชันเก่ากว่า: สร้าง route เองแล้วแก้ `HEALTHCHECK_PATH` ใน .env)
- app service ไม่มี `container_name` — ใช้ `docker compose exec __PROJECT__-app …`
  แทนการ exec ด้วยชื่อ container ตรง ๆ

รายละเอียด + migration แบบ expand/contract: docs/25-zero-downtime.md
