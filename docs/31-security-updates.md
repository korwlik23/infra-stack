# 31 — อัปเดตความปลอดภัยอัตโนมัติ + จำกัดความเสียหาย

## 🎯 เป้าหมาย

CVE ใหม่ออกแทบทุกวัน แต่ที่ต้องสนใจคือ CVE ที่ **อยู่ในของที่รันอยู่จริง** และ **มีแพตช์แล้ว** เอกสารนี้ตั้งระบบ 4 ชั้น:

| ชั้น | อัปเดตอะไร | ทำงานยังไง | ต้องมีคนกดไหม |
|------|-----------|-----------|---------------|
| 1. OS ของเครื่อง | Ubuntu package | `unattended-upgrades` (มีตั้งแต่ติดตั้ง — docs/02) | ไม่ |
| 2. image ของ stack | Traefik, Grafana, Postgres … | Watchtower ทุกคืน 04:00 · หรือ `infra update <stack>` | ไม่ |
| 3. PHP / Node / OS **ใน image ของ project** | base image ใน Dockerfile (`FROM php:8.3-fpm`) | `infra refresh` ทุกคืน 05:00 | ไม่ |
| 4. library ของแอป | `composer.lock` / `package-lock.json` / `go.sum` | Renovate (ใน repo ของแอป) | แพตช์ไม่ต้อง · minor/major กด merge |

และมี **ตัวตรวจ** คือ `infra cve` ทุกเช้า 06:00 สแกนของที่รันอยู่ แล้วแจ้ง Telegram ถ้ายังมี CVE ที่แก้ได้แต่ยังไม่ได้แก้

ส่วนที่สองคือ **ถ้าโดนเจาะก่อนแพตช์ออก (zero-day) ให้เสียหายน้อยที่สุด**: แอปหนึ่งโดน ต้องไม่ลามไปแอปอื่นหรือทั้งเครื่อง

## ⚙️ ตั้งครั้งเดียวต่อเครื่อง

**เครื่องใหม่: ไม่ต้องทำอะไร** — `install.sh` ตั้ง cron ทั้งหมดให้แล้ว · `infra new` สร้าง database user ของ project ให้เอง

**เครื่องที่ติดตั้งก่อนหน้านี้:** `git pull` แล้ว

```bash
infra cron                # เพิ่ม refresh (05:00) + cve-scan (06:00) — ตัวเดิมไม่แตะ
infra db-user --all       # ทุก project ที่ยังใช้ superuser → user ของตัวเอง + restart ให้ (ถามก่อน)
infra audit               # ดูว่ายังขาดข้อไหน
```

ทุกข้อความไป Telegram เดียวกับ deploy (`NOTIFY_TELEGRAM_*` ใน `.env` — docs/19)

---

## 3. PHP / Node / OS ใน image ของ project — `infra refresh`

image ของ project build ครั้งเดียวตอน push ถ้าไม่มีใครแตะ repo หลายเดือน PHP/Node ข้างในจะค้างเวอร์ชันเก่า
ทั้งที่ Docker Hub ออกแพตช์ไปแล้ว

**ทุก deploy:** `deploy.sh` build ด้วย `--pull` = ดึง base image ล่าสุดเสมอ (`php:8.3-fpm` → 8.3.x ตัวล่าสุด)

**ทุกคืน 05:00 (`refresh.sh`):** ต่อ project ที่ build บนเครื่อง
1. หา base image ของ stage ที่รันจริง (FROM สุดท้าย หรือ `build.target`) — อ่านค่า `ARG PHP_VERSION=8.5` ให้เอง
   และ Dockerfile ตาม `build.dockerfile` ใน compose · stage ที่ใช้แค่ตอน build (node ทำ asset, composer) ไม่นับ
2. `docker pull` base ตัวนั้น แล้วดูว่า image บนเว็บ (`APP_IMAGE`) build บน base เวอร์ชันนี้ไหม (layer ของ image
   ขึ้นต้นด้วย layer ของ base) — ไม่ต้องจดสถานะไว้ที่ไหน
3. ไม่ใช่ = base ออกแพตช์ใหม่หลัง build → `deploy.sh` ตามปกติ: backup DB → migrate → rolling (เว็บไม่ดับ) → smoke test
   → ล้ม + `DEPLOY_AUTO_ROLLBACK=1` ถอยกลับเอง · Telegram บอกผล "โดย: อัปเดตแพตช์ base image (php:8.3-fpm)"

**ข้ามเอง (ไม่ deploy ทับ) เมื่อ:** มี commit ที่ยังไม่ขึ้นเว็บ · deploy ล่าสุดล้ม / smoke ล้ม / รอคำตอบ seed ·
project ถูก rollback อยู่ · มี deploy กำลังรัน

```bash
infra refresh               # ทุก project ตอนนี้
infra refresh myapp         # project เดียว
infra logs refresh          # ผลของ cron
```

| ค่าใน `projects/<ชื่อ>/.env` | ผล |
|---|---|
| `DEPLOY_REFRESH=0` | ไม่ refresh project นี้ |
| `DEPLOY_REFRESH=1` | project ที่ใช้ image จาก registry (ไม่มี `build:` เช่น n8n) ให้ refresh ด้วย — เทียบ digest ใน registry |
| `DEPLOY_DOCKERFILE=src/docker/Dockerfile` | บังคับ Dockerfile เอง (ปกติอ่านจาก `build:` ใน compose ให้แล้ว) |
| `DEPLOY_BUILD_PULL=0` | build ไม่ `--pull` (registry ล่มบ่อย) — refresh ก็จะไม่ได้ผล |

**Dockerfile ควรใช้ tag แบบลอย** เช่น `php:8.3-fpm`, `node:22-alpine` — ได้แพตช์เองโดยไม่เปลี่ยน minor
ถ้า pin เต็ม (`php:8.3.12-fpm`) refresh จะไม่มีอะไรใหม่ ให้ Renovate (ข้อ 4) เปิด PR เปลี่ยนเลขให้แทน

⚠️ n8n (`DEPLOY_REFRESH=1`) ใช้ `n8nio/n8n:latest` = อาจข้าม major version (มี breaking change) ·
ถ้าเปิด ให้ pin major ใน compose ก่อน แล้วอัปเกรด major เองหลังอ่าน release notes

---

## 4. library ของแอป — Renovate

library อยู่ใน repo ของแอป ไม่ใช่บนเซิร์ฟเวอร์ ถ้าเซิร์ฟเวอร์ `composer update` เอง โค้ดบนเครื่องจะไม่ตรงกับ Git
→ ให้บอตบน GitHub เปิด PR แทน แล้ว auto-deploy ทำงานตามปกติเมื่อ merge

[Renovate](https://github.com/apps/renovate) ฟรี และ **merge เองได้โดยไม่ต้องใช้ GitHub Actions**

### ตั้ง (ต่อ repo ของแอป)

1. GitHub → repo → Settings → Code security → เปิด **Dependabot alerts** (Renovate ใช้ข้อมูลนี้ทำ PR ช่องโหว่)
2. ติดตั้ง Renovate App: <https://github.com/apps/renovate> → เลือก repo ของแอป
3. copy [`examples/renovate/renovate.json`](../examples/renovate/renovate.json) ไปไว้ที่ root ของ repo แอป แล้ว push
4. Renovate เปิด PR "Configure Renovate" มาก่อน (ถ้าไม่ได้วางไฟล์ในข้อ 3) → merge

### ทำงานยังไง (ตามไฟล์ตัวอย่าง)

| อัปเดต | Renovate ทำ |
|--------|-------------|
| แพตช์ `x.y.Z` (library ≥ 1.0) | merge เองตอนตี 1–5 → push เข้า main → **auto-deploy** (smoke test + rollback กันไว้) |
| minor / major | เปิด PR รอคนกด merge (กดจากมือถือได้) |
| library `0.x` | เปิด PR เสมอ (เปลี่ยน API ได้ทุกเวอร์ชัน) |
| แก้ช่องโหว่ (label `security`) | เปิด PR ทันทีไม่รอรอบ · ถ้าเป็นแพตช์ก็ merge เอง |

- `minimumReleaseAge: 3 days` = **ไม่หยิบเวอร์ชันที่เพิ่งออกไม่ถึง 3 วัน** กัน supply-chain attack
  (ปล่อย package ปลอมเวอร์ชันใหม่ → registry มักลบภายในไม่กี่วัน) · PR แก้ช่องโหว่ไม่ต้องรอ
- `ignoreTests: true` = merge แม้ repo ไม่มี CI · ถ้า repo มี CI ที่รันเทส ลบบรรทัดนี้ออก Renovate จะรอเทสผ่านก่อน
- branch protection ที่บังคับ "require approvals" ทำให้ Renovate merge เองไม่ได้ → แพตช์ก็จะรอคนกดเหมือน minor

---

## 🔎 ตัวตรวจ — `infra cve`

```bash
infra cve                 # สแกนตอนนี้ แสดงทุกรายการ
infra logs cve-scan       # ผลของ cron ทุกเช้า
```

- สแกน **image ที่รันอยู่ทุกตัว** ด้วย [Trivy](https://trivy.dev) (รันเป็น container ชั่วคราวแล้วลบทิ้ง)
- ใช้ disk ราว **2GB** (ฐานข้อมูล CVE ใน volume `trivy-cache` 1.7GB + image ~230MB) · สแกน image ละ ~8 วินาที
- **disk ว่างน้อยกว่า 10GB → ข้ามเอง** (แจ้ง Telegram ครั้งเดียว) กัน VPS เล็กเต็ม · `CVE_MIN_FREE_GB` ปรับเกณฑ์ · `CVE_SCAN=0` ปิด
  ไม่ใช้แล้ว: ลบบรรทัด `cve-scan.sh` ใน `crontab -e` แล้ว `docker volume rm trivy-cache`
- เฉพาะระดับ `CRITICAL,HIGH` และ **มีเวอร์ชันที่แก้แล้ว** — ไม่ใช่ข่าว CVE ทั้งโลก
- cron ส่ง Telegram **เฉพาะ CVE ที่ไม่เคยแจ้ง** · ไม่มีของใหม่ = เงียบ
- แต่ละรายการบอกวิธีแก้:

```text
🛡️ CVE ใหม่ 2 รายการ (มีแพตช์แล้ว · ระดับ CRITICAL,HIGH)
• 🔴 myapp: CVE-2026-1234 openssl 3.0.13 → 3.0.15 — infra refresh myapp
• 🟠 myapp: CVE-2026-5678 guzzlehttp/guzzle 7.8.0 → 7.8.2 — อัปเดต guzzlehttp/guzzle → 7.8.2 ใน repo ของ myapp (Renovate)
```

ตั้งใน `.env` กลาง:

| ค่า | default | ใช้เมื่อ |
|-----|---------|----------|
| `CVE_SEVERITY` | `CRITICAL,HIGH` | อยากเห็น `MEDIUM` ด้วย |
| `TRIVY_IMAGE` | `aquasec/trivy:0.69.3` | อัปเกรด Trivy — **pin เวอร์ชันเสมอ** อ่าน release notes ก่อนเปลี่ยน (scanner มีสิทธิ์อ่าน docker.sock) |

---

## 🛡️ ยามเฝ้า VPS — `infra watch`

ตรวจทุกชั่วโมง (cron นาทีที่ 7) — เจอสัญญาณผู้บุกรุก **ส่ง Telegram ทันทีจาก script ไม่ผ่าน AI** ·
วันละครั้ง (`WATCH_REPORT_HOUR` default 7 โมง) ส่งตัวเลขสรุปให้ **Gemini (ฟรี) ผ่าน n8n** เรียบเรียงเป็นภาษาไทย

| เตือนทันที | ทำไมสำคัญ |
|-----------|-----------|
| SSH login จาก IP ที่ไม่เคยเห็น | มีคนได้ key ไป |
| `authorized_keys` · crontab · `/etc/cron.d` · sudoers.d · sshd_config · `/etc/passwd` · systemd unit เปลี่ยน | ผู้บุกรุกฝังทางเข้าถาวรตรงนี้ |
| container นอก compose รันค้าง · container ใหม่ที่ privileged / mount `docker.sock` | ตัวขุดเหมือง / ยึดเครื่อง |
| ไฟล์ `.php` / `.phar` ใหม่ใน `storage/` `public/` ของแอป · executable ใหม่ใน `/tmp` ของ container | webshell (เจาะเว็บ PHP แบบที่เจอบ่อยสุด) |
| CPU ของ container เกิน `WATCH_CPU_ALERT` (150% = 1.5 core) 2 ชั่วโมงติด · ส่งข้อมูลออกเกิน `WATCH_TX_ALERT_GB` ต่อชั่วโมง | ขุดเหมือง / ดูดข้อมูล |

- รอบแรกจดของที่มีอยู่เป็น baseline (`logs/watch/`) · แต่ละเรื่องแจ้ง**ครั้งเดียว** · deploy image ใหม่ = จด baseline ใหม่เงียบ ๆ
- คุณแก้เอง (เพิ่ม SSH key, `infra cron`, ลง package) ก็จะเตือนหนึ่งครั้ง — ปกติ
- **AI ไม่ได้เป็นคนตัดสิน**: ได้แค่ตัวเลขสรุป (ไม่มี IP / user / log ดิบ) · ไม่มีสิทธิ์อะไรบนเครื่อง ·
  รายงานแนบตัวเลขดิบเสมอ · AI ล่ม = ยังได้ตัวเลขดิบ
- ข้อจำกัด: user `deploy` อ่าน `/var/log/auth.log` ไม่ได้ → เห็นเฉพาะ login แบบมี terminal และไม่รู้จำนวน SSH ล้มเหลว
  เปิดให้เห็นครบ: `sudo usermod -aG adm deploy`

### ต่อ Gemini (ครั้งเดียว — ไม่ต่อก็ยังเตือนทันทีได้ รายงานจะเป็นตัวเลขดิบ)

1. สร้าง API key ฟรีที่ https://aistudio.google.com/apikey (ไม่ต้องผูกบัตร = ไม่มีทางเสียเงิน)
   แนะนำ: Google Cloud Console → APIs & Services → Credentials → key → API restrictions → **Generative Language API** อย่างเดียว
2. n8n → Credentials → Create → **Google Gemini(PaLM) Api** → วาง key → ชื่อ `Gemini infra-watch` → Save
3. บนเครื่อง:

```bash
infra watch --setup     # นำ workflow เข้า n8n + สร้าง token + ทดสอบ
infra watch --report    # ส่งรายงานเข้า Telegram เดี๋ยวนี้
```

- workflow รับคำขอที่ `…/webhook/infra-watch` เฉพาะที่มี token ถูก (`WATCH_N8N_TOKEN`) — ไม่มี/ผิด = 403 (กันคนนอกใช้โควตา Gemini)
- model: `gemini-flash-lite-latest` (ชื่อ `-latest` Google ชี้รุ่นล่าสุดให้เอง) · คนใช้เยอะ (503) → รอแล้วลองใหม่ + สลับไป `gemini-flash-latest`
- free tier: Google อาจใช้ข้อมูลที่ส่งไปปรับปรุงโมเดล — จึงส่งแค่ตัวเลข

```bash
infra watch             # ตรวจตอนนี้ แสดงผลอย่างเดียว (ไม่ส่ง ไม่แตะ baseline)
infra logs watch        # ผลทุกชั่วโมง
# ปิด: WATCH=0 ใน .env · container ของคุณเองที่รันนอก compose: WATCH_IGNORE_CONTAINERS='^(my-tool|test-)'
```

## 🧱 จำกัดความเสียหายเมื่อโดนเจาะ

### 5. database user แยกต่อ project

เดิมทุก project ต่อ Postgres ด้วย `POSTGRES_USER` (superuser) ตัวเดียวกัน → แอปเดียวโดน SQL injection =
อ่าน/ลบ **ทุก database** และสั่งคำสั่งบนเครื่องได้ผ่าน `COPY … PROGRAM`

ตอนนี้: `infra new` สร้าง user ของ project (ชื่อเดียวกับ project, `-` → `_`) เป็นเจ้าของ database ของตัวเองเท่านั้น
role อื่นที่ไม่ใช่ superuser connect database นี้ไม่ได้

**project ที่สร้างก่อนหน้านี้** (`infra audit` ขึ้น ❌ "ต่อ database ด้วย superuser"):

```bash
infra db-user --all       # ทุกตัวที่ยังใช้ superuser ในคำสั่งเดียว (ถามก่อน แล้ว restart ให้)
# หรือทีละตัว:
infra db-user myapp       # สร้าง user + ย้ายเจ้าของตาราง + แก้ .env + ทดสอบ login (เว็บยังไม่สะดุด)
infra restart myapp       # ให้ container ใช้ user ใหม่ (rolling — เว็บไม่ดับ)
```

n8n ที่ติดตั้งจาก `install.sh` ก็ย้ายได้เหมือนกัน (host อยู่ใน compose — script อ่านให้) · n8n ไม่มี rolling → ดับไม่กี่วินาทีตอน restart

- รันซ้ำได้ · superuser ยังใช้ได้ตามเดิม (backup / `infra psql` / restore ใช้ superuser)
- ระหว่างย้ายเจ้าของ แต่ละตารางถูก lock สั้น ๆ — ทำตอนคนใช้น้อย
- แอปที่ `config:cache` ใน Dockerfile: ใช้ `infra deploy myapp` แทน `restart`
- MySQL (`--mysql`) แยก user ต่อ project อยู่แล้ว

### 6. `no-new-privileges` ใน container ของ project

template ทุกตัวใส่ `security_opt: [no-new-privileges:true]` = โปรเซสในแอปที่โดนเจาะยกระดับสิทธิ์ผ่าน setuid
(เช่น `sudo`, `su`) ไม่ได้ · project เดิม: เพิ่มใต้ทุก service ใน `projects/<ชื่อ>/docker-compose.yml`

```yaml
    security_opt:
      - no-new-privileges:true
```

แล้ว `infra restart <ชื่อ>` · entrypoint ของ image ที่ต้อง `sudo` จะ start ไม่ขึ้น (ส่วนน้อยมาก — `gosu`/`su-exec` ที่รันจาก root ใช้ได้)

### 7. R2 key แยกต่อ project

template เติม R2 key จาก `.env` กลางให้ = key ตัวเดียวกับ **backup** → แอปโดนเจาะ = ลบ backup off-site ได้
Cloudflare → R2 → Manage API tokens → สร้าง token **Object Read & Write เฉพาะ bucket ของ project** แล้ว
`infra env <ชื่อ>` เปลี่ยน `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` (`infra audit` เตือนเมื่อยังใช้ตัวเดียวกัน)

### 8. ทำที่ GitHub / Cloudflare (script ทำให้ไม่ได้)

- [ ] **ทุกคนที่ push ได้เปิด 2FA** — push เข้า main = รันโค้ดบนเซิร์ฟเวอร์ได้ (auto-deploy)
- [ ] branch protection ของ main: ห้าม force-push · จำกัดคนที่ push ตรงได้
- [ ] deploy key เป็นแบบ **read-only** (`infra git` สร้างให้แบบนี้อยู่แล้ว — อย่าติ๊ก Allow write access)
- [ ] หน้าแอดมิน (Portainer, Grafana, Dozzle, Netdata, pgAdmin …) อยู่หลัง **Cloudflare Access** (Zero Trust ฟรี 50 user)
      — ตัวที่ mount `docker.sock` (Portainer, Dozzle, Netdata) มี CVE เมื่อไหร่ = root ทั้งเครื่อง basicauth ชั้นเดียวไม่พอ
- [ ] Cloudflare WAF → Managed rules เปิด (ช่วยบล็อกการยิงช่องโหว่ดัง ๆ ระหว่างรอแพตช์)
- [ ] bucket ของ **backup** เปิด R2 **Bucket Lock** (retention ≥ 30 วัน) = ไฟล์ลบ/ทับไม่ได้จนครบกำหนด
      แม้ใช้ key ของเครื่องนี้ (เครื่องโดนยึด / ransomware → backup off-site ยังอยู่)

## 🧪 ทดสอบ

```bash
infra cron                    # ✅ refresh ✅ cve-scan
infra refresh                 # ทุก project: ✅ base image ล่าสุดแล้ว (หรือ deploy ถ้ามีแพตช์)
infra cve                     # เห็นรายการ (หรือ "รวม 0 รายการ")
infra db-user myapp && infra restart myapp && infra check myapp
infra audit                   # หมวด 6–8 ไม่มี ❌
```

## 🔄 Rollback

| ย้อนอะไร | ทำ |
|---------|----|
| refresh deploy แล้วแอปพัง | ถ้า `DEPLOY_AUTO_ROLLBACK=1` ถอยเองแล้ว · ไม่งั้น `infra rollback <ชื่อ>` — refresh จะไม่ทำซ้ำจนกว่าจะ deploy สำเร็จครั้งถัดไป · ปิดถาวร `DEPLOY_REFRESH=0` |
| Renovate merge แพตช์แล้วแอปพัง | `infra rollback <ชื่อ>` แล้ว revert commit ใน GitHub · ใส่ package นั้นใน `packageRules` ให้ `automerge: false` |
| db-user แล้วแอปต่อ DB ไม่ได้ | `infra env <ชื่อ>` ใส่ `DB_USERNAME` / `DB_PASSWORD` (หรือ `DATABASE_URL`) กลับเป็นค่า superuser จาก `infra secrets` แล้ว `infra restart <ชื่อ>` — user ใหม่ยังเป็นเจ้าของตาราง superuser ใช้ได้ทุกอย่าง |
| ปิด cron | `crontab -e` ลบบรรทัด `refresh.sh` / `cve-scan.sh` |
