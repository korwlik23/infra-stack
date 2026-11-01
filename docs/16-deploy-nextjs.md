# 16 — Deploy Next.js

🎯 Next.js standalone container + HTTPS

## เตรียม app (ฝั่ง repo ของแอป)

`next.config.js`:

```js
module.exports = { output: "standalone" };
```

Dockerfile ตาม official example (multi-stage, สุดท้าย `node server.js`, expose 3000)

### ใช้ Prisma → เพิ่ม stage `migrate` (ไว้**ก่อน** stage สุดท้าย)

standalone image ไม่มี prisma CLI — `deploy.sh` build stage นี้แยกแล้วรัน `prisma migrate deploy`
ก่อนสลับ traffic (`DEPLOY_TOOLS_TARGET=migrate` ใน .env — template ตั้งให้แล้ว)

```dockerfile
FROM node:24-alpine AS migrate
RUN apk add --no-cache libc6-compat openssl
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci
COPY prisma ./prisma
RUN npx prisma generate

FROM node:24-alpine AS runner     # ← stage สุดท้าย = ตัวที่ docker build ใช้ปกติ
```

- ต้องมี migration ใน `prisma/migrations/` (ใช้ `prisma migrate dev` ตอน dev) — `db push` อย่างเดียว
  production migrate ไม่ได้ · DB ที่สร้างด้วย `db push` มาก่อน: `prisma migrate resolve --applied <ชื่อ>` ทีละตัว
- seed (`prisma db seed`) ต้องเป็นข้อมูลพื้นฐานเท่านั้น — มีรหัส/ข้อมูลตัวอย่าง → `DEPLOY_SEED_CMD=none`

## ⚙️ Deploy (ฝั่งเซิร์ฟเวอร์)

```bash
./scripts/create-project.sh myweb nextjs        # สร้าง database myweb_db ให้ (+ --mysql ถ้าใช้ MySQL)
./scripts/setup-git.sh myweb <owner>/<repo>     # clone + เปิด build + APP_IMAGE
nano projects/myweb/.env                        # API keys / NEXT_PUBLIC_* — DATABASE_URL เติมให้แล้ว
# เพิ่ม DNS record ใน Cloudflare (ก่อน deploy)
./scripts/deploy.sh myweb                        # build → prisma migrate deploy → ถาม seed → rolling
```

## ⚠️ ระวัง

- ตัวแปร `NEXT_PUBLIC_*` ถูก bake ตอน **build** — เปลี่ยนค่าต้อง build image ใหม่
  (ตัวแปร runtime ฝั่ง server เปลี่ยนใน .env แล้ว restart ได้)
- ISR/cache เขียนลง filesystem ของ container — ถ้า scale หลายตัวค่อยดู shared cache

## 🧪 ทดสอบ

```bash
curl -I https://myweb.<domain>                        # 200
cd projects/myweb && docker compose logs --tail 20    # "Ready in …"
```

Deploy ครั้งถัดไป: `./scripts/deploy.sh myweb` — zero-downtime อัตโนมัติ
(ดู [25-zero-downtime.md](25-zero-downtime.md))
