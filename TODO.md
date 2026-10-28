# InfraStack Installation Checklist

ใช้ checklist นี้กับ Ubuntu VPS เครื่องใหม่หนึ่งเครื่อง งานทั้งหมดเริ่มเป็นสถานะยังไม่ทำ
และต้องตรวจผลจริงก่อนติ๊กเสร็จ อ่านภาพรวมที่ [GUIDE.md](GUIDE.md) และลำดับคู่มือที่
[docs/00-introduction.md](docs/00-introduction.md)

> เก็บ `.env`, private keys, certificates, backup archives และข้อมูล runtime ไว้นอก
> Git เสมอ ตัวอย่างใน repository ใช้ค่าจำลองเท่านั้น

## 1. Prerequisites — เตรียมเครื่องและสิทธิ์เข้าถึง

- [ ] เตรียม Ubuntu VPS ที่เข้าผ่าน SSH หรือ provider console ได้
- [ ] สร้าง SSH key บนเครื่องผู้ดูแลและสำรอง private key ในที่ปลอดภัย
- [ ] เพิ่ม public key ให้ `root` แล้วเปิด terminal ใหม่ทดสอบว่าเข้าได้จริง
- [ ] เตรียม domain และสิทธิ์แก้ DNS; เปิด inbound เฉพาะ SSH, HTTP และ HTTPS
- [ ] สร้าง DNS A record ของทุก subdomain ที่จะเปิด → IP เครื่อง **ก่อนรัน `install.sh`**
      (core: `traefik`, `portainer` — installer start ให้ทันที; รายการต่อ stack ดู
      [docs/11-cloudflare.md](docs/11-cloudflare.md)) ไม่งั้น ACME ล้มซ้ำจนโดน rate limit
- [ ] ติดตั้ง Git แล้ว clone repository ลง `/opt/infra-stack`

```bash
apt update && apt install -y git
git clone https://github.com/korwlik23/infra-stack.git /opt/infra-stack
cd /opt/infra-stack
```

รายละเอียด: [docs/01-server-setup.md](docs/01-server-setup.md)

## 2. Security — Harden server ก่อนเปิดบริการ

- [ ] อ่านคำเตือนเรื่อง SSH key และ lockout ใน [docs/02-security.md](docs/02-security.md)
- [ ] รัน hardening script จาก session ที่ยังเปิด provider console สำรองไว้ได้

```bash
cd /opt/infra-stack
sudo ./scripts/harden.sh
```

- [ ] ตั้งรหัสสำหรับ `sudo` ของ user `deploy` และโอน ownership ของ repository

```bash
sudo passwd deploy
sudo chown -R deploy:deploy /opt/infra-stack
```

- [ ] เปิด terminal ใหม่ทดสอบ `ssh deploy@<server-ip>` ก่อนปิด session เดิม
- [ ] ยืนยันว่า root login และ password login ถูกปิดตามนโยบายที่เลือก
- [ ] ตรวจ UFW และ Fail2ban

```bash
sudo ufw status verbose
sudo fail2ban-client status sshd
```

## 3. Configuration — ตั้งค่าที่ไม่อยู่ใน Git

- [ ] Login ใหม่เป็น `deploy` แล้วสร้าง `.env` จากตัวอย่าง

```bash
cd /opt/infra-stack
cp .env.example .env
chmod 600 .env
nano .env
```

- [ ] เปลี่ยน `BASE_DOMAIN`, `ACME_EMAIL` และทุกค่า `CHANGE_ME`
- [ ] สร้างรหัสผ่านแต่ละระบบแยกกัน เช่น `openssl rand -hex 32`
- [ ] ตั้งค่า R2 เฉพาะเมื่อพร้อมใช้ offsite backup; อย่าใส่ secret ลงไฟล์ตัวอย่าง
- [ ] ตั้ง basicauth ของ Traefik dashboard, Netdata และ Dozzle (placeholder เดิม login ไม่ได้)
      — `htpasswd -nb admin '<password>'` แล้วแทน `$` เป็น `$$` ในไฟล์ compose ([docs/04-traefik.md](docs/04-traefik.md))
- [ ] ตรวจว่า `.env` ถูก ignore และไม่มี secret ถูก stage

```bash
git check-ignore -v .env
git status --short
```

## 4. Core — Docker, networks, Traefik และ Portainer

- [ ] รัน installer; ถ้าเพิ่ม user เข้า group `docker` ให้ logout/login แล้วรันซ้ำ

```bash
cd /opt/infra-stack
./install.sh
```

- [ ] ตรวจ Docker, Compose, shared networks และ core containers

```bash
docker --version
docker compose version
docker network ls | grep -E 'proxy|backend|monitoring'
docker compose --env-file .env -f docker/docker-compose.core.yml ps
```

- [ ] ตรวจว่า Traefik ออก TLS certificate สำเร็จ (`docker logs traefik --tail 50 | grep -i acme`)
- [ ] สร้างบัญชี Portainer ครั้งแรก**ภายใน 5 นาที**หลัง start และใช้รหัสผ่านเฉพาะระบบ

รายละเอียด: [docs/03-docker.md](docs/03-docker.md),
[docs/04-traefik.md](docs/04-traefik.md), [docs/05-portainer.md](docs/05-portainer.md)

## 5. Database — PostgreSQL และ Redis

- [ ] Start database stack

```bash
docker compose --env-file .env -f docker/docker-compose.database.yml up -d
docker compose --env-file .env -f docker/docker-compose.database.yml ps
```

- [ ] ยืนยันว่า PostgreSQL และ Redis healthy และไม่เปิด ports สู่ public network
- [ ] ใช้ database แยกต่อ application (`create-project.sh` สร้างให้เมื่อ postgres รันอยู่)

รายละเอียด: [docs/06-postgresql.md](docs/06-postgresql.md),
[docs/07-redis.md](docs/07-redis.md)

## 6. Monitoring — Metrics, logs และ uptime

- [ ] Start monitoring stack

```bash
docker compose --env-file .env -f docker/docker-compose.monitoring.yml up -d
docker compose --env-file .env -f docker/docker-compose.monitoring.yml ps
```

- [ ] login Grafana ด้วย `GRAFANA_ADMIN_USER`/`GRAFANA_ADMIN_PASSWORD` จาก `.env` และตรวจ Prometheus targets
- [ ] สร้าง DNS `servers.` ไว้แล้ว (Beszel hub อยู่ใน monitoring stack)
- [ ] สร้าง Uptime Kuma owner account, monitors และ notification channel
- [ ] ทดสอบ alert ด้วย service ทดลอง แล้วเปิด service กลับทันที
- [ ] ตรวจว่า token หรือ chat ID ไม่ถูก commit ใน tracked configuration

รายละเอียด: [docs/08-netdata.md](docs/08-netdata.md),
[docs/09-grafana.md](docs/09-grafana.md), [docs/10-uptime-kuma.md](docs/10-uptime-kuma.md),
[docs/14-monitoring.md](docs/14-monitoring.md)

## 7. Backup — สำรองและซ้อมกู้คืน

- [ ] รัน PostgreSQL backup และตรวจว่า archive มีขนาดมากกว่า 0 bytes

```bash
./backup/scripts/postgres-backup.sh
ls -lh backup/archives/postgres/
```

- [ ] รัน volume backup และตรวจผลลัพธ์
- [ ] สร้าง log files ที่ cron เขียนได้ แล้วตั้ง daily/weekly schedules ตามคู่มือ
- [ ] ตั้ง offsite copy เช่น Cloudflare R2 และตรวจว่าไฟล์ปลายทางเปิดอ่านได้
- [ ] ซ้อม restore ด้วยข้อมูลทดสอบก่อนใช้ production และจดเวลา recovery

รายละเอียด: [docs/12-r2.md](docs/12-r2.md), [docs/13-backup.md](docs/13-backup.md)

## 8. Optional Services — เปิดเท่าที่ใช้

- [ ] เปิด tools stack เมื่อต้องใช้ pgAdmin หรือ Redis Insight
- [ ] เปิด messaging stack เมื่อต้องใช้ RabbitMQ
- [ ] เปิด storage stack เมื่อต้องใช้ MinIO
- [ ] ทบทวนสิทธิ์, DNS, authentication, backup และ monitoring ของทุก service ที่เปิดเพิ่ม

```bash
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
