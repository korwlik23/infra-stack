# __PROJECT__ (Laravel)

3 containers: **app** (HTTP, rolling deploy ได้), **queue** (Redis worker), **scheduler** (cron)

## Deploy

Database `__PROJECT___db` ถูกสร้างให้แล้วตอน `create-project.sh` (ถ้า postgres รันอยู่)

```bash
# รันจาก repo root (/opt/infra-stack)
# 1. เชื่อม GitHub — clone เข้า src/ + เปิด build + ตั้ง APP_IMAGE (private repo → วาง deploy key แล้วรันซ้ำ)
./scripts/setup-git.sh __PROJECT__ <github-user>/<repo>

# 2. ตั้ง APP_KEY: echo "base64:$(openssl rand -base64 32)"
nano projects/__PROJECT__/.env

# 3. Deploy ครั้งแรก (build + migrate + start) — project ใหม่ถาม "รัน seed ด้วยไหม? [y/N]"
#    ตอบ y ถ้าต้องใช้ข้อมูลเริ่มต้น (role, admin, setting) · ต่อจากนี้ push main → deploy + seed เอง
./scripts/deploy.sh __PROJECT__
```

DNS: เพิ่ม record `__PROJECT__.<domain>` ชี้ server IP ใน Cloudflare (Proxied)

## Zero-downtime deploy

Deploy ครั้งถัดไปใช้ `./scripts/deploy.sh __PROJECT__` (จาก repo root) — จะ rolling อัตโนมัติ
(เปิดตัวใหม่รอ healthy ก่อน ค่อยถอดตัวเก่า — เว็บไม่ดับ) เงื่อนไข:

- image ต้องมี `curl` (ใช้ใน healthcheck)
- app ต้องมี health route — Laravel 11+ มี `/up` ให้แล้ว
  (เวอร์ชันเก่ากว่า: สร้าง route เองแล้วแก้ `HEALTHCHECK_PATH` ใน .env)
- app service ไม่มี `container_name` — ใช้ `docker compose exec __PROJECT__-app …`
  แทนการ exec ด้วยชื่อ container ตรง ๆ

รายละเอียด + migration แบบ expand/contract: docs/25-zero-downtime.md
