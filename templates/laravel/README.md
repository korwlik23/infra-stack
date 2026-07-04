# __PROJECT__ (Laravel)

3 containers: **app** (HTTP), **queue** (Redis queue worker), **scheduler** (cron)

## Deploy

```bash
# 1. สร้าง database
docker exec -it postgres psql -U infra -c "CREATE DATABASE __PROJECT___db;"

# 2. ตั้งค่า .env (APP_KEY: php artisan key:generate --show)
nano .env

# 3. Start + migrate
docker compose up -d
docker exec __PROJECT__-app php artisan migrate --force
```

DNS: เพิ่ม record `__PROJECT__.<domain>` ชี้ server IP ใน Cloudflare (Proxied)
