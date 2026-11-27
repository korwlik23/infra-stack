# Starter templates — ติดตั้ง go-lang-starter ด้วย `infra new`

- วันที่: 2026-11-27
- สถานะ: design รอผู้ใช้ review
- ขอบเขต: infra-stack + go-lang-starter (api, admin, site) · Rust starter = design แยกรอบหน้า

## 1. ปัญหาและเป้าหมาย

`D:\go-lang-starter` (Go API + Vue admin + Astro site) build และ `go test ./...` ผ่าน
แต่ deploy บน infra-stack ปัจจุบันไม่ได้:

| จุด | starter ตอนนี้ | infra-stack ตอนนี้ |
|---|---|---|
| revision | wrapper บังคับ HEAD = `ee4df17` | ใหม่กว่า 60+ commits → wrapper หยุด |
| วิธี deploy | GHCR digest + `scripts/deploy-infra-stack.sh` | `infra new` → `infra git` → `infra deploy` (build บนเครื่อง) |
| API image | `FROM scratch` | ต้องมี `sh` + `wget` ให้ healthcheck / drain |
| migrate | `DEPLOY_MIGRATE=0` + wrapper | `DEPLOY_MIGRATE_CMD` รันใน service ของ app (ได้ credential runtime) |
| DB | `DB_SSLMODE=require`, 2 principals | Postgres กลางใน network `backend` ไม่มี TLS, 1 user ต่อ project |
| drain | ไม่มี `docker-rollout.pre-stop-hook` | template ทุกตัวมี |
| ชื่อ Traefik router | fix `go-lang-api` | 2 suite บนเครื่องเดียวจะชนกัน |

**เป้าหมาย:** มือใหม่ติดตั้งทั้งชุดได้ด้วย

```bash
infra new shop cms-go       # สร้าง shop-api + shop-admin + shop-site
infra deploy shop           # api → admin → site (หยุดเมื่อตัวใดล้ม)
```

**เกณฑ์สำเร็จ:** บน VPS จริง `infra new demo cms-go` + `infra deploy demo` แล้ว
`/readyz` ตอบ 200, login admin ได้, runtime user `DROP TABLE` ไม่ได้,
rolling deploy ไม่มี request หลุด, `infra rollback` ใช้ได้

## 2. ทางเลือกที่พิจารณา

- **A. alias + suite ชี้ไป repo (เลือก)** — template อยู่ใน repo starter ที่เดียว, infra ไม่ผูก env ของ starter
- B. คัดลอก template เข้า `templates/` ของ infra — พิมพ์สั้นเท่ากัน แต่ต้องแก้ 2 repo ทุกครั้งที่ env เปลี่ยน
- C. คง GHCR digest + wrapper แล้วอัปเดต pin — ต้องตาม pin ทุกครั้ง, ใช้คำสั่ง `infra` ปกติไม่ได้
- ตั้งชื่อ alias ตามหน้าที่ (`cms-admin`) ไม่ใช่ภาษา (`go-admin`) — admin/site เป็น Vue/Astro และจะใช้ร่วมกับ Rust API

## 3. ฝั่ง infra-stack

### 3.1 `templates/starters.list`

```
# alias          repo
cms-api-go       korwlik23/go-api-starter
cms-admin        korwlik23/vue-vite-admin-starter
cms-site         korwlik23/astro-site-starter

# suite = ส่วนต่อท้ายชื่อ:alias ...
cms-go = api:cms-api-go admin:cms-admin site:cms-site
```

เพิ่ม `cms-api-rust` / `-saas` เมื่อ repo มีจริงเท่านั้น

### 3.2 `infra new <ชื่อ> <template|alias|suite|owner/repo> [--mysql|--external-db]`

- template ในตัว (`laravel`, `go`, …) — พฤติกรรมเดิมทุกอย่าง
- alias / `owner/repo` — clone เข้า `projects/<ชื่อ>/src` ด้วย logic ของ `setup-git.sh`
  (private repo → แสดง deploy key แล้วรอ) แล้วใช้ `src/deploy/infra-stack/` เป็น template;
  ขั้นที่เหลือใช้ของเดิม (แทน token, สร้าง DB, `db-user`, เปิด `build: ./src`)
- suite — ทำข้อบนทีละตัวเป็น `<ชื่อ>-api`, `<ชื่อ>-admin`, `<ชื่อ>-site`
  แล้วเขียน `projects/<ชื่อ>.suite` (รายชื่อสมาชิกตามลำดับ deploy)
- repo ไม่มี `deploy/infra-stack/` → หยุด พร้อมบอกว่าต้องมีไฟล์อะไร
- ปฏิเสธ compose ที่ mount `docker.sock` หรือ `privileged: true`

### 3.3 Token ใหม่ใน `.env.example`

| Token | ค่า |
|---|---|
| `__GENERATE_B64__` | `openssl rand -base64 32` ต่อค่า |
| `__DB_RUNTIME_USER__` / `__DB_RUNTIME_PASSWORD__` | `<role>_rt` + รหัสสุ่ม hex |
| `__SUITE_ORIGIN:api\|admin\|site__` | `https://<suite>-api.<BASE_DOMAIN>` / `-admin` / `<suite>.<BASE_DOMAIN>` |
| `__PROXY_CIDR__` | subnet ของ network `proxy` จาก `docker network inspect` |

domain ใช้ subdomain ชั้นเดียว (`shop-api.example.com`) เพราะ Cloudflare Universal SSL
ครอบแค่ชั้นเดียว · สร้างทีละตัว (ไม่ใช่ suite) → `__SUITE_ORIGIN:*__` = `CHANGE_ME`

### 3.4 Runtime role (`scripts/db-user.sh`)

เมื่อ `.env` ของ project มี `DB_RUNTIME_USER`: สร้าง role นั้น (LOGIN, ไม่ใช่ owner),
`GRANT CONNECT`, `USAGE ON SCHEMA public`, `SELECT/INSERT/UPDATE/DELETE` ทุกตาราง,
`USAGE/SELECT` ทุก sequence และ `ALTER DEFAULT PRIVILEGES FOR ROLE <owner>` ให้ตารางที่
migrate สร้างภายหลังได้สิทธิ์เอง · owner เดิม = migration user · project ที่ไม่มี key นี้ไม่เปลี่ยน
· รันซ้ำได้ · ทดสอบ login จริงก่อนจบเหมือนเดิม

### 3.5 `DEPLOY_MIGRATE_SERVICE` (`scripts/lib/deploy-db.sh`)

service ที่ใช้รัน migrate/seed (default = `ROLLOUT_SERVICE` ตามเดิม) — ให้ migrate ใช้
credential ของ owner ใน `api-migrate` โดย container `api` ไม่เคยได้รหัสนั้น

### 3.6 `infra deploy <suite>`

มี `projects/<ชื่อ>.suite` → deploy สมาชิกตามลำดับ, หยุดเมื่อตัวใดล้ม (ไม่ deploy ตัวถัดไป)
· `infra list` / completion / help แสดง suite

## 4. ฝั่ง go-lang-starter

**ก่อนเริ่ม (change แยก, branch ของตัวเอง):** admin/site ใช้ `node:24.8.0` < baseline 24.22.1
(CVE-2026-111497) → อัปเกรด base image

### 4.1 ย้ายไฟล์ deploy

`ops/infra-stack/{api,admin,site}` (parent) → `deploy/infra-stack/` ใน repo ลูกแต่ละตัว
(`docker-compose.yml`, `.env.example`, `README.md`) · ลบ `scripts/deploy-infra-stack.sh`
และ infra pin ใน release manifest · `docs/operations/infra-stack.md` เหลือ `infra new shop cms-go`

### 4.2 api

- `Dockerfile` runtime `scratch` → `alpine` (pin digest + เวอร์ชันใน comment), uid 65532 เดิม, คง `/app/healthcheck`
- compose: `image: ${APP_IMAGE}` + `# build: ./src`, router/service = `__PROJECT__`,
  healthcheck `test ! -f /tmp/drain && wget -qO /dev/null http://localhost:8080/readyz`,
  `docker-rollout.pre-stop-hook=touch /tmp/drain && sleep 35`, คง `read_only` / `tmpfs /tmp` / `cap_drop: ALL` / `no-new-privileges` / resource limits
- `api-migrate`: image เดียวกับ `api`, `profiles: [tools]`, ได้ owner credential เท่านั้น
- `.env.example`: `DB_SSLMODE=disable`, `DB_MIGRATION_USER=__DB_USER__`,
  `DB_RUNTIME_USER=__DB_RUNTIME_USER__`, peppers = `__GENERATE__`, keyrings = `v1:__GENERATE_B64__`,
  origins = `__SUITE_ORIGIN:*__`, `TRUSTED_PROXY_CIDRS=__PROXY_CIDR__`,
  `ROLLOUT_SERVICE=api`, `HEALTHCHECK_PATH=/readyz`, `DEPLOY_MIGRATE=1`,
  `DEPLOY_MIGRATE_SERVICE=api-migrate`, `DEPLOY_MIGRATE_CMD=/app/migrate`,
  `DEPLOY_SEED_CMD=/app/bootstrap` (สร้าง owner คนแรก — ยืนยันว่ารันซ้ำได้ตอนทำ plan)
- `cmd/seed` = fixture สำหรับ local เท่านั้น ห้ามใช้บน production

### 4.3 admin / site

compose: `# build: ./src`, router = `__PROJECT__`, drain hook + healthcheck `/healthz` แบบเดียวกัน,
`API_ORIGIN=__SUITE_ORIGIN:api__` (admin ใช้ `config.template.js` ตอน runtime อยู่แล้ว)

## 5. การทดสอบ

- infra: bash test (repo ยังไม่มีชุด test — วางที่ `tests/` ให้รันได้ทั้ง Git Bash และ VPS):
  parse alias/suite, แทน token ทุกตัว (รวมรหัสที่มี `& | \`), repo ไม่มี `deploy/infra-stack`,
  compose ที่มี `docker.sock` ถูกปฏิเสธ, template เดิม (`go`, `laravel`) ได้ไฟล์เหมือนก่อนแก้
- starter: `go test ./...` ผ่าน, `docker build` ผ่านทั้ง 3 image
- E2E บน VPS ตามเกณฑ์สำเร็จในข้อ 1

**ข้อจำกัด:** เครื่อง dev (Windows) ไม่มี Docker และ agent ยังไม่มีสิทธิ์ SSH `mainvps`
→ docker build / E2E ผู้ใช้ต้องรัน หรือให้สิทธิ์

## 6. ความเสี่ยง

- compose จาก repo ภายนอกรันบนเครื่องเรา — กันด้วยข้อ 3.2 + `infra audit`; ใช้กับ repo ที่ไว้ใจเท่านั้น
- `ALTER DEFAULT PRIVILEGES` มีผลเฉพาะ object ที่ owner สร้าง — migration ต้องรันด้วย owner เสมอ (บังคับด้วยข้อ 3.5)
- `BOOTSTRAP_PASSWORD` อยู่ใน `.env` — ให้เปลี่ยนรหัสหลัง login ครั้งแรก (เขียนในคู่มือ)
- project/template เดิมต้องไม่เปลี่ยนพฤติกรรม — มี test เทียบผลลัพธ์ก่อน/หลัง

## 7. นอกขอบเขต

Rust API starter (design แยก — จะใช้ alias/suite/runtime role ชุดนี้), repo `-saas`,
การ publish image ไป GHCR
