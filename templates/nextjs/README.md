# __PROJECT__ (Next.js)

Next.js standalone container ต่อ Traefik (HTTPS อัตโนมัติ) — image ควร build
ด้วย `output: "standalone"` ใน `next.config.js` แล้ว expose port 3000

## Deploy

```bash
# รันจาก repo root (/opt/infra-stack)
./scripts/setup-git.sh __PROJECT__ <github-user>/<repo>   # clone + เปิด build + APP_IMAGE (private → วาง deploy key แล้วรันซ้ำ)
nano projects/__PROJECT__/.env              # API keys / NEXT_PUBLIC_* — DATABASE_URL เติมให้แล้ว
./scripts/deploy.sh __PROJECT__             # build → prisma migrate deploy → project ใหม่ถาม seed → rolling
docker compose --project-directory projects/__PROJECT__ logs -f __PROJECT__
```

Prisma: Dockerfile ต้องมี stage `migrate` (docs/16-deploy-nextjs.md) · ไม่ใช้ DB → `DEPLOY_MIGRATE=0` ใน .env
ต่อจากนี้ push เข้า main → auto-deploy ขึ้นเอง (docs/19-cicd.md)

DNS: เพิ่ม record `__PROJECT__.<domain>` ชี้ server IP ใน Cloudflare (Proxied)

## Zero-downtime deploy

Deploy ครั้งถัดไปใช้ `./scripts/deploy.sh __PROJECT__` (จาก repo root) — rolling อัตโนมัติ

- healthcheck ใช้ `fetch` ของ Node 18+ (ไม่ต้องมี curl ใน image)
- default เช็คหน้าแรก `/` — แนะนำสร้าง `/api/health` ที่ตอบเร็วและเบา
  แล้วแก้ `HEALTHCHECK_PATH` ใน .env
- ไม่มี `container_name` — ดู log ด้วย `docker compose logs` แทนชื่อ container

รายละเอียด: docs/25-zero-downtime.md
