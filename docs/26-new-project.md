# 26 — Deploy Project ใหม่ (ทำซ้ำได้ทุกครั้ง)

🎯 เอา app ใหม่ (Laravel / Next.js) ขึ้นเซิร์ฟเวอร์ให้ auto-deploy + zero-downtime

## แนวคิด: แยกเป็น 2 เฟส

```text
เฟส 1 — ตั้งค่าครั้งเดียว (ทำมือ ~15 นาที)
เฟส 2 — ทุกครั้งหลังจากนั้น = แค่ git push (auto-deploy ทำเอง 2-4 นาที)
```

เฟส 1 ทำครั้งเดียวต่อ project เพื่อ "แนะนำ" project ให้เซิร์ฟเวอร์รู้จัก
พอมี `projects/<ชื่อ>/src/` แล้ว auto-deploy จะดูแลต่อเอง

---

## เฟส 0 — เตรียมฝั่ง app repo (ครั้งเดียว ทำก่อน)

app repo ต้องมี **Dockerfile** ไม่งั้น build บนเซิร์ฟเวอร์ล้ม (`no such file: Dockerfile`)

| ต้องมีใน Dockerfile | Laravel | Next.js |
|---------------------|---------|---------|
| expose port | 8080 | 3000 |
| มี `curl` ใน image | ✅ (healthcheck ใช้) | ไม่จำเป็น (ใช้ node fetch) |
| health route | `/up` (Laravel 11 มีให้) | สร้าง `/api/health` เอง |
| build output | php-fpm+nginx | `output: "standalone"` |

(ตัวอย่าง Dockerfile ดูจาก accounting-saas / automation-ai-seller-chat ใน repo ของ app นั้น)

---

## เฟส 1 — ตั้งค่าครั้งเดียวบนเซิร์ฟเวอร์

> แทน `<ชื่อ>` ด้วยชื่อ project (ตัวเล็ก a-z 0-9 -), `<repo>` = ชื่อ repo จริงบน GitHub
> (อาจไม่ตรงกัน เช่น project `zennuaflow` แต่ repo ชื่อ `accounting-saas`)

```bash
cd /opt/infra-stack

# 1) สร้าง project จาก template (laravel / nextjs / n8n / ai-worker)
./scripts/create-project.sh <ชื่อ> laravel

# 2) clone โค้ด app เข้าไปใน src/
cd projects/<ชื่อ>
git clone git@github.com:korwlik23/<repo>.git src
cd /opt/infra-stack

# 3) เปิดโหมด build-on-server (เอา # ออกหน้า "build: ./src")
nano projects/<ชื่อ>/docker-compose.yml

# 4) ตั้งค่า .env
nano projects/<ชื่อ>/.env
```

ค่าสำคัญใน `.env` (Laravel):

```env
APP_IMAGE=ghcr.io/korwlik23/<ชื่อ>:latest
APP_DOMAIN=<ชื่อ>.tewarach-dev.me     # หรือ temp domain ถ้ายังไม่พร้อมสลับ DNS
APP_KEY=base64:...                    # ถ้าย้ายจากเครื่องเก่า ต้องตัวเดิม!
DB_DATABASE=<ชื่อ>_db
DB_PASSWORD=<POSTGRES_PASSWORD จาก /opt/infra-stack/.env>
REDIS_PASSWORD=<REDIS_PASSWORD>
REDIS_CLIENT=predis                   # ถ้า image ไม่มี phpredis extension
ROLLOUT_SERVICE=<ชื่อ>-app            # template ตั้งให้แล้ว
DEPLOY_MIGRATE=1                      # migrate อัตโนมัติทุก deploy (v2.2.0+)
HEALTHCHECK_PATH=/up
```

```bash
# 5) สร้าง database (ชื่อห้ามมี "-" ใช้ "_" แทน)
docker exec -i postgres psql -U infra -c "CREATE DATABASE <ชื่อ>_db;"

# 6) เพิ่ม DNS record ใน Cloudflare: <ชื่อ>.tewarach-dev.me → 217.216.32.198
#    ⚠️ ทำก่อน deploy ไม่งั้น Traefik ขอ cert ไม่ผ่าน → โดน rate limit

# 7) deploy ครั้งแรก (build + migrate + start)
./scripts/deploy.sh <ชื่อ>

# 8) เฉพาะ app ที่ต้อง seed ข้อมูลเริ่มต้น
./scripts/artisan.sh <ชื่อ> db:seed --force

# 9) สร้าง admin/owner ครั้งแรก (แล้วแต่ app — ผ่านหน้าเว็บหรือ artisan)

# 10) เพิ่ม monitor ใน Uptime Kuma → https://<ชื่อ>.tewarach-dev.me
```

---

## เฟส 2 — ทุกครั้งหลังจากนั้น

```text
แก้โค้ด → git push → รอ 2-4 นาที → เว็บอัปเดตเอง (ไม่ดับ)
```

auto-deploy (cron ทุก 2 นาที) เห็น commit ใหม่ → build → migrate → rolling deploy
ไม่ต้อง ssh เข้าเซิร์ฟเวอร์เลย

อยาก deploy เดี๋ยวนั้นไม่รอ cron: `./scripts/deploy.sh <ชื่อ>`
พลาดต้องถอย: `./scripts/rollback.sh <ชื่อ> previous`

---

## ⚠️ กับดักที่เจอจริง (กันพลาดซ้ำ)

| อาการ | สาเหตุ | แก้ |
|-------|--------|-----|
| `no such file: Dockerfile` ตอน build | app repo ยังไม่มี Dockerfile | เพิ่ม Dockerfile ใน repo ก่อน (เฟส 0) |
| deploy บอก "not found" ทั้งที่มีโฟลเดอร์ | mkdir + clone เอง ข้าม create-project | ใช้ `create-project.sh` เสมอ (มันสร้าง docker-compose.yml) |
| `Class "Redis" not found` | image ไม่มี phpredis | `REDIS_CLIENT=predis` ใน .env |
| เว็บ 500 หลัง push (มี migration ใหม่) | ลืม `DEPLOY_MIGRATE=1` | เพิ่มใน .env (template ใหม่มีให้แล้ว) |
| cert ขอไม่ผ่าน / log NXDOMAIN | ยังไม่ได้เพิ่ม DNS record | เพิ่ม A record ก่อน deploy |
| database ชื่อมี `-` สร้างไม่ได้ | PostgreSQL ไม่ชอบ `-` | ใช้ `_` เช่น `my_app_db` |

## 🔒 กฎที่ยังต้องจำ

- migration ต้องเป็น **expand/contract** — ห้าม drop/rename column ใน release เดียว ([docs/25](25-zero-downtime.md))
- `.env` ของ project **ไม่ commit** — อยู่ใน .gitignore แล้ว
- ย้ายเว็บจากเครื่องเก่า: ใช้ **temp domain** ทดสอบก่อน แล้วค่อยสลับ DNS จริง ([docs/15](15-deploy-laravel.md))
