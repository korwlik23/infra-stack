# __PROJECT__ (Next.js)

Next.js standalone container ต่อ Traefik (HTTPS อัตโนมัติ) — image ควร build
ด้วย `output: "standalone"` ใน `next.config.js` แล้ว expose port 3000

## Deploy

```bash
nano .env
docker compose up -d
docker compose logs -f __PROJECT__
```

DNS: เพิ่ม record `__PROJECT__.<domain>` ชี้ server IP ใน Cloudflare (Proxied)

## Zero-downtime deploy

Deploy ครั้งถัดไปใช้ `../../scripts/deploy.sh __PROJECT__` — rolling อัตโนมัติ

- healthcheck ใช้ `fetch` ของ Node 18+ (ไม่ต้องมี curl ใน image)
- default เช็คหน้าแรก `/` — แนะนำสร้าง `/api/health` ที่ตอบเร็วและเบา
  แล้วแก้ `HEALTHCHECK_PATH` ใน .env
- ไม่มี `container_name` — ดู log ด้วย `docker compose logs` แทนชื่อ container

รายละเอียด: docs/25-zero-downtime.md
