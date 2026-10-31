# InfraStack Installation Checklist

ใช้ checklist นี้กับ Ubuntu VPS เครื่องใหม่หนึ่งเครื่อง งานทั้งหมดเริ่มเป็นสถานะยังไม่ทำ
และต้องตรวจผลจริงก่อนติ๊กเสร็จ อ่านภาพรวมที่ [GUIDE.md](GUIDE.md) — ไม่เคยติดตั้งมาก่อน
ให้ทำตาม [docs/INSTALL.md](docs/INSTALL.md) ทีละขั้น แล้วใช้ไฟล์นี้ติ๊กตรวจ
(ติดปัญหา: [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md))

> เก็บ `.env`, private keys, certificates, backup archives และข้อมูล runtime ไว้นอก
> Git เสมอ ตัวอย่างใน repository ใช้ค่าจำลองเท่านั้น

## 1. Prerequisites — เตรียมเครื่องและสิทธิ์เข้าถึง

- [ ] เตรียม Ubuntu VPS (22.04 / 24.04) ที่เข้าผ่าน SSH หรือ provider console ได้ — มีรหัส root
- [ ] สร้าง SSH key บนเครื่องผู้ดูแล (`ssh-keygen -t ed25519`) และสำรอง private key ในที่ปลอดภัย
- [ ] โดเมนอยู่ใน Cloudflare สถานะ **Active** แล้ว (ย้าย nameserver อาจรอหลายชั่วโมง — ทำล่วงหน้า)
      และ SSL/TLS mode = **Full (strict)**
- [ ] เปิด inbound เฉพาะ SSH, HTTP และ HTTPS ที่ firewall ของ provider (ถ้ามี)

DNS record **ไม่ต้องสร้างล่วงหน้า** — `install.sh` โชว์ตารางชื่อที่ต้องสร้างพร้อม IP และรอให้ระหว่างติดตั้ง

รายละเอียด: [docs/INSTALL.md](docs/INSTALL.md) ขั้นที่ 1–3

## 2. ช่วง A — เตรียมเครื่องและ user (root)

- [ ] เข้าเครื่องเป็น root แล้ววางคำสั่งเดียว (user ที่ sudo ได้: ใช้ `| sudo bash`)

```bash
curl -fsSL https://raw.githubusercontent.com/korwlik23/infra-stack/main/prepare.sh | bash
```

- [ ] ตั้งรหัส sudo ของ `deploy` (จดไว้) และวาง SSH public key เมื่อถูกถาม
- [ ] จบช่วง A เห็น `permitrootlogin no` / `passwordauthentication no` และ `✅ ช่วง A เสร็จ`
- [ ] ตอบ Enter ที่ `เริ่มติดตั้ง InfraStack ต่อเลยไหม?` (สลับเป็น deploy ให้เอง ไม่ต้อง logout)

ตรวจ (ทีหลังได้):

```bash
sudo ufw status verbose
sudo fail2ban-client status sshd
id deploy                      # มี group sudo และ docker
```

รายละเอียด: [docs/02-security.md](docs/02-security.md)

## 3. ช่วง B — ติดตั้งระบบ (deploy)

- [ ] ตอบโดเมน, อีเมล (Let's Encrypt), ติดตั้ง n8n ไหม → ยืนยัน
      (โดเมนเดียวกับเครื่องอื่นที่ยังใช้งาน → ใช้ชื่อย่อย เช่น `sg.example.com` — [docs/11](docs/11-cloudflare.md))
- [ ] สร้าง DNS record ใน Cloudflare ตามตารางที่สคริปต์แสดง จนขึ้น `✅ DNS ครบ` และ `✅ ครบ … ชื่อ` (HTTPS)
- [ ] ตรวจว่า `.env` ถูก ignore และไม่มี secret ถูก stage

```bash
git check-ignore -v .env
git status --short
```

## 4. Core — Traefik และ Portainer

- [ ] `infra status` ไม่มี container ที่ Exited / Restarting / unhealthy และ HTTPS ✅ ทุกชื่อ
- [ ] login Portainer ด้วย `admin` / `PORTAINER_ADMIN_PASSWORD` (`infra secrets`) — ถ้าสรุปท้ายบอกให้สร้างเอง
      ต้องสร้าง**ภายใน 5 นาที**
- [ ] หน้า Traefik dashboard, Netdata, Dozzle login ด้วย `DASHBOARD_USER` / `DASHBOARD_PASSWORD`

รายละเอียด: [docs/03-docker.md](docs/03-docker.md),
[docs/04-traefik.md](docs/04-traefik.md), [docs/05-portainer.md](docs/05-portainer.md)

## 5. Database — PostgreSQL และ Redis

- [ ] PostgreSQL และ Redis `healthy` และไม่เปิด ports สู่ public network

```bash
docker compose --env-file .env -f docker/docker-compose.database.yml ps
```

- [ ] ใช้ database แยกต่อ application (`create-project.sh` สร้างให้เมื่อ postgres รันอยู่)

รายละเอียด: [docs/06-postgresql.md](docs/06-postgresql.md),
[docs/07-redis.md](docs/07-redis.md)

## 6. Monitoring และ n8n

- [ ] สร้างบัญชี owner ของ n8n, Uptime Kuma และ Beszel (`servers.`) **ทันที** — ใครเปิดก่อนได้เป็นเจ้าของ
- [ ] จด `BACKUP_ENCRYPTION_PASSWORD` และ `N8N_ENCRYPTION_KEY` ลง password manager (`infra secrets`)
- [ ] login Grafana ด้วย `GRAFANA_ADMIN_USER`/`GRAFANA_ADMIN_PASSWORD` และตรวจ Prometheus targets
- [ ] ตั้ง Uptime Kuma monitors และ notification channel
- [ ] ทดสอบ alert ด้วย service ทดลอง แล้วเปิด service กลับทันที
- [ ] ตรวจว่า token หรือ chat ID ไม่ถูก commit ใน tracked configuration

รายละเอียด: [docs/08-netdata.md](docs/08-netdata.md),
[docs/09-grafana.md](docs/09-grafana.md), [docs/10-uptime-kuma.md](docs/10-uptime-kuma.md),
[docs/14-monitoring.md](docs/14-monitoring.md), [docs/17-deploy-n8n.md](docs/17-deploy-n8n.md)

## 7. Backup — สำรองและซ้อมกู้คืน

- [ ] จด `BACKUP_ENCRYPTION_PASSWORD` (และ R2 key) เก็บใน password manager — ไม่มีรหัสนี้กู้ secrets ไม่ได้
- [ ] ตั้ง rclone remote `r2` + `R2_BUCKET_BACKUP` ใน `.env` ([docs/12-r2.md](docs/12-r2.md))
- [ ] รัน backup ทั้งชุด และตรวจว่าไฟล์ทั้ง 3 ประเภทมีขนาดมากกว่า 0 bytes และขึ้น R2 (`✅ ตรวจแล้ว`)

```bash
./scripts/backup.sh
ls -lh backup/archives/postgres/ backup/archives/volumes/ backup/archives/secrets/
```

- [ ] สร้าง log files ที่ cron เขียนได้ แล้วตั้ง cron รายวันตาม [docs/13-backup.md](docs/13-backup.md)
- [ ] ตั้ง Object lifecycle rule ของ bucket backup ใน R2 (เช่นลบไฟล์อายุเกิน 30 วัน)
- [ ] ซ้อมกู้ทั้งเครื่องลง VPS ทดลอง: `./scripts/restore-server.sh r2:<bucket>/<host>` และจดเวลา recovery

รายละเอียด: [docs/12-r2.md](docs/12-r2.md), [docs/13-backup.md](docs/13-backup.md)

## 8. Optional Services — เปิดเท่าที่ใช้

- [ ] เปิด tools stack เมื่อต้องใช้ pgAdmin หรือ Redis Insight
- [ ] เปิด messaging stack เมื่อต้องใช้ RabbitMQ
- [ ] เปิด storage stack เมื่อต้องใช้ MinIO
- [ ] ทบทวนสิทธิ์, DNS, authentication, backup และ monitoring ของทุก service ที่เปิดเพิ่ม

```bash
./scripts/check-dns.sh tools messaging storage   # เช็คเฉพาะ stack ที่จะเปิด
docker compose --env-file .env -f docker/docker-compose.tools.yml up -d
docker compose --env-file .env -f docker/docker-compose.messaging.yml up -d
docker compose --env-file .env -f docker/docker-compose.storage.yml up -d
```

ดูรายการ stack ที่ [docker/README.md](docker/README.md)

## 9. Deploy — เพิ่ม application แรก

- [ ] เตรียม application image หรือ Dockerfile พร้อม health endpoint
- [ ] สร้าง project จาก template ที่ตรงกับ application

```bash
./scripts/create-project.sh app <laravel|nextjs|n8n|ai-worker>
nano projects/app/.env
./scripts/deploy.sh app
```

- [ ] เพิ่ม DNS ก่อน deploy เพื่อหลีกเลี่ยง certificate issuance failure
- [ ] เปิด migration เฉพาะ application ที่ใช้ expand/contract migration ได้
- [ ] ตรวจ health endpoint, งานหลัก, queue/scheduler และ logs
- [ ] เพิ่ม application เข้า Uptime Kuma และทดสอบ rollback บน environment ทดลอง

รายละเอียด: [docs/25-zero-downtime.md](docs/25-zero-downtime.md),
[docs/26-new-project.md](docs/26-new-project.md)

## 10. Validation — ตรวจ Definition of Done

- [ ] Core, database และ monitoring containers อยู่ในสถานะ running/healthy
- [ ] HTTPS ใช้งานได้โดยไม่มี certificate warning
- [ ] PostgreSQL/Redis ไม่เข้าถึงได้จาก public internet
- [ ] Uptime และ resource alerts ส่งถึงผู้ดูแลจริง
- [ ] Backup ล่าสุดอ่านได้และ restore drill ผ่าน
- [ ] `git status --short` ไม่มี `.env`, keys, certificates, archives หรือ runtime data
- [ ] เก็บ rollback path และ provider-console recovery steps ไว้ใน runbook ส่วนตัว

```bash
docker ps
docker network ls
sudo ufw status verbose
git status --short
```

## 11. Maintenance — งานประจำหลังติดตั้ง

- [ ] ทุกสัปดาห์: ตรวจ disk, container restarts, backup age และ uptime
- [ ] ทุกเดือน: ซ้อม restore, ทบทวน alerts และอัปเดต security patches
- [ ] ก่อน update: อ่าน [CHANGELOG.md](CHANGELOG.md), ยืนยัน backup และ rollback path
- [ ] หลัง update/deploy: ตรวจ health, logs และ metrics ก่อนจบงาน
- [ ] บันทึกข้อมูลเฉพาะเครื่องใน runbook ส่วนตัวที่อยู่นอก repository นี้

อ้างอิงการดูแลต่อเนื่อง: [docs/14-monitoring.md](docs/14-monitoring.md),
[docs/18-scale.md](docs/18-scale.md), [docs/roadmap.md](docs/roadmap.md)
