# Changelog

All notable changes to InfraStack are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/) and [SemVer](https://semver.org/).

## [Unreleased]

## [2.5.0] - 2026-10-31

### Added — seed ตอน deploy แบบถามก่อน
- `deploy.sh` หลัง migrate (project ที่มี `DEPLOY_MIGRATE=1`) เทียบ hash ของ `database/seeders/` ใน image ใหม่
  กับครั้งล่าสุด → ครั้งแรกหรือ seeder ใหม่/แก้ไข จะโชว์ไฟล์แล้วถาม `รัน db:seed ด้วยไหม? [y/N]`
  (`db:seed --force` เติมข้อมูล ไม่ล้าง DB) · ตอบ N = จำไว้ ไม่ถามซ้ำจนกว่าจะเปลี่ยน · auto-deploy
  (ไม่มีคนตอบ) ไม่ seed เอง แค่เตือนใน log · `--seed` / `--no-seed` รัน/ข้ามโดยไม่ถาม
- template Laravel / docs 15, 25, 26 / `create-project.sh` อธิบายว่า migrate + seed เกิดตอน deploy
  (ตอน create-project ยังไม่มีโค้ดและ image ให้รัน) และ seeder ต้องรันซ้ำได้

### Fixed
- `deploy.sh` build จาก `src/` ที่ copy มาเอง (ไม่ใช่ git clone) แทนการ `docker compose pull`
  ที่ล้มด้วย "pull access denied" (เจอตอน deploy laravel-starter บน VPS จริง)

## [2.4.0] - 2026-10-31

### Changed — ติดตั้งด้วยคำสั่งเดียว เข้าเครื่องครั้งเดียว
- ใหม่ `prepare.sh` (root, `curl … | bash`): ช่วง A — clone → `harden.sh` → ถาม "เริ่มติดตั้งต่อเลยไหม"
  แล้ว `su - deploy` รัน `install.sh` (ช่วง B) ให้ใน session เดียว ไม่ต้อง logout/login
- `harden.sh` ทำ user ให้เสร็จก่อนงานอื่น: ถามรหัส sudo ของ deploy + ให้วาง SSH public key
  (ถ้า login ด้วยรหัสผ่าน, ตรวจด้วย `ssh-keygen -l`) + ใส่ group `docker` ล่วงหน้า + ติด Docker;
  ข้อความยาวของ apt / Docker ลง `/var/log/infra-prepare.log` ล้มเมื่อไหร่โชว์ท้าย log
- `install.sh` รอบเดียวจบ: ถามโดเมน / อีเมล / ติดตั้ง n8n ไหม แทนการ `nano .env`; ไม่อยู่ใน group
  docker ของ session → รันตัวเองใหม่ผ่าน `sg docker` แทนการบอกให้ login ใหม่; เปิด Portainer,
  database, monitoring, n8n ก่อน แล้วโชว์ตาราง DNS ที่ต้องสร้าง รอ (`check-dns.sh --wait`) จนครบ
  ค่อยเปิด Traefik — DNS ไม่ต้องสร้างล่วงหน้าอีก และไม่โดน Let's Encrypt แบน; Ctrl+C = รอต่อเบื้องหลัง
  แล้วเปิด HTTPS เองเมื่อพร้อม; จบด้วยสรุป URL / รหัส / ของที่ต้องจด; อัตโนมัติไม่ถาม:
  `INFRA_DOMAIN=… INFRA_EMAIL=… [INFRA_N8N_DOMAIN=…] ./install.sh`
- Portainer: `install.sh` สร้าง admin ผ่าน API ทันทีด้วย `PORTAINER_ADMIN_PASSWORD` (ใหม่ใน `.env`)
  — ไม่ต้องแข่งกับเวลา 5 นาที
- `check-dns.sh` แสดงเป็นตาราง Type / Name / IPv4 / สถานะ, รับชื่อเต็ม (เว็บของ project), `--wait`,
  `--list`; ถาม 1.1.1.1 ผ่าน DNS-over-HTTPS ตรง ๆ (systemd-resolved จำ "ไม่มีชื่อนี้" ได้นานถึง 30 นาที)
- template n8n: `N8N_ENCRYPTION_KEY=__GENERATE__` — `create-project.sh` สุ่ม secret ให้ (token ใหม่)
- ใหม่ `infra status` (container + DNS + HTTPS) และ `infra secrets` (รหัสทั้งหมด) ที่ `/usr/local/bin/infra`
- `restore-server.sh` ตั้ง `SKIP_DNS_CHECK=1` — ระหว่างย้ายเครื่อง DNS ยังชี้เครื่องเดิม cert มาจาก acme.json
- docs: INSTALL.md เขียนใหม่ตาม flow คำสั่งเดียว (9 ขั้น), TROUBLESHOOTING แยกช่วง A / ช่วง B,
  README / GUIDE / TODO / docs 00, 02, 03, 05, 11, 13, 17 และ scripts/README ปรับตาม

**อัปเกรดเครื่องเดิม:** `git pull` แล้ว `./install.sh` — `.env` เดิมไม่ถูกถามซ้ำ, เติม
`PORTAINER_ADMIN_PASSWORD` / `INFRA_N8N_DOMAIN` ให้ (Portainer ที่มี admin อยู่แล้วไม่ถูกแตะ) และ
install.sh จะเปิด database + monitoring ด้วยถ้ายังไม่ได้เปิด

### Fixed — จากการติดตั้งจริงบน VPS ใหม่ (2026-10-31)
- `harden.sh` ไม่ล็อกตัวเองออกอีก: ถามรหัส sudo ของ `deploy` ให้เลย (ถ้ารันใน terminal) และ
  ปิด root login เฉพาะเมื่อ `deploy` มีรหัสแล้ว — ถ้าไม่มี (เช่นรันผ่าน ssh แบบไม่ interactive)
  root ยังเข้าได้ด้วย key เท่านั้นพร้อมคำเตือน เดิม root ถูกปิดทั้งที่ `deploy` sudo ไม่ได้ → ต้องแก้ผ่าน VNC
- `harden.sh` โอน repo ที่ clone ด้วย root ให้ `deploy` เอง (เฉพาะตอนยังเป็นของ root)
- `check-dns.sh` เช็คว่า record ชี้มา**เครื่องนี้** ไม่ใช่แค่มีชื่อ — ชี้ไป IP อื่นจะหยุดและบอก IP ที่เจอ
  (เดิม BASE_DOMAIN ซ้ำกับเครื่องเก่าแล้วผ่าน), Proxied ผ่าน Cloudflare เตือนให้ตรวจ IP ใน dashboard
  และข้อความ error ใส่ IP จริงของเครื่องแทน `<IP ของ VPS>`
- templates: comment `__ROOT:KEY__` ใน `.env.example` ทำให้ `create-project.sh` เตือน
  `ไม่มีค่าใน .env กลาง: KEY` ทุกครั้ง → เปลี่ยนเป็น `__ROOT:<ชื่อค่า>__`

### Added — คู่มือสำหรับมือใหม่
- `docs/INSTALL.md` คู่มือติดตั้งทีละขั้นตั้งแต่เช่า VPS, ย้ายโดเมนเข้า Cloudflare, เปิด terminal,
  ทำ SSH key (Windows + Mac), ใช้ nano จนเปิดหน้าแอดมินครบ — ทุกขั้นบอกว่าสำเร็จแล้วจะเห็นอะไร
- `docs/TROUBLESHOOTING.md` รวมอาการที่เจอบ่อยตามลำดับขั้นติดตั้ง พร้อมวิธีแก้และวิธีกู้รหัสผ่าน
- README / GUIDE / TODO / docs/00 ชี้มาที่ INSTALL.md เป็นจุดเริ่มต้นเดียว; docs/11 แนะนำ
  เมฆเทาตอนขอ cert ครั้งแรก

### Fixed — จุดที่ทำให้ติดตั้งบนเครื่องใหม่ล้ม
- watchtower: `DOCKER_API_VERSION` 1.40 → 1.44 (Docker 29 รับขั้นต่ำ 1.44 — 1.40 restart loop)
- postgres: network `backend` เป็น `external` เหมือน service อื่น (สร้างโดย install.sh)
- `install.sh` หยุดถ้า `BASE_DOMAIN` / `ACME_EMAIL` ยังเป็น example.com และเตือนรหัสผ่าน
  `CHANGE_ME` ที่ต้องตั้งก่อน start database stack ครั้งแรก
- `create-project.sh` สร้าง database ของ project (`DB_DATABASE`) ให้อัตโนมัติถ้า postgres
  รันอยู่ — เดิม deploy แรกล้มที่ migrate "database does not exist"
- README quick start ขั้นที่ 5 ใช้ `deploy.sh` แทน `docker compose up -d` ตรง ๆ

### Fixed — installer / hardening
- `install.sh` ตอนยังไม่มี `.env`: สร้างจาก example (chmod 600) แล้ว**หยุด**ให้แก้และรันซ้ำ
  — เดิมรอ Enter ซึ่งแก้ไฟล์ใน terminal เดียวกันไม่ได้
- `harden.sh` รันซ้ำได้จริง: copy key ของ root ให้ deploy เมื่อ deploy ยังไม่มี key
  (เดิม copy เฉพาะตอนสร้าง user → เพิ่ม key ทีหลังแล้วรันซ้ำ ก็ยังข้ามการปิด password login)
- `harden.sh` เขียน `sshd_config.d/00-infra-hardening.conf` กัน `50-cloud-init.conf`
  (`PasswordAuthentication yes`) ชนะค่าที่แก้ใน `sshd_config` + `sshd -t` ก่อน restart
- `harden.sh` ติดตั้ง `apache2-utils` (`htpasswd`) สำหรับสร้าง basicauth hash

### Fixed — Redis / backup
- redis.conf: `maxmemory-policy allkeys-lru` → `volatile-lru` — เดิม RAM เต็มแล้ว job ใน
  queue (ไม่มี TTL) ถูกลบเงียบ ๆ ได้ เครื่องเดิม: `git pull` แล้ว `docker restart redis`
- backup scripts เลิก `source .env` — อ่านทีละ key แทน (รหัสผ่านที่มี `$` ช่องว่าง `&`
  ทำ cron backup ล้มด้วย unbound variable); `volumes-backup.sh` อ่าน `BACKUP_KEEP_DAYS` จาก `.env` ด้วย

### Fixed — rollback ค้าง tag `:previous`
- `rollback.sh` retag image เป้าหมายเป็น `APP_IMAGE` แทนการแก้ `.env` — เดิม `.env`
  ค้าง `APP_IMAGE=…:previous`: deploy ถัดไป (build) เขียนทับ `:previous` จน image ดีหาย
  และโหมด registry `pull …:previous` ล้ม; และไม่ `docker compose pull` (ดึง :latest ตัวพังกลับมา)
- เครื่องที่เคย rollback ด้วยเวอร์ชันเก่า: แก้ `APP_IMAGE` ใน `projects/<name>/.env` กลับเป็น tag เดิม

### Docs — เอกสารให้ตรงกับโค้ด
- ลำดับติดตั้งเดียวกันทุกที่ (README / GUIDE / TODO): SSH key + DNS ก่อน → clone ลง
  `/opt/infra-stack` → harden (root) → `.env` + `install.sh` ด้วย user deploy
- docs/11 ตาราง DNS ต่อ stack (เดิมขาด `traefik`, `servers` ฯลฯ → ACME ล้ม/rate limit)
- deploy docs: สร้าง `APP_KEY` ด้วย openssl (ก่อน deploy ยังไม่มี container ให้ artisan),
  ต้องตั้ง `APP_IMAGE`, clone ผ่าน deploy-key host alias, ใช้ `deploy.sh` ครั้งแรก,
  เลิกสั่ง `CREATE DATABASE` ซ้ำกับ create-project, ชื่อ volume n8n จริง `<p>_<p>_data`
- README ของ service สั่งผ่านไฟล์ stack (เดิม `cd services/x && up` ชนชื่อ container),
  แก้ชื่อ volume `postgres_data` / `portainer_data`, beszel-agent ผ่าน monitoring stack

### Changed — Traefik static config ย้ายเข้า compose `command:`
- ลบ `services/traefik/traefik.yml` — ACME email อ่านจาก `ACME_EMAIL` ใน `.env` ผ่าน CLI flag
- `install.sh` เลิก `sed` แก้ไฟล์ที่อยู่ใน Git (เดิมทำให้ `git status` ไม่ clean และ
  `git checkout -- traefik.yml` ก่อน pull ทำ email กลับเป็น example.com)

### Changed — แยก compose project ต่อ stack + pin ชื่อ volume
- ทุก stack มี project ของตัวเอง (`infra-core`, `infra-database`, `infra-monitoring`,
  `infra-tools`, `infra-messaging`, `infra-storage`) — เลิก WARN orphan ข้าม stack
  และ `--remove-orphans` ของ stack หนึ่งไม่ลบ container ของ stack อื่นอีกต่อไป
- named volume ทั้ง 17 ตัว pin ชื่อเป็น `<name>` (เดิม `docker_<name>`)
- postgres-exporter แยก user/pass ออกจาก DSN — รหัสผ่านที่มี `@ : / # ?` ไม่ทำ DSN พัง

### Changed — ติดตั้งได้เองโดยไม่ต้องมีพื้นฐาน
- `install.sh` สุ่มรหัสให้ทุก `*_PASSWORD=CHANGE_ME` ใน `.env` (hex 48 ตัว — ใส่ใน URL/DSN ได้)
  ข้ามตัวที่ data volume มีอยู่แล้ว (postgres/grafana/pgadmin/rabbitmq จำรหัสตอน init ครั้งแรก)
  — มือใหม่แก้ `.env` แค่ `BASE_DOMAIN` + `ACME_EMAIL` และไม่มีทาง start database ด้วย `CHANGE_ME`
- basicauth กลาง `dashboard-auth@file` สำหรับ Traefik dashboard / Netdata / Dozzle / Redis Insight:
  `install.sh` สร้าง `services/traefik/dynamic/auth.yml` (gitignored) จาก `DASHBOARD_USER` /
  `DASHBOARD_PASSWORD` ใน `.env` — เลิกให้คนรัน `htpasswd` แล้วแก้ compose + escape `$`→`$$` เอง
  (และ compose ไม่ถูกแก้บนเครื่องอีก → `git pull` ไม่ชน)
- `scripts/check-dns.sh <stack…>` (ใหม่): อ่าน `Host(…)` จาก compose ของ stack แล้วเช็คว่าทุก
  subdomain resolve ได้ — `install.sh` เช็ค core ก่อน start, ขาดตัวไหนหยุดและบอกวิธีสร้าง record
  (กัน ACME ล้มซ้ำจน Let's Encrypt แบน ~1 ชม.) ข้ามได้ด้วย `SKIP_DNS_CHECK=1`
- `harden.sh` รัน apt แบบ non-interactive (`DEBIAN_FRONTEND=noninteractive`, `NEEDRESTART_MODE=a`,
  `--force-confold`) — เลิกหน้าจอม่วงของ needrestart / dpkg conffile ที่ค้างกลางทาง
- เอกสารบอกเวลารอ DNS (ย้าย nameserver ไป Cloudflare อาจหลายชั่วโมง) แยกจาก "10–15 นาที"

### Changed — Backup / Disaster Recovery กู้ทั้งเครื่องได้จริง
- `volumes-backup.sh` backup **ทุก** named volume ในเครื่องแทนรายการตายตัว 4 ตัว (เดิมขาด minio,
  rabbitmq, beszel, pgadmin, volume ของ project เช่น n8n) — ข้าม `postgres_data` (ใช้ `pg_dumpall`),
  `docker_*`, volume ไม่มีชื่อ และ `BACKUP_EXCLUDE_VOLUMES` (default: metrics/log history)
- `secrets-backup.sh` (ใหม่): `.env`, `projects/*` (ยกเว้น src/data), `acme.json`, alertmanager token,
  deploy keys, crontab → gpg AES256 ด้วย `BACKUP_ENCRYPTION_PASSWORD` (install.sh สุ่มให้ + เตือนให้จด)
  — เดิมไม่มีการ backup secrets เลย: restore ข้อมูลได้แต่ไม่มีรหัสผ่าน/cert
- `offsite.sh` (ใหม่): ทุกไฟล์ขึ้น `r2:<bucket>/<BACKUP_HOST>/<kind>/` + ตรวจขนาดหลัง upload,
  เตือนดังเมื่อยังไม่ตั้ง — เดิมมีแค่ postgres ขึ้น R2 (volume อยู่บนดิสก์เดียวกับเครื่อง) และไม่ตรวจผล
- `scripts/backup.sh` รันทั้ง 3 ส่วนต่อกันแม้ส่วนแรกล้ม แล้ว exit 1 พร้อมบอกส่วนที่ล้ม; cron เหลือบรรทัดเดียว
- `postgres-restore.sh`: ตรวจ gzip ก่อน, แยก "already exists" ที่ปกติออก แล้ว **ล้มเมื่อมี error จริง**
  (เดิมจบ "done" เสมอ) — เก็บ log ข้างไฟล์ backup; เพิ่ม `--yes`
- `volumes-restore.sh`, `secrets-restore.sh` (ใหม่) — ไม่ทับ volume ที่มีข้อมูล / `.env` เดิมเก็บเป็น
  `.env.before-restore-*` / ไม่ทับ `~/.ssh` ที่มีอยู่
- `scripts/restore-server.sh` (ใหม่): กู้ทั้งเครื่องลง VPS ใหม่จาก R2 หรือโฟลเดอร์ local —
  secrets → volumes → core → database + PostgreSQL → stack ที่เครื่องเดิมเปิดไว้ แล้วบอกขั้น
  deploy project + ทดสอบด้วย `curl --resolve` ก่อนย้าย DNS (cert เดิมจาก acme.json ใช้ได้ทันที)
- `harden.sh` ติดตั้ง `gnupg`

### ⚠️ Upgrade notes — เครื่องที่ติดตั้งก่อนเวอร์ชันนี้ (ทำครั้งเดียว)
container เดิมอยู่ใต้ project `docker` และ volume ชื่อ `docker_<name>` — ถ้า up เลยจะชน
ชื่อ container หรือได้ volume ใหม่ที่ว่างเปล่า ให้รัน `./scripts/migrate-volumes.sh`
(ใหม่) ก่อน up stack — ขั้นตอนเต็มใน `docker/README.md`

basicauth: hash ที่เคยแก้เองใน compose ของ traefik/netdata/dozzle/redisinsight ถูกแทนด้วย
`DASHBOARD_PASSWORD` ใน `.env` (รหัสเดียวทุกหน้า) — `git checkout --` 4 ไฟล์นั้นก่อน `git pull`
แล้วรัน `./install.sh` (เติม `DASHBOARD_*` ลง `.env` + สุ่มรหัสให้ถ้ายังไม่มี)

## [2.3.0] - 2026-07-13

### Added — ดึงค่าจาก .env กลางเข้า project อัตโนมัติ (ลดพิมพ์ซ้ำ + typo)
- `create-project.sh` แทนที่ token `__ROOT:KEY__` ใน project `.env` ด้วยค่าจาก
  `.env` กลางตอนสร้าง (DB/Redis/domain/TZ/R2) — key ที่ไม่มี → CHANGE_ME + เตือน
- template ทุกตัว (laravel/nextjs/n8n/ai-worker) ใช้ `__ROOT:` แทน CHANGE_ME
  ในค่าที่ share กัน; ปล่อยว่างเฉพาะค่า per-project (APP_KEY, encryption key, API key)
- laravel template เพิ่ม `REDIS_CLIENT=predis` เป็น default

### Implementation note (บั๊กที่กันได้ตอนเทสต์)
แทนที่ค่าด้วย bash `${//}` + `shopt -u patsub_replacement` (bash 5.2 ตีความ `&`
เป็น match เหมือน sed) — รองรับรหัสผ่านที่มี `& | \ =` แบบ byte-exact
(sed escape เชื่อถือไม่ได้, nested-regex loop ค้าง — เลี่ยงทั้งคู่)

## [2.2.0] - 2026-07-12

### Added — auto-migrate + rollback (post-mortem จากเว็บดับหลัง push)
- `deploy.sh` รัน `php artisan migrate --force` ก่อน rollout อัตโนมัติเมื่อ
  project มี `DEPLOY_MIGRATE=1` (รันด้วย image ใหม่บน container ชั่วคราว)
- `deploy.sh` tag image ปัจจุบันเป็น `:previous` ก่อน build ใหม่ →
  `rollback.sh <project> previous` ใช้ได้เสมอ (ก่อนหน้านี้ prune ลบ image เก่าทิ้ง)
- template Laravel `.env.example` เพิ่ม `DEPLOY_MIGRATE=1`
- docs/25: post-mortem, ข้อจำกัด healthcheck /up, วิธี health route ที่แตะ DB

### Root cause ที่แก้
push โค้ดที่มี migration ใหม่ → auto-deploy build+deploy โค้ดใหม่ แต่ schema เก่า
→ app คืน 500; healthcheck `/up` ตอบ 200 (เช็คแค่ boot ไม่เช็ค DB) → rolling deploy
คิดว่าสำเร็จ เว็บดับจน migrate มือ

### ต้องทำบน server สำหรับ project เดิม
เพิ่ม `DEPLOY_MIGRATE=1` ใน `.env` ของ Laravel deployments ที่ต้องรัน migration

## [2.1.2] - 2026-07-07

### Fixed — จากการ deploy Laravel จริงครั้งแรก
- ตัวเช็ค docker-rollout ใช้ `docker rollout --help` ซึ่ง exit 0 แม้ไม่มี plugin
  (Docker 29 พิมพ์ help รวม) → install/deploy/rollback เช็คไฟล์ plugin ตรง ๆ แทน
- pgAdmin: Traefik ชี้ port 80 แต่ pgAdmin ย้ายตัวเองไป 8080 เพราะ
  no-new-privileges → แก้ label เป็น 8080
- redis.conf: เลิกปิด FLUSHDB — Laravel `cache:clear`/`optimize:clear` ต้องใช้
  (FLUSHALL/CONFIG ยังปิดอยู่)
- docs/13, 19, TODO: cron ต้อง `sudo touch/chown` ไฟล์ log ใน /var/log ก่อน
  ไม่งั้น cron ล้มเงียบเพราะ deploy เขียนไฟล์ใหม่ใน /var/log ไม่ได้
- docs/13: อธิบาย "already exists" ตอน restore = ปกติ
- docs/15: troubleshooting — Class "Redis" not found (phpredis/predis),
  FLUSHDB, และวิธีย้ายเว็บด้วย temp domain กัน Let's Encrypt rate limit
- docs/04: NXDOMAIN cert spam จาก router ที่ไม่มี DNS record + ทางแก้

### Added
- `scripts/artisan.sh <project> <args>` — รัน artisan จากที่ไหนก็ได้
  (แทน alias ที่หายทุกครั้งที่ ssh ใหม่)

## [2.1.1] - 2026-07-04

### Fixed — จากการติดตั้งจริงครั้งแรก (fresh-install จะไม่เจอปัญหาพวกนี้แล้ว)
- `alertmanager.yml` default เปลี่ยนเป็น receiver "none" ที่ start ผ่านทันที
  (เดิมเป็น CHANGE_ME/chat_id 0 → restart loop แกะกล่อง) — Telegram เป็นบล็อกคอมเมนต์
- `beszel-agent` คอมเมนต์ไว้ default (เดิม start โดยไม่มี KEY → restart loop)
- `install.sh` sync `ACME_EMAIL` จาก .env เข้า `traefik.yml` อัตโนมัติ
  (Let's Encrypt ปฏิเสธ @example.com — ลืมแก้ = ไม่มี cert ทั้งเครื่อง)
- เพิ่ม `.gitattributes` บังคับ LF — กัน Windows checkout ทำ script พังบน Linux
- `docker/README.md`: คำเตือน --remove-orphans + วิธี git pull บนเซิร์ฟเวอร์
- `docs/05`: วิธีหา Portainer setup token จาก log

## [2.1.0] - 2026-07-04

### Added — Zero-Downtime Deployment
- `scripts/deploy.sh`: rolling deploy ด้วย `docker rollout` — เปิด container ใหม่
  รอ healthcheck ผ่านก่อนถอดตัวเก่า; ตัวใหม่พัง = deploy ล้มเฉย ๆ เว็บไม่ดับ
- `scripts/rollback.sh <project> <tag>`: กลับ image tag เก่าแบบ rolling (มี confirmation)
- `install.sh`: ติดตั้ง docker-rollout plugin อัตโนมัติ
- Templates laravel/nextjs: เอา `container_name` ออกจาก service ที่รับ traffic,
  เพิ่ม Docker healthcheck + Traefik healthcheck labels,
  เพิ่ม `ROLLOUT_SERVICE` / `HEALTHCHECK_PATH` ใน .env.example
- `docs/25-zero-downtime.md`: rolling deploy, expand/contract migration, rollback,
  ข้อยกเว้น (n8n/queue/worker), วิธีทดสอบ

### Changed
- `deploy.sh` เลิก restart queue/scheduler ด้วยชื่อ container —
  ใช้ compose recreate ตาม image ที่เปลี่ยนแทน
- docs/15, 16, 19 อัปเดตคำสั่งเป็น `docker compose exec/logs`

## [2.0.0] - 2026-07-04

### Added — Database Tools
- pgAdmin 4 (`services/pgadmin/`) — PostgreSQL UI ผ่าน browser
- Redis Insight (`services/redisinsight/`) — Redis UI (basicauth ผ่าน Traefik)
- Stack ใหม่: `docker/docker-compose.tools.yml`

### Added — Monitoring เต็มระบบ
- postgres-exporter + redis-exporter → Grafana dashboards 9628 / 11835
- Alertmanager → Telegram (`services/alertmanager/`) + Prometheus alerting config
- Loki + Promtail (`services/loki/`) — log aggregation, เลือกแทน ELK
  เพราะกิน RAM น้อยกว่า ~20 เท่า เหมาะเครื่อง 8GB
- Beszel hub + agent (`services/beszel/`) — multi-server monitoring
- Grafana: provision datasource Loki อัตโนมัติ

### Added — v2.0 Platform
- RabbitMQ 3 (`services/rabbitmq/` + `docker-compose.messaging.yml`)
- MinIO self-hosted S3 (`services/minio/` + `docker-compose.storage.yml`)
- AI Worker template (`templates/ai-worker/`) — queue consumer + resource limits

### Added — CI/CD ไม่ใช้ GitHub Actions (ฟรี)
- `scripts/deploy.sh <project>` — build-on-server (มี `src/`) หรือ pull image
- `scripts/auto-deploy.sh` — cron git poll ทุก project → deploy อัตโนมัติ
- Templates laravel/nextjs: เพิ่ม option `build: ./src` (commented)
- `.gitignore`: `projects/**/src/`

### Added — Documentation
- `docs/19-cicd.md` … `docs/24-ai-worker.md`

## [1.0.0] - 2026-07-04

### Added
- Modular service stack: Traefik, Portainer, PostgreSQL 16, Redis 7,
  Netdata, Prometheus, Grafana, Uptime Kuma, Dozzle, Watchtower
- Stack aggregation files: `docker/docker-compose.{core,database,monitoring}.yml`
- Bootstrap scripts: `install.sh`, `scripts/harden.sh`
- Automation: `scripts/{update,backup,restore,create-project}.sh`
- Backup scripts for PostgreSQL and Docker volumes (`backup/scripts/`)
- Project templates: Laravel, Next.js, n8n (`templates/`)
- Environment examples: production / staging / development
- Documentation: `docs/00-introduction.md` … `docs/18-scale.md`,
  plus `architecture.md`, `requirements.md`, `roadmap.md`

### Planned (future versions)
- RabbitMQ, MinIO, ELK stack, AI Worker (v2.x)
- Multi-server monitoring (Beszel)
- Kubernetes migration path (Stage 4)
