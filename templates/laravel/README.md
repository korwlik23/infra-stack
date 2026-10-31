# __PROJECT__ (Laravel)

3 containers: **app** (HTTP, rolling deploy ได้), **queue** (Redis worker), **scheduler** (cron)

## Deploy

Database `__PROJECT___db` ถูกสร้างให้แล้วตอน `create-project.sh` (ถ้า postgres รันอยู่)

```bash
# 1. ตั้งค่า .env — APP_IMAGE (build บนเครื่อง: ตั้งชื่ออะไรก็ได้ เช่น __PROJECT__:latest)
#    และ APP_KEY: echo "base64:$(openssl rand -base64 32)"
nano .env

# 2. Deploy (build/pull + migrate + ถาม seed + start) — รันจาก repo root
#    ครั้งแรกตอบ y ที่ "รัน db:seed ด้วยไหม?" ถ้าต้องใช้ข้อมูลเริ่มต้น (role, admin, setting)
cd ../.. && ./scripts/deploy.sh __PROJECT__
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
