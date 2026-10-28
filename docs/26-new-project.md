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

(เก็บ Dockerfile ไว้ใน repository ของ application นั้น)

---

## เฟส 1 — ตั้งค่าครั้งเดียวบนเซิร์ฟเวอร์

> แทน `<ชื่อ>` ด้วยชื่อ project (ตัวเล็ก a-z 0-9 -), `<repo>` = ชื่อ repo จริงบน GitHub
> ชื่อ project และชื่อ repository ไม่จำเป็นต้องตรงกัน

```bash
cd /opt/infra-stack

# 1) สร้าง project จาก template (laravel / nextjs / n8n / ai-worker)
#    database stack ต้องรันอยู่ — script สร้าง database <ชื่อ>_db ให้ด้วย
./scripts/create-project.sh <ชื่อ> laravel

# 2) clone โค้ด app เข้าไปใน src/ (ใช้ deploy key + host alias — docs/19-cicd.md)
cd projects/<ชื่อ>
git clone git@github.com-<ชื่อ>:<github-user>/<repo>.git src
cd /opt/infra-stack

# 3) เปิดโหมด build-on-server (เอา # ออกหน้า "build: ./src")
nano projects/<ชื่อ>/docker-compose.yml

# 4) ตั้งค่า .env
nano projects/<ชื่อ>/.env
```

**ข่าวดี (v2.3.0+):** `create-project.sh` **ดึงค่าจาก `.env` กลางให้อัตโนมัติแล้ว** —
`DB_PASSWORD`, `DB_USERNAME`, `REDIS_PASSWORD`, `APP_DOMAIN`, `TZ`, R2 ถูกเติมให้เลย
ไม่ต้องพิมพ์ซ้ำ (กลไก: template ใช้ token `__ROOT:KEY__` → script แทนค่าจาก `.env` กลาง)

เหลือแค่ตั้ง **ค่าเฉพาะ project** ที่ปล่อยว่างไว้:

```env
# ⚠️ ต้องตั้ง — ชื่อ image ที่ build บนเครื่อง (placeholder ghcr.io/<github-user>/… มี < > → build ล้ม)
APP_IMAGE=<ชื่อ>:latest
# ⚠️ ต้องตั้ง — สร้างบน host ได้เลย (ยังไม่มี container ให้รัน artisan จนกว่าจะ deploy ครั้งแรก):
#    echo "base64:$(openssl rand -base64 32)"
#    ย้ายจากเครื่องเก่า → ใช้ APP_KEY เดิม ห้าม generate ใหม่
APP_KEY=
# ที่เหลือเติมมาให้แล้วจาก .env กลาง — เช็คแล้วแก้เฉพาะที่ต่าง เช่น:
# DEPLOY_MIGRATE=1 / REDIS_CLIENT=predis  ← template Laravel ตั้งให้แล้ว
```

ถ้าค่าไหนใน `.env` กลางยังเป็น `CHANGE_ME`/ว่าง script จะเตือน + ใส่ `CHANGE_ME`
ให้ (เช่น R2 ถ้ายังไม่ตั้ง) แล้วค่อยเติมทีหลัง

```bash
# 5) database — create-project.sh สร้าง <ชื่อ>_db ให้แล้ว (ชื่อมี "-" ก็ได้ — quote ให้แล้ว)
#    ถ้าตอนนั้น postgres ยังไม่รัน script จะพิมพ์คำสั่งสร้างเองให้ copy ไปรัน

# 6) เพิ่ม DNS record ใน Cloudflare: <ชื่อ>.example.com → 203.0.113.10
#    ⚠️ ทำก่อน deploy ไม่งั้น Traefik ขอ cert ไม่ผ่าน → โดน rate limit

# 7) deploy ครั้งแรก (build + migrate + start)
./scripts/deploy.sh <ชื่อ>

# 8) เฉพาะ app ที่ต้อง seed ข้อมูลเริ่มต้น
./scripts/artisan.sh <ชื่อ> db:seed --force

# 9) สร้าง admin/owner ครั้งแรก (แล้วแต่ app — ผ่านหน้าเว็บหรือ artisan)

# 10) เพิ่ม monitor ใน Uptime Kuma → https://<ชื่อ>.example.com
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
| `CREATE DATABASE my-app_db` ด้วยมือแล้ว syntax error | ชื่อมี `-` ต้อง quote | ใช้ `create-project.sh` (quote ให้) หรือ `CREATE DATABASE "my-app_db";` |
| `invalid reference format` ตอน build | `APP_IMAGE` ยังเป็น placeholder `ghcr.io/<github-user>/…` | ตั้ง `APP_IMAGE=<ชื่อ>:latest` |
| `artisan.sh … key:generate` ได้ "service is not running" | ยังไม่เคย deploy — ไม่มี container | `echo "base64:$(openssl rand -base64 32)"` |

## 🔒 กฎที่ยังต้องจำ

- migration ต้องเป็น **expand/contract** — ห้าม drop/rename column ใน release เดียว ([docs/25](25-zero-downtime.md))
- `.env` ของ project **ไม่ commit** — อยู่ใน .gitignore แล้ว
- ย้ายเว็บจากเครื่องเก่า: ใช้ **temp domain** ทดสอบก่อน แล้วค่อยสลับ DNS จริง ([docs/15](15-deploy-laravel.md))
