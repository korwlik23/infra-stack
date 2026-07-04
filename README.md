# InfraStack

Production Infrastructure Stack — v2.1.0

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
- Full documentation under `docs/` (00–25)

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

- Repository ควรเป็น **Private** ถ้าใช้กับเซิร์ฟเวอร์จริง
- **ห้าม commit**: `.env`, SSH keys, API tokens, certificates — ดู `.gitignore`
- Commit ได้เฉพาะ `.env.example` ที่ใช้ค่า `CHANGE_ME`

## Documentation

Start at [docs/00-introduction.md](docs/00-introduction.md).
Architecture details in [docs/architecture.md](docs/architecture.md),
requirements in [docs/requirements.md](docs/requirements.md),
roadmap in [docs/roadmap.md](docs/roadmap.md).

## Versioning

Infrastructure is versioned like software — see [CHANGELOG.md](CHANGELOG.md).
Current: **v2.1.0** — zero-downtime rolling deployment + rollback, on top of
v2.0 (RabbitMQ, MinIO, Loki, Alertmanager→Telegram, Beszel, AI Worker,
CI/CD without GitHub Actions).
