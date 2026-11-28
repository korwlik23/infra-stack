# 32 — Starter: ติดตั้งระบบสำเร็จรูปทั้งชุดในคำสั่งเดียว

**Starter** คือ repo บน GitHub ที่มีแม่แบบ deploy ของตัวเองอยู่ใน `deploy/infra-stack/`
`infra new` จะ clone repo นั้นมา แล้วตั้งค่าให้ครบ ได้แก่ database, user, รหัสสุ่ม และ URL ที่ต่อข้ามกัน
**Suite** คือชุดของ starter หลายตัว เช่น API + หลังบ้าน + หน้าเว็บ ที่ต้องรู้ URL ของกันและกัน

| ต่างจาก template ในตัว (`laravel`, `go`, …) ยังไง | |
|---|---|
| template ในตัว | ได้แค่โครง compose + `.env` แล้วค่อย `infra git` ต่อ repo ของคุณ |
| starter | repo มีโค้ด**และ**แม่แบบ deploy อยู่แล้ว — `infra new` ทำทั้ง clone + ตั้งค่าให้ |

รายชื่อที่ใช้ได้อยู่ใน [`templates/starters.list`](../templates/starters.list)

| ชื่อ | คืออะไร |
|---|---|
| `cms-go` (suite) | CMS ครบชุด: API (Go) + Back Office (Vue) + เว็บสาธารณะ (Astro) |
| `cms-api-go` | เฉพาะ API (Go + PostgreSQL) |
| `cms-admin` | เฉพาะ Back Office (Vue + Vite) |
| `cms-site` | เฉพาะเว็บสาธารณะ (Astro) |

---

## ติดตั้ง CMS ทั้งชุด (cms-go)

ตัวอย่างใช้ชื่อ `shop` และโดเมน `example.com` (คือ `BASE_DOMAIN` ที่ตั้งตอนติดตั้ง)

### 1. สร้าง

```bash
infra new shop cms-go
```

สำเร็จแล้วจะเห็น:

```
✅ suite shop (cms-go): shop-api shop-admin shop-site
next:
  1. เพิ่ม DNS record (Cloudflare, Proxied) ชี้ server IP:
       shop-api.example.com
       shop-admin.example.com
       shop.example.com
  2. infra deploy shop
```

ได้ 3 project: `shop-api`, `shop-admin`, `shop-site` และไฟล์ `projects/shop.suite` ที่บอกลำดับ deploy
ค่าที่ตั้งให้อัตโนมัติ:

- **database `shop-api_db` และ user 2 ตัว**
  - `shop_api` เป็นเจ้าของ ใช้ตอน migrate เท่านั้น
  - `shop_api_rt` ให้แอปใช้ตอนรัน อ่าน/เขียนข้อมูลได้ แต่สร้าง ลบ หรือแก้ตารางไม่ได้ ถ้าแอปโดน SQL injection ก็ `DROP TABLE` ไม่ได้
- **รหัสและ key ทุกตัว** สุ่มใหม่ ไม่ซ้ำกับเครื่องอื่น
- **URL ข้ามกัน:** หลังบ้านและหน้าเว็บรู้ URL ของ API ส่วน API รู้ว่าต้องรับ request จากหลังบ้าน (CORS)
- **ช่วง IP ของ Traefik** (`TRUSTED_PROXY_CIDRS`) ให้แอปเชื่อ IP จริงของผู้ใช้เฉพาะเมื่อมาจาก Traefik

> **repo เป็น private?** ระหว่างสร้างจะเห็นข้อความ 🔑 พร้อม deploy key
> วาง key ใน GitHub ตามขั้นที่บอก (ไม่ติ๊ก write access) แล้ว**รันคำสั่งเดิมซ้ำ**
> ตัวที่สร้างเสร็จแล้วจะถูกข้าม ทำต่อจากตัวที่ค้าง

### 2. เพิ่ม DNS

ใน Cloudflare เพิ่ม A record 3 ตัวตามรายการด้านบน ชี้ไปที่ IP เครื่อง เลือก **Proxied** (เมฆสีส้ม)

> ใช้ `shop-api.example.com` ไม่ใช่ `api.shop.example.com` เพราะ SSL ฟรีของ Cloudflare ครอบ subdomain แค่ชั้นเดียว

### 3. Deploy

```bash
infra deploy shop
```

deploy ทีละตัวตามลำดับ api → admin → site ถ้าตัวไหนล้ม จะหยุดทันที ตัวที่ยังไม่ถึงคิวยังเป็นเวอร์ชันเดิม
ครั้งแรกจะถาม `รัน seed ด้วยไหม? [y/N]` ให้ตอบ **y** เพื่อสร้างบัญชีผู้ดูแลคนแรก

สำเร็จแล้วจะเห็น `✅ suite shop: deploy ครบ 3 ตัว`

### 4. Login ครั้งแรก

```bash
infra env shop-api      # ดู BOOTSTRAP_EMAIL / BOOTSTRAP_PASSWORD
```

เปิด `https://shop-admin.example.com` แล้ว login ด้วยค่านั้น จากนั้น**เปลี่ยนรหัสทันที**
เพราะรหัสแรกเก็บอยู่ในไฟล์ `.env` บนเครื่อง

### ใช้งานต่อ

| ต้องการ | คำสั่ง |
|---|---|
| deploy ทั้งชุด | `infra deploy shop` |
| deploy ตัวเดียว | `infra deploy shop-api` |
| ดูสถานะ | `infra list` (มีหัวข้อ SUITE ท้ายตาราง) |
| ย้อนเวอร์ชัน | `infra rollback shop-api` · database: `infra restore db shop-api` |
| push เข้า main | auto-deploy ทีละ project เหมือน project ทั่วไป |

---

## สร้างทีละตัว หรือจาก repo อื่น

```bash
infra new blog-api cms-api-go               # ชื่อใน starters.list
infra new blog-api korwlik23/go-api-starter # owner/repo ตรง ๆ ก็ได้
```

สร้างทีละตัว URL ข้ามกันจะเป็น `CHANGE_ME` ให้ตั้งเองด้วย `infra env <ชื่อ>`
(`--mysql` / `--external-db` ใช้กับ starter ไม่ได้ — ตั้ง database ในแม่แบบของ repo แทน)

---

## ทำ repo ของคุณให้เป็น starter

repo ต้องมี:

| ไฟล์ | ข้อกำหนด |
|---|---|
| `Dockerfile` (root) | image สุดท้ายต้องมี `sh` + `wget` (หรือคำสั่งที่ healthcheck ใช้) และ `/tmp` เขียนได้ — ใช้กับ healthcheck และ drain ตอน rolling deploy ([25](25-zero-downtime.md)) |
| `deploy/infra-stack/docker-compose.yml` | service หลักมี `# build: ./src` (infra เปิดให้), healthcheck ที่เช็ค `/tmp/drain`, label `docker-rollout.pre-stop-hook=touch /tmp/drain && sleep 35`, ชื่อ router ของ Traefik = `__PROJECT__` (กันชนกันเมื่อมีหลายชุด) · ไม่มี `container_name` ใน service ที่ rolling |
| `deploy/infra-stack/.env.example` | ใช้ token ด้านล่าง — ห้ามใส่รหัสจริง |
| `deploy/infra-stack/README.md` | (แนะนำ) อธิบาย env ของ starter |

`infra new` **ปฏิเสธ** compose ที่ mount `docker.sock`, `privileged`, ใช้ host network/pid/ipc,
`cap_add` อันตราย หรือ mount โฟลเดอร์ระบบ (`/`, `/etc`, `/root`, …) — ตัวกรองนี้อ่านข้อความเท่านั้น
ไม่ใช่ sandbox: **ใช้กับ repo ที่ไว้ใจเท่านั้น** แล้วตรวจซ้ำด้วย `infra audit`

### Token ที่ใช้ใน `.env.example`

| Token | ได้ค่า |
|---|---|
| `__PROJECT__` | ชื่อ project (แทนทุกไฟล์ ยกเว้น `src/`) |
| `__ROOT:KEY__` | ค่า `KEY` จาก `.env` กลาง เช่น `__ROOT:REDIS_PASSWORD__` |
| `__DB_USER__` / `__DB_PASSWORD__` | user เจ้าของ database + รหัสสุ่ม (ใช้ตอน migrate) |
| `__DB_RUNTIME_USER__` / `__DB_RUNTIME_PASSWORD__` | user ที่อ่าน/เขียนข้อมูลได้อย่างเดียว (ใช้ตอนรัน) |
| `__GENERATE__` | รหัสสุ่ม hex 48 ตัว (สุ่มใหม่ทุกตัว) |
| `__GENERATE_B64__` | 32 byte สุ่มแบบ base64 — สำหรับ keyring เช่น `v1:__GENERATE_B64__` |
| `__SUITE_ORIGIN:api\|admin\|site__` | `https://shop-api.example.com` / `https://shop-admin…` / `https://shop.example.com` |
| `__SUITE_HOST:api\|admin\|site__` | เหมือนบรรทัดบนแต่ไม่มี `https://` (ใช้กับ `APP_DOMAIN`) |
| `__PROXY_CIDR__` | subnet ของ network `proxy` (Traefik) |

ค่าที่ infra ใช้อ่าน database ของ project (backup / restore / `infra db-user`) ต้องใช้ชื่อเหล่านี้:
`DB_HOST=postgres`, `DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD` (เจ้าของ) และ `DB_RUNTIME_USER`,
`DB_RUNTIME_PASSWORD` (runtime) — ถ้าแอปใช้ชื่ออื่น ให้ map ใน `environment:` ของ compose

### migrate ด้วย user เจ้าของ แต่รันแอปด้วย runtime user

```yaml
services:
  api:                                   # รับ traffic — ได้แค่ runtime user
    environment:
      DB_USER: ${DB_RUNTIME_USER}
      DB_PASSWORD: ${DB_RUNTIME_PASSWORD}
  api-migrate:                           # ใช้ตอน deploy เท่านั้น
    image: ${APP_IMAGE}
    profiles: [tools]                    # infra deploy ไม่สั่ง up ตัวนี้
    environment:
      DB_USER: ${DB_USERNAME}
      DB_PASSWORD: ${DB_PASSWORD}
```

```bash
# .env.example
DEPLOY_MIGRATE=1
DEPLOY_MIGRATE_SERVICE=api-migrate   # migrate/seed รันใน service นี้ (default = ROLLOUT_SERVICE)
DEPLOY_MIGRATE_CMD=/app/migrate
```

ใช้ `environment:` ระบุทีละค่า **ไม่ใช้ `env_file: .env`** — ไม่งั้น container ที่รับ traffic จะได้รหัสเจ้าของไปด้วย

### เพิ่มชื่อใน `templates/starters.list`

```
my-api     owner/my-api-repo
my-web     owner/my-web-repo
my-suite = api:my-api site:my-web     # เรียงตามลำดับ deploy
```

---

## แก้ปัญหา

| อาการ | สาเหตุ / วิธีแก้ |
|---|---|
| `ไม่มี deploy/infra-stack/docker-compose.yml` | repo นั้นยังไม่ใช่ starter — ใช้ `infra new <ชื่อ> go` + `infra git` แทน |
| `มี project ชื่อนี้อยู่แล้ว: shop-admin` | ชื่อ suite ชนกับ project เดิม — ใช้ชื่อ suite อื่น |
| `⏸ suite shop ยังไม่ครบ` | แก้ตามข้อความด้านบน (มักเป็น deploy key) แล้วรัน `infra new shop cms-go` ซ้ำ |
| `TRUSTED_PROXY_CIDRS=CHANGE_ME` | ตอนสร้าง Traefik ยังไม่รัน — `docker network inspect proxy` ดู Subnet แล้ว `infra env shop-api` |
| แอป `permission denied for table` หลัง restore | รัน `infra db-user shop-api` (restore เวอร์ชันนี้ให้สิทธิ์คืนเองแล้ว — เกิดกับ backup ที่ restore ด้วยมือ) |
