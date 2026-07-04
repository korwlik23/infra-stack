# ✅ TODO — งานที่เหลือหลังติดตั้ง (เครื่อง 217.216.32.198)

> สถานะ ณ 2026-07-04: core + database + monitoring ขึ้นครบ 18 ตัว,
> Alertmanager→Telegram ทำงานแล้ว, Grafana/Uptime Kuma สร้าง admin แล้ว
>
> ทุกคำสั่งรันที่ `/opt/infra-stack` ด้วย user `deploy` เว้นแต่บอกไว้
> ติ๊ก `[x]` เมื่อเสร็จ แล้ว commit ไฟล์นี้กลับเข้า Git ได้เลย (ไม่มี secret)

---

## Phase A — ปิดงานระบบ (ทำให้ครบก่อน deploy โปรเจกต์)

### A1. 🔴 Revoke Telegram token (5 นาที — token เก่าหลุดในภาพแคปแล้ว)

- [ ] เปิด Telegram → คุยกับ `@BotFather` → พิมพ์ `/revoke` → เลือก bot → ได้ token ใหม่
- [ ] เอา token ใหม่ใส่แทนตัวเก่า:

```bash
nano services/alertmanager/alertmanager.yml   # แก้บรรทัด bot_token: "..."
docker restart alertmanager
```

- [ ] ทดสอบว่ายังส่งได้:

```bash
docker exec alertmanager wget -qO- --post-data='[{"labels":{"alertname":"TestAlert","severity":"info"}}]' --header='Content-Type: application/json' http://localhost:9093/api/v2/alerts
```

→ ต้องมีข้อความเข้า Telegram ภายใน ~30 วินาที

- [ ] กันเผลอ commit token:

```bash
git update-index --skip-worktree services/alertmanager/alertmanager.yml
```

### A2. 🔴 ตั้ง cron backup (10 นาที — สำคัญที่สุดในลิสต์นี้)

- [ ] ทดลองรัน backup มือก่อน 1 ครั้ง:

```bash
./scripts/backup.sh
ls -lh backup/archives/postgres/    # ต้องมีไฟล์ all_*.sql.gz ขนาด > 0
```

- [ ] ตั้ง cron:

```bash
crontab -e
```

วางท้ายไฟล์:

```cron
0 3 * * *  /opt/infra-stack/backup/scripts/postgres-backup.sh >> /var/log/infra-backup.log 2>&1
30 3 * * 0 /opt/infra-stack/backup/scripts/volumes-backup.sh  >> /var/log/infra-backup.log 2>&1
```

- [ ] เช้าวันถัดไป เช็คว่า cron ทำงานจริง:

```bash
ls -lh backup/archives/postgres/ && tail /var/log/infra-backup.log
```

- [ ] 🔁 **ภายในเดือนนี้**: ซ้อม restore 1 ครั้ง (`./scripts/restore.sh` — มี confirmation ก่อนเขียนทับ)
  กฎ: backup ที่ไม่เคยลอง restore = ไม่มี backup ([docs/13](docs/13-backup.md))

### A3. 🟠 Uptime Kuma — ตั้ง monitor + แจ้งเตือน (15 นาที)

- [ ] เปิด `https://uptime.tewarach-dev.me` → login
- [ ] Settings → Notifications → Setup Notification → **Telegram**
  → ใส่ bot token (ตัวใหม่จาก A1) + chat ID → Test → Save
  → ติ๊ก **Default enabled** (monitor ใหม่จะผูกอัตโนมัติ)
- [ ] Add New Monitor ทีละตัว (Type: HTTP(s), Interval: 60s):

| Friendly Name | URL |
|---|---|
| Portainer | `https://portainer.tewarach-dev.me` |
| Grafana | `https://grafana.tewarach-dev.me` |
| ZennuaFlow (เครื่องเก่า) | `https://zennuaflow.tewarach-dev.me` |

- [ ] ทดสอบ: ปิด grafana ชั่วคราว `docker stop grafana` → รอ ~2 นาที → ต้องมีแจ้งเตือน
  → `docker start grafana` → ต้องมีข้อความ "Up" ตามมา

### A4. 🟠 เปลี่ยน basicauth ของ netdata / dozzle (10 นาที)

ตอนนี้ 2 ตัวนี้ login ไม่ได้เพราะ hash ยังเป็น `CHANGE_ME`

- [ ] สร้าง hash (บนเซิร์ฟเวอร์):

```bash
sudo apt install -y apache2-utils
htpasswd -nb admin 'รหัสผ่านที่ต้องการ'
# ได้ผลลัพธ์แบบ: admin:$apr1$xxxx$yyyyyyyy
```

- [ ] ⚠️ ก่อนวางใน compose ต้องเปลี่ยน `$` ทุกตัวเป็น `$$` เช่น
  `admin:$apr1$ab12$cd34` → `admin:$$apr1$$ab12$$cd34`
- [ ] แก้ 2 ไฟล์ (บรรทัด `basicauth.users=`):

```bash
nano services/netdata/docker-compose.yml
nano services/dozzle/docker-compose.yml
docker compose --env-file .env -f docker/docker-compose.monitoring.yml up -d netdata dozzle
```

- [ ] ทดสอบ: เปิด `https://netdata.tewarach-dev.me` และ `https://logs.tewarach-dev.me`
  → ใส่ admin + รหัส → เข้าได้

### A5. 🟡 Grafana — import dashboards (10 นาที)

- [ ] เปิด `https://grafana.tewarach-dev.me` → Dashboards → New → **Import**
- [ ] Import ทีละ ID (ช่อง datasource เลือก **Prometheus**):

| ID | ชื่อ | ดูอะไร |
|----|------|--------|
| 1860 | Node Exporter Full | CPU / RAM / Disk / Network |
| 193 | Docker monitoring | container ราย ตัว |
| 9628 | PostgreSQL Database | postgres (exporter มีแล้ว) |
| 11835 | Redis Dashboard | redis (exporter มีแล้ว) |

- [ ] เปิด dashboard 1860 ดูค่า baseline ตอนเครื่องว่าง แล้วจดไว้:
  RAM ใช้ไป ~___ GB, CPU ~___% (ไว้เทียบตอนเครื่อง "ตึง" — [docs/18](docs/18-scale.md))

---

## Phase B — Deploy โปรเจกต์ (ทำทีละตัว ตามลำดับ)

> แนวคิด CI/CD ที่ใช้: **build บนเซิร์ฟเวอร์ ฟรี 100%** ไม่ใช้ GitHub Actions
> อ่านก่อนเริ่ม: [docs/19-cicd.md](docs/19-cicd.md) + [docs/25-zero-downtime.md](docs/25-zero-downtime.md)

### B1. 🟢 n8n (30 นาที — ง่ายสุด เริ่มตัวนี้ DNS ก็ชี้รออยู่แล้ว)

- [ ] สร้าง project:

```bash
./scripts/create-project.sh n8n n8n
```

- [ ] สร้าง encryption key แล้วเก็บใน password manager **เดี๋ยวนี้** (หาย = credentials ทุก workflow กู้ไม่ได้):

```bash
openssl rand -hex 24
```

- [ ] ตั้งค่า:

```bash
nano projects/n8n/.env
```

```env
APP_DOMAIN=n8n.tewarach-dev.me
N8N_ENCRYPTION_KEY=<ค่าจาก openssl ข้างบน>
DB_DATABASE=n8n_db        # มีอยู่แล้ว (สร้างตอน postgres init)
DB_USERNAME=infra          # ตาม POSTGRES_USER ใน /opt/infra-stack/.env
DB_PASSWORD=<POSTGRES_PASSWORD จาก /opt/infra-stack/.env>
```

- [ ] Start + เช็ค:

```bash
cd projects/n8n && docker compose up -d
docker compose logs -f    # รอเห็น "Editor is now accessible" แล้ว Ctrl+C
cd ../..
```

- [ ] เปิด `https://n8n.tewarach-dev.me` → สร้าง owner account
- [ ] ทดสอบ workflow แรก: Webhook trigger → Execute → ยิง curl ตาม URL ที่มันให้ → เห็น execution สำเร็จ
- [ ] เพิ่ม monitor `https://n8n.tewarach-dev.me` ใน Uptime Kuma

### B2. 🟢 Laravel — ZennuaFlow ย้ายมาเครื่องนี้ (2-4 ชั่วโมง เผื่อเวลา)

> เช็คก่อน: ZennuaFlow มี Dockerfile หรือยัง? ถ้ายัง ต้องเพิ่มใน repo ของ app ก่อน
> (แนะนำ php-fpm + nginx หรือ FrankenPHP, expose port 8080, มี `curl` ใน image)

**เตรียม (ครั้งเดียว):**

- [ ] สร้าง deploy key แบบ read-only บนเซิร์ฟเวอร์:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/deploy_zennuaflow -N ""
cat ~/.ssh/deploy_zennuaflow.pub
```

- [ ] GitHub → repo zennuaflow → Settings → Deploy keys → Add key (ไม่ติ๊ก write)
- [ ] ตั้ง ssh alias:

```bash
nano ~/.ssh/config
```

```text
Host github.com-zennuaflow
    HostName github.com
    User git
    IdentityFile ~/.ssh/deploy_zennuaflow
```

**Deploy:**

- [ ] สร้าง project + clone source:

```bash
./scripts/create-project.sh zennuaflow laravel
cd projects/zennuaflow
git clone git@github.com-zennuaflow:korwlik23/zennuaflow.git src
```

- [ ] เปิดโหมด build-on-server: `nano docker-compose.yml` → เอา `#` ออกหน้า `build: ./src` (บรรทัดเดียว ใน service `-app`)
- [ ] ตั้งค่า `nano .env` — จุดสำคัญ:

```env
APP_DOMAIN=zennuaflow.tewarach-dev.me   # ⚠️ ยังไม่สลับ DNS — ดูข้อถัดไป
APP_KEY=<จาก .env ของเครื่องเก่า — ต้องตัวเดิม! ไม่งั้นข้อมูลเข้ารหัสเดิมอ่านไม่ได้>
DB_DATABASE=zennuaflow_db
DB_PASSWORD=<POSTGRES_PASSWORD>
REDIS_PASSWORD=<REDIS_PASSWORD>
HEALTHCHECK_PATH=/up       # Laravel 11+; เก่ากว่านั้นสร้าง route /up เอง
```

- [ ] **ย้ายข้อมูลจากเครื่องเก่า** (ทำตอนคนใช้น้อย):

```bash
# บนเครื่องเก่า: dump database
pg_dump -U <user> zennuaflow_db | gzip > /tmp/zennuaflow.sql.gz
# ดึงมาเครื่องใหม่:
scp <user>@20.63.219.103:/tmp/zennuaflow.sql.gz /tmp/
gunzip -c /tmp/zennuaflow.sql.gz | docker exec -i postgres psql -U infra -d zennuaflow_db
```

- [ ] Build + start + migrate:

```bash
cd /opt/infra-stack && ./scripts/deploy.sh zennuaflow
docker compose --project-directory projects/zennuaflow exec zennuaflow-app php artisan migrate --force
```

- [ ] ทดสอบก่อนสลับ DNS (ยิงตรงเข้าเครื่องใหม่):

```bash
curl -sk -H "Host: zennuaflow.tewarach-dev.me" https://localhost -o /dev/null -w "%{http_code}\n"   # ต้อง 200
```

- [ ] **สลับ DNS**: Cloudflare → แก้ A record `zennuaflow` จาก `20.63.219.103` → `217.216.32.198`
- [ ] เปิดเว็บจริง ทดสอบ login / งานหลัก / queue:

```bash
docker compose --project-directory projects/zennuaflow exec zennuaflow-app php artisan queue:monitor redis
```

- [ ] เก็บเครื่องเก่าไว้ 1 สัปดาห์ก่อนปิด (เผื่อ rollback DNS กลับ)

### B3. 🟢 Next.js (1-2 ชั่วโมง)

> เตรียมใน repo ของ app: `next.config.js` ใส่ `output: "standalone"` + Dockerfile
> (multi-stage ตาม official example, ท้ายสุด `node server.js`, port 3000)

- [ ] Deploy key + ssh alias (ทำเหมือน B2 เปลี่ยนชื่อ)
- [ ] สร้าง + clone + เปิด build:

```bash
./scripts/create-project.sh <ชื่อ> nextjs
cd projects/<ชื่อ>
git clone git@github.com-<ชื่อ>:korwlik23/<repo>.git src
nano docker-compose.yml    # เอา # ออกหน้า build: ./src
nano .env                  # APP_DOMAIN, DATABASE_URL (ถ้าใช้), HEALTHCHECK_PATH
```

- [ ] สร้าง `/api/health` ใน app ที่ตอบ 200 เร็วๆ แล้วตั้ง `HEALTHCHECK_PATH=/api/health`
- [ ] เพิ่ม A record `<ชื่อ>.tewarach-dev.me` → `217.216.32.198` ใน Cloudflare
- [ ] `cd /opt/infra-stack && ./scripts/deploy.sh <ชื่อ>` → เปิดเว็บ → เพิ่ม Uptime Kuma monitor
- [ ] ⚠️ จำ: ตัวแปร `NEXT_PUBLIC_*` ฝังตอน build — เปลี่ยนค่าต้อง deploy ใหม่ ไม่ใช่แค่ restart

### B4. 🟢 เปิด auto-deploy (5 นาที — ทำหลัง B1-B3 นิ่งแล้ว)

- [ ] `crontab -e` เพิ่ม:

```cron
*/2 * * * * /opt/infra-stack/scripts/auto-deploy.sh >> /var/log/infra-deploy.log 2>&1
```

- [ ] ทดสอบ: push commit เล็กๆ เข้า repo ของ app → รอ 2-4 นาที → `tail -f /var/log/infra-deploy.log`
  ต้องเห็นมัน pull + build + rolling deploy เอง
- [ ] ทดสอบ zero-downtime จริง (terminal ที่สอง ระหว่าง deploy):

```bash
while true; do curl -s -o /dev/null -w "%{http_code} " https://<เว็บ>.tewarach-dev.me; sleep 1; done
# ต้องเห็น 200 ล้วน ไม่มี 502
```

---

## Phase C — ภายในเดือนนี้ (ไม่บล็อกอะไร แต่อย่าลืม)

- [ ] **Cloudflare R2**: สมัคร → สร้าง buckets (`images`, `videos`, `uploads`, `backup`)
  → ติดตั้ง rclone → backup จะ sync offsite อัตโนมัติ ([docs/12](docs/12-r2.md))
- [ ] **ซ้อม disaster recovery**: อ่าน [docs/13](docs/13-backup.md) ท้ายบท — จับเวลา restore
- [ ] **ทดสอบ rollback**: `./scripts/rollback.sh <project> <tag>` กับ project ทดลอง ([docs/25](docs/25-zero-downtime.md))
- [ ] **Beszel agent**: ค่อยเปิดตอนมีเครื่องที่ 2 — ตอนนี้หยุดไว้ถูกแล้ว ([docs/23](docs/23-beszel.md))
- [ ] เช็คสุขภาพประจำอาทิตย์ 5 นาที ตามลิสต์ใน [docs/14-monitoring.md](docs/14-monitoring.md)

---

## ⚠️ กฎประจำเครื่องนี้ (อ่านซ้ำได้เรื่อยๆ)

1. **ห้ามใช้ `--remove-orphans`** กับ docker compose บนเครื่องนี้ — จะลบ stack อื่นทิ้ง
2. `.env` และ `alertmanager.yml` (มี token) **ห้าม commit** — .gitignore + skip-worktree กันไว้แล้ว
3. Deploy ใช้ `./scripts/deploy.sh <ชื่อ>` เสมอ — อย่า `docker compose up -d` มือใน projects/ (เสีย zero-downtime)
4. Migration ต้องเป็น expand/contract — ห้าม rename/drop column ใน release เดียว ([docs/25](docs/25-zero-downtime.md))
5. แก้อะไรใน services/ บนเซิร์ฟเวอร์ ให้แก้ใน repo (เครื่อง dev) แล้ว push ด้วย — Git คือ source of truth
