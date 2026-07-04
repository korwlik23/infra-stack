# 16 — Deploy Next.js

🎯 Next.js standalone container + HTTPS

## เตรียม app (ฝั่ง repo ของแอป)

`next.config.js`:

```js
module.exports = { output: "standalone" };
```

Dockerfile ตาม official example (multi-stage, สุดท้าย `node server.js`, expose 3000)
CI build → push image ขึ้น ghcr

## ⚙️ Deploy (ฝั่งเซิร์ฟเวอร์)

```bash
./scripts/create-project.sh myweb nextjs
nano projects/myweb/.env          # APP_IMAGE, APP_DOMAIN, DATABASE_URL ถ้าใช้
# เพิ่ม DNS record ใน Cloudflare
cd projects/myweb && docker compose up -d
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
