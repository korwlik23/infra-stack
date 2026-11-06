# 25 — Zero-Downtime Deployment (v2.1)

🎯 Deploy แล้วเว็บไม่ดับสักวินาที และ**ของพังไม่มีทางถึงมือ user**

## 🤔 ปัญหาของ deploy แบบเดิม

`docker compose up -d` = หยุดตัวเก่า → เปิดตัวใหม่:

```text
ปัญหา 1: มีช่องว่าง 2-10 วินาทีที่ไม่มีใครรับ traffic (เว็บดับ)
ปัญหา 2: ถ้า image ใหม่พัง → เว็บดับยาว จนกว่าจะ rollback มือ
```

## ⚙️ วิธีที่ stack นี้ใช้: Rolling deploy ด้วย `docker rollout`

`scripts/deploy.sh` ทำให้อัตโนมัติเมื่อ project มี `ROLLOUT_SERVICE` ใน .env:

```text
1. เปิด container ใหม่ (v2) ขึ้นมา "คู่กับ" ตัวเก่า (v1)
2. รอ v2 ผ่าน Docker healthcheck (app ตอบ HTTP ได้จริง)
3. Traefik เริ่มกระจาย traffic ให้ v2 (LB สองตัวอัตโนมัติ)
4. drain v1: สร้าง /tmp/drain → healthcheck ของ v1 ล้ม → Traefik เลิกส่ง request ให้ v1 (รอ 35s)
5. ถอด v1 ออก → เหลือ v2 ตัวเดียว
   ✅ user ไม่เจอช่องว่างเลย

ถ้า v2 healthcheck ไม่ผ่าน:
   rollout ล้ม → v1 ไม่ถูกแตะ → เว็บยังปกติ, deploy fail เฉย ๆ
   ✅ "ระบบแตก" กลายเป็นแค่ log error ไม่ใช่ downtime
```

Plugin ติดตั้งโดย `install.sh` อยู่แล้ว (ไฟล์เดียวที่ `~/.docker/cli-plugins/docker-rollout`)

ไม่มี plugin แต่ project ตั้ง `ROLLOUT_SERVICE` และเว็บรันอยู่ → `deploy.sh` **หยุด ไม่ deploy**
(เดิม fallback เป็น `docker compose up -d` = ถอดตัวเก่าก่อนตัวใหม่พร้อม ไม่มี healthcheck gate)
แก้: รัน `./install.sh` ซ้ำ · ยอมดับครั้งนี้: `DEPLOY_ALLOW_DOWNTIME=1 infra deploy <ชื่อ>`
deploy ครั้งแรก (ยังไม่มี container) ทำต่อได้ตามปกติ

## เงื่อนไขที่ template จัดให้แล้ว

| เงื่อนไข | สถานะ |
|----------|--------|
| App เป็น stateless (session→Redis, ไฟล์→R2) | ✅ ออกแบบไว้ตั้งแต่ v1.0.0 |
| ไม่มี `container_name` บน service ที่รับ traffic | ✅ templates laravel/nextjs (v2.1) |
| มี `healthcheck` จริง (ตอบ HTTP ไม่ใช่แค่ process ขึ้น) | ✅ Laravel `/up`, Next.js fetch |
| Traefik healthcheck labels — ส่ง traffic เฉพาะตัว healthy | ✅ ใส่ให้แล้ว |
| drain ตัวเก่าก่อน stop (`docker-rollout.pre-stop-hook` + healthcheck เช็ค `/tmp/drain`) | ✅ templates (v2.8.1) |

### Drain — ทำไมต้องมี (วัดจริง 2026-11-01)

ไม่มี drain: `docker rollout` stop ตัวเก่าทันทีที่ตัวใหม่ healthy แต่ Traefik ยังส่ง request ให้ตัวเก่าอยู่
→ request ที่วิ่งอยู่ช่วงนั้นหลุด (ยิงทุก 0.5s ระหว่าง deploy: **1/100 ได้ `000`**, ซ้ำได้ 2 ครั้ง)
มี drain: ตัวเก่าสร้าง `/tmp/drain` → Docker healthcheck ล้ม → Traefik ตัดออกเอง (ไม่ส่ง traffic ให้
container ที่ไม่ healthy) → รอ 35s แล้วค่อย stop → **210/210 ได้ 200** · deploy นานขึ้น ~35s

```yaml
healthcheck:
  test: ["CMD-SHELL", "test ! -f /tmp/drain && curl -fsS http://localhost:8080/up || exit 1"]
labels:
  # 35s = interval 10s × retries 3 ให้เป็น unhealthy + 5s ให้ request ที่ค้างจบ
  - "docker-rollout.pre-stop-hook=touch /tmp/drain && sleep 35"
```

⚠️ rollout อ่าน label จาก**ตัวเก่า** → drain มีผลตั้งแต่ deploy ครั้งที่ 2 หลังแก้ compose ·
เปลี่ยน interval/retries ของ healthcheck ต้องปรับ sleep ตาม

project ที่สร้างก่อน v2.8.1: เพิ่ม 2 จุดด้านบนใน `projects/<name>/docker-compose.yml` เอง
(compose ของ project ไม่อยู่ใน Git — `git pull` ไม่แก้ให้) แล้ว deploy 2 ครั้ง

⚠️ **Healthcheck ต้อง "จริง"** — endpoint ควรแตะ database/Redis เบา ๆ ด้วย
ถ้าตอบ 200 ทั้งที่ต่อ db ไม่ได้ ของพังจะผ่านด่านเข้าไปรับ traffic

## 🗄️ Database Migration: จุดที่พังบ่อยสุด

ช่วง rolling มี**โค้ดเก่า+ใหม่รันคู่กัน**บน schema เดียว → migration ต้องเป็น
**expand / contract** (backward-compatible เสมอ):

```text
❌ ห้าม: rename column / drop column / เปลี่ยน type ในครั้งเดียว
   → โค้ดเก่า query column เดิม พังทันทีที่ migrate

✅ ทำเป็น 2 release:
   Release 1 (expand):   ADD COLUMN ใหม่ — โค้ดเขียนลงทั้งคู่, อ่านจากตัวใหม่
   (รอจน Release 1 นิ่ง)
   Release 2 (contract): DROP COLUMN เก่า — ไม่มีโค้ดไหนใช้แล้ว
```

กติกาสั้น ๆ: **migration ทุกตัวต้องรันได้โดยโค้ดเวอร์ชันก่อนหน้ายังทำงานต่อได้**

## ⚙️ migrate อัตโนมัติตอน deploy (v2.2.0+ · ทุก stack ตั้งแต่ v2.9.0)

`deploy.sh` รันคำสั่ง migrate **ก่อนสลับ traffic** อัตโนมัติ ถ้า project มี `DEPLOY_MIGRATE=1` ใน `.env`
(template laravel / nextjs / go ตั้งให้แล้ว) — โค้ดอยู่ที่ `scripts/lib/deploy-db.sh`

| ค่าใน `.env` ของ project | Laravel (default) | Next.js + Prisma | Go |
|---|---|---|---|
| `DEPLOY_MIGRATE_CMD` | `php artisan migrate --force` | `npx prisma migrate deploy` | `/app/server migrate` |
| `DEPLOY_SEED_CMD` | `php artisan db:seed --force` | `npx prisma db seed` | `/app/server seed` |
| `DEPLOY_SEED_PATHS` | `database/seeders` | `prisma/seed.ts …` | `seeds` |
| `DEPLOY_TOOLS_TARGET` | — (ใช้ image ของ app) | `migrate` (stage ใน Dockerfile) | — |

- `DEPLOY_TOOLS_TARGET` = stage ใน Dockerfile ที่มีเครื่องมือ migrate — Next.js standalone image ไม่มี prisma CLI
  จึง build stage `migrate` แยก (ไม่ build Next.js ซ้ำ) แล้วรันบน network `backend` ด้วย `.env` เดียวกัน
- `DEPLOY_SEED_CMD=none` = project นี้ไม่ seed ตอน deploy (เช่น seed มีรหัส/ข้อมูลตัวอย่างที่ไม่ควรขึ้น production)
- project Laravel เดิมไม่ต้องแก้ — ไม่ตั้งค่าเหล่านี้ = ใช้ค่า Laravel

ลำดับ: build image ใหม่ → **migrate ด้วย image ใหม่** → rolling deploy
→ schema พร้อมก่อนโค้ดใหม่รับ traffic ถ้า migrate ล้ม `set -e` หยุดทันที ไม่ deploy ต่อ

🩹 **เหตุผลที่ต้องมี (post-mortem 2026-07-12):** ก่อนมีฟีเจอร์นี้ push โค้ดที่มี
migration ใหม่ → auto-deploy build+deploy โค้ดใหม่ **แต่ schema ยังเก่า** → app คืน 500
และ healthcheck `/up` ตอบ 200 อยู่ (แค่เช็คว่า framework boot ได้ ไม่เช็ค DB)
rolling deploy เลยคิดว่าสำเร็จ ทั้งที่หน้าเว็บพัง → เว็บดับจน migrate มือ

**project เก่าที่สร้างก่อน v2.2.0:** เพิ่ม `DEPLOY_MIGRATE=1` ใน `.env` เอง

## 🌱 seed ตอน deploy — project ใหม่ถามก่อน · push ใหม่ seed เอง (v2.11.0)

หลัง migrate (เฉพาะ project ที่มี `DEPLOY_MIGRATE=1`) `deploy.sh` เทียบ hash ของ
ไฟล์ seeder (`DEPLOY_SEED_PATHS` — Laravel: `database/seeders/`) ของ image ใหม่กับครั้งที่ seed/ตอบไปล่าสุด
(`projects/<ชื่อ>/.deploy-seeders.sha256` — ไม่มีไฟล์นี้ = project ใหม่บนเครื่องนี้)

| สถานการณ์ | ผล |
|-----------|----|
| **project ใหม่** (deploy ครั้งแรก) รันใน terminal | โชว์ไฟล์ seeder แล้วถาม `รัน seed ด้วยไหม? [y/N]` · ตอบ N = จำไว้ ไม่ถามอีก |
| **project ใหม่** แต่ auto-deploy (cron) เจอ commit ก่อนมีคนตอบ | **ยังไม่ deploy** — พักรอคำตอบ แจ้งใน log + Telegram ครั้งเดียว → คนรัน `deploy.sh <ชื่อ>` |
| **project เดิม** push commit ที่แก้ seeder | **seed ให้เองเลย** (ทั้ง auto-deploy และ deploy มือ) — seeder ต้องรันซ้ำได้ |
| project เดิม + `DEPLOY_AUTO_SEED=0` | ถามก่อนเมื่อ seeder เปลี่ยน — auto-deploy พักรอคำตอบเหมือน project ใหม่ |
| `deploy.sh <ชื่อ> --seed` / `--no-seed` | รันเลยไม่ถาม / ไม่รันและไม่ถาม |

รันด้วย image ใหม่ก่อนสลับ traffic เหมือน migrate — seed ล้ม = deploy หยุด เว็บเดิมยังอยู่

⚠️ คำสั่งที่ใช้คือ `db:seed --force` — **เติม**ข้อมูลลง DB เดิม ไม่ล้างตาราง แต่ seeder ต้องรันซ้ำได้
(`firstOrCreate` / `updateOrCreate` / `upsert`) ถ้าใช้ `create()` หรือ factory ตรง ๆ จะได้ข้อมูลซ้ำทุกครั้ง
และ seeder ที่สร้าง user ห้ามมีรหัสผ่าน default ที่เดาได้บน production

## 🔄 Rollback

```bash
infra rollback app   # กลับเวอร์ชันก่อนหน้า
```

`deploy.sh` เก็บ image ก่อน build ใหม่ไว้เป็น tag `:previous` อัตโนมัติ (v2.2.0+)
→ rollback ได้เสมอโดยไม่ต้อง tag เวอร์ชันเอง (เก็บย้อนได้ 1 step)
อยากเก็บหลายเวอร์ชัน: tag image เองเป็น `:v1.4.2` แล้ว `rollback.sh <project> v1.4.2`

`rollback.sh` **ไม่แก้ `.env`** — มันชี้ tag ใน `APP_IMAGE` (เช่น `:latest`) ไปที่ image เก่า
แล้ว rolling deploy ด้วย tag เดิม deploy ครั้งถัดไปจึงทำงานปกติ (build/pull เวอร์ชันใหม่ทับ)
ถ้าเคย rollback ด้วยเวอร์ชันก่อนหน้านี้ที่แก้ `.env` เป็น `APP_IMAGE=…:previous` ให้แก้กลับเป็น tag เดิม

⚠️ **migration ไม่ย้อนอัตโนมัติ** — ถ้าใช้ expand/contract ถูกต้อง โค้ดเก่าจะยัง
อ่าน schema ใหม่ได้ → rollback โค้ดปลอดภัย (นี่คือเหตุผลที่ห้าม drop column ใน release เดียว)

## 🛡️ ด่านกันพังรอบ deploy

healthcheck กันได้แค่ "ตัวใหม่ boot ไม่ขึ้น" — `deploy.sh` มีด่านเพิ่มอีก 3 ชั้น ไม่ต้องใช้ GitHub Actions:

```text
git pull → [1] ตรวจ .env → build → migrate → rollout (healthcheck) → [2] smoke test → [3] auto-rollback
```

| ด่าน | ทำอะไร | ล้มแล้วเว็บเป็นยังไง |
|------|--------|---------------------|
| **1. ตรวจ .env** | key ที่ **เพิ่มใหม่** ใน `src/.env.example` ตั้งแต่ deploy ล่าสุด แต่ยังไม่มีใน `projects/<ชื่อ>/.env` → หยุดก่อน build · `DATABASE_URL`/`DB_HOST` = `CHANGE_ME` ก็หยุด | เวอร์ชันเดิม |
| **2. smoke test** | `scripts/smoke.sh` หลังสลับ: container รัน/healthy, health path = 200, `/` < 500 ผ่าน Traefik, migration ไม่ค้าง (+ `DEPLOY_SMOKE_PATHS`) · ล้มรอบแรกรอ 20s ลองอีกรอบ | **ขึ้นเว็บแล้ว** → แจ้ง ⚠️ |
| **3. auto-rollback** | smoke ล้ม + `DEPLOY_AUTO_ROLLBACK=1` → `rollback.sh <ชื่อ> previous --yes` แล้ว smoke ซ้ำ | เวอร์ชันก่อน (migration ไม่ย้อน) |

key เก่าที่ขาด (app มี default) แค่เตือนใน log — ไม่งั้น project Laravel เดิมที่ `.env.example` มี key เป็นสิบจะ deploy ไม่ได้

ค่าใน `projects/<ชื่อ>/.env` (template ใหม่ตั้ง `DEPLOY_AUTO_ROLLBACK=1` ให้แล้ว · project เดิมเพิ่มเอง):

| ค่า | default | ความหมาย |
|-----|---------|---------|
| `DEPLOY_AUTO_ROLLBACK` | ปิด | `1` = smoke ล้มแล้วถอยให้เอง |
| `DEPLOY_SMOKE` | เปิด | `0` = ไม่รัน smoke หลัง deploy |
| `DEPLOY_SMOKE_PATHS` | ว่าง | path เพิ่ม คั่นด้วยช่องว่าง ต้องตอบ < 500 เช่น `/login /api/ping` |
| `DEPLOY_ENV_CHECK` | เปิด | `0` = ไม่ตรวจ `.env.example` |
| `DEPLOY_ENV_IGNORE` | ว่าง | key ที่เครื่องนี้ไม่ต้องตั้ง คั่นด้วยช่องว่าง |
| `DEPLOY_ALLOW_DOWNTIME` | ปิด | `1` = ไม่มี docker-rollout ก็ deploy (เว็บดับสั้น ๆ) |

### แจ้ง Telegram ทุกผล

ตั้ง `NOTIFY_TELEGRAM_BOT_TOKEN` + `NOTIFY_TELEGRAM_CHAT_ID` ใน `.env` กลาง — ทุกข้อความบอก commit, คน commit, ข้อความ commit และ deploy มือหรือ auto

| ข้อความ | เมื่อไหร่ |
|---------|----------|
| ✅ deploy สำเร็จ | ทุกครั้ง (ปิด: `NOTIFY_DEPLOY_SUCCESS=0`) |
| ❌ deploy ล้มตอน: `<ขั้น>` | pull / ตรวจ .env / build / migrate / rollout ล้ม — บอกว่าเว็บยังเป็นเวอร์ชันเดิมไหม |
| ⚠️ ขึ้นเว็บแล้วแต่ smoke ล้ม | ไม่ได้เปิด auto-rollback → ตัดสินใจเอง: `infra rollback <ชื่อ>` |
| ↩️ rollback แล้ว | smoke ล้ม + auto-rollback |
| 🔌 git fetch ล้ม / กลับมาได้ | auto-deploy ดึงโค้ดไม่ได้ (deploy key หาย, repo ย้าย) — แจ้งครั้งเดียวจนกว่าจะหาย |
| ⏸ รอคำตอบเรื่อง seed | เหมือนเดิม |

`infra list` แสดงสถานะเดียวกัน (❌ ล้ม · ⚠️ smoke ล้ม · 🔌 fetch ล้ม · ⏸ รอตอบ)

commit ที่ล้ม (รวมถูก rollback) จำใน `.deploy-failed` — auto-deploy ไม่ลองซ้ำ รอ commit ใหม่ หรือ `infra deploy <ชื่อ>`

### ที่ด่านพวกนี้ยังจับไม่ได้

- บั๊กที่ไม่ทำให้ health / หน้าแรก / path ใน `DEPLOY_SMOKE_PATHS` พัง — ใส่ path สำคัญเพิ่ม หรือใส่ test ใน Dockerfile (`RUN … test` ล้ม = build ล้ม)
- error ฝั่ง browser ของ SPA (JS พังแต่ server ตอบ 200)
- migration ที่ทำลายข้อมูล — rollback ย้อนโค้ดได้ ย้อนข้อมูลไม่ได้

## ข้อยกเว้น (ตัวที่ rolling ไม่ได้ — และไม่เป็นไร)

| ตัว | เหตุผล | ผลตอน deploy |
|-----|--------|---------------|
| n8n | instance เดียวต่อ encryption key + volume | restart สั้น ๆ, workflow ค้างคิวไว้รันต่อ |
| queue/scheduler | ไม่รับ traffic จาก user | `deploy.sh` recreate ด้วย image ใหม่ทุกครั้งที่ image เปลี่ยน (v2.5.1+) แล้วหยิบงานจากคิวต่อ ไม่มีใครเห็น |
| AI worker | ไม่รับ traffic | เหมือน queue |

## 🧪 วิธีทดสอบว่า zero-downtime จริง

เปิด terminal ที่สอง ยิงทุกวินาทีระหว่าง deploy:

```bash
while true; do curl -s -o /dev/null -w "%{http_code} " https://app.<domain>; sleep 1; done
# ระหว่างรัน infra deploy <name> ต้องเห็น 200 ล้วน ไม่มี 502/000

# ทดสอบด่าน healthcheck: deploy image ที่พังโดยตั้งใจ
# → rollout ต้อง fail, เว็บต้องยังตอบ 200 ตลอด
```

## ⚠️ ข้อจำกัดของ healthcheck `/up` (รู้ไว้)

`/up` ของ Laravel เช็คแค่ว่า framework boot ได้ — **ไม่เช็คว่า migration ครบ**
ดังนั้น "deploy สำเร็จ" ไม่ได้แปลว่า "ทุกหน้าใช้ได้" เสมอ ทางกันสองชั้น:
1. `DEPLOY_MIGRATE=1` — migrate ก่อน traffic (แก้เคสที่เจอบ่อยสุด) ✅ ทำแล้ว
2. อยากเข้มกว่า: เขียน health route เองที่แตะ DB/Redis เบา ๆ แล้วตั้ง `HEALTHCHECK_PATH`
   ชี้ไปที่นั่น — ตัวใหม่ที่ query ตารางที่ยังไม่มีจะ fail healthcheck → rollout ไม่ผ่าน
