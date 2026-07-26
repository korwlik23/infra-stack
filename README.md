# InfraStack

Production Infrastructure Stack — v2.3.0

## Goal

Build reusable production infrastructure for deploying Laravel, Next.js, n8n
and other services using Docker. Clone this repository on any fresh Ubuntu VPS
(Contabo, GreenCloud, Hetzner, Oracle Cloud, …), run one script, and get a
standardized server in 10–15 minutes.

```bash
git clone https://github.com/korwlik23/infra-stack.git
cd infra-stack
./install.sh
```

## Architecture

```text
                    Cloudflare
                         │
                         ▼
                     Traefik ──────────── HTTPS / Reverse Proxy
                         │
        ┌────────────────┼────────────────┐
        ▼                ▼                ▼
     Laravel          Next.js            n8n
        │
        ├──────────────┐
        ▼              ▼
    PostgreSQL       Redis
        │
        ▼
  Cloudflare R2 ──── Object Storage / Backup
```

Three layers:

| Layer | Contents |
|-------|----------|
| **Infrastructure** | Ubuntu, Docker, Traefik, PostgreSQL, Redis, Cloudflare, R2, MinIO |
| **Platform** | Portainer, Netdata, Grafana, Prometheus, Alertmanager, Loki, Uptime Kuma, Dozzle, Watchtower, Beszel, pgAdmin, Redis Insight, RabbitMQ, Backup, CI/CD |
| **Application** | Laravel, Next.js, n8n, AI Workers and every project under `projects/` |

## Features

- Docker + Docker Compose (modular — one compose file per service)
- Traefik (HTTPS, reverse proxy, automatic Let's Encrypt)
- Portainer (Docker management UI) + pgAdmin + Redis Insight
- PostgreSQL 16 + Redis 7 (+ postgres/redis exporters)
- Netdata, Grafana, Prometheus, Alertmanager→Telegram, Uptime Kuma (monitoring)
- Loki + Promtail (ค้น log ย้อนหลัง) + Dozzle (log สด)
- Beszel (multi-server monitoring) + Watchtower (auto image updates)
- RabbitMQ (message queue) + MinIO (self-hosted S3) — v2.0
- Backup & restore scripts (PostgreSQL + Docker volumes → R2)
- CI/CD ฟรีไม่ใช้ GitHub Actions — build-on-server + auto-deploy (cron git poll)
- **Zero-downtime deployment** — rolling deploy + healthcheck gate + `rollback.sh`
- Project templates (Laravel, Next.js, n8n, AI Worker) + `create-project.sh`
- Full documentation under `docs/` (00–26)

## Repository Structure

```text
infra-stack/
├── docs/            # คู่มือทั้งหมด (00-introduction … 18-scale)
├── docker/          # Stack aggregation (core / database / monitoring)
├── services/        # หนึ่ง service = หนึ่งโฟลเดอร์ = หนึ่ง docker-compose.yml
├── monitoring/      # Prometheus config, alerts, Grafana dashboards
├── backup/          # Backup & restore scripts
├── scripts/         # Automation (install, update, create-project, …)
├── templates/       # Project templates (laravel / nextjs / n8n)
├── environments/    # production / staging / development env examples
└── projects/        # Deployed projects (each independent, never committed secrets)
```

## Quick Start

```bash
# 1. Bootstrap a fresh Ubuntu server (security + Docker)
sudo ./scripts/harden.sh
./install.sh

# 2. Bring up the core stack (Traefik + Portainer)
docker compose --env-file .env -f docker/docker-compose.core.yml up -d

# 3. Databases
docker compose --env-file .env -f docker/docker-compose.database.yml up -d

# 4. Monitoring
docker compose --env-file .env -f docker/docker-compose.monitoring.yml up -d

# 5. Create a project from a template
./scripts/create-project.sh myapp laravel
cd projects/myapp && docker compose up -d

# Optional stacks (v2.0)
docker compose --env-file .env -f docker/docker-compose.tools.yml up -d      # pgAdmin, Redis Insight
docker compose --env-file .env -f docker/docker-compose.messaging.yml up -d  # RabbitMQ
docker compose --env-file .env -f docker/docker-compose.storage.yml up -d    # MinIO
```

## Security Rules

- Repository นี้เปิดเผย reusable code ได้ แต่ deployment configuration และ operator
  runbooks ต้องเก็บเป็น private
- **ห้าม commit**: `.env`, SSH keys, API tokens, certificates, backup archives หรือ
  runtime data — ดู `.gitignore`
- Commit ได้เฉพาะ `.env.example` ที่ใช้ dummy values เช่น `CHANGE_ME`
- ใช้ [TODO.md](TODO.md) เป็น installation checklist และเก็บข้อมูลเฉพาะเครื่องไว้นอก
  repository

## Documentation

**มือใหม่ / ได้ repo นี้มาแล้วงง เริ่มที่ [GUIDE.md](GUIDE.md)** — อธิบายว่าแต่ละตัวคืออะไร
ใช้ยังไง ทำอะไรได้บ้าง แบบไม่ต้องมีพื้นฐาน

Start at [docs/00-introduction.md](docs/00-introduction.md).
Architecture details in [docs/architecture.md](docs/architecture.md),
requirements in [docs/requirements.md](docs/requirements.md),
roadmap in [docs/roadmap.md](docs/roadmap.md).
Installation checklist in [TODO.md](TODO.md).

## Versioning

Infrastructure is versioned like software — see [CHANGELOG.md](CHANGELOG.md).
Current: **v2.3.0** — project `.env` auto-fill from shared root configuration, on top
of v2.2 auto-migration/rollback and the v2.0 service expansion.

## License

[MIT](LICENSE)
