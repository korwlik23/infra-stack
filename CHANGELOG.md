# Changelog

All notable changes to InfraStack are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/) and [SemVer](https://semver.org/).

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
