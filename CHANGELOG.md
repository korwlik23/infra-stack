# Changelog

All notable changes to InfraStack are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/) and [SemVer](https://semver.org/).

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
เพิ่ม `DEPLOY_MIGRATE=1` ใน `.env` ของ automation-ai-seller-chat และ zennuaflow

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
