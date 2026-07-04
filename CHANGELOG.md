# Changelog

All notable changes to InfraStack are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/) and [SemVer](https://semver.org/).

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
