# InfraStack

Production Infrastructure Stack — v2.5.1

## Goal

Build reusable production infrastructure for deploying Laravel, Next.js, n8n
and other services using Docker. Clone this repository on any fresh Ubuntu VPS
(Contabo, GreenCloud, Hetzner, Oracle Cloud, …), run one script, and get a
standardized server in 10–15 minutes (plus waiting for DNS — a fresh Cloudflare
nameserver change can take hours, so set up DNS the day before).

```bash
# บน VPS ใหม่ เข้าเป็น root แล้ววางคำสั่งเดียว — ตอบคำถามบนจอจนจบ
curl -fsSL https://raw.githubusercontent.com/korwlik23/infra-stack/main/prepare.sh | bash
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
├── prepare.sh       # ช่วง A (root): user deploy + Docker + ล็อกเครื่อง → ต่อช่วง B ให้
├── install.sh       # ช่วง B (deploy): ถามโดเมน → database / monitoring / n8n → DNS → HTTPS
├── docs/            # คู่มือทั้งหมด (00-introduction … 26-new-project)
├── docker/          # Stack aggregation (core / database / monitoring / tools / messaging / storage)
├── services/        # หนึ่ง service = หนึ่งโฟลเดอร์ = หนึ่ง docker-compose.yml
├── monitoring/      # Prometheus config, alerts, Grafana dashboards
├── backup/          # Backup & restore scripts
├── scripts/         # Automation (harden, update, create-project, deploy, rollback, …)
├── templates/       # Project templates (laravel / nextjs / n8n / ai-worker)
├── environments/    # production / staging / development env examples
└── projects/        # Deployed projects (each independent, never committed secrets)
```

## Quick Start

> **ไม่เคยทำมาก่อน? อ่าน [docs/INSTALL.md](docs/INSTALL.md)** — คู่มือทีละขั้นตั้งแต่เช่า VPS,
> ย้ายโดเมนเข้า Cloudflare, ทำ SSH key จนเปิดหน้าแอดมินได้ บอกทุกขั้นว่าสำเร็จแล้วจะเห็นอะไร
> ติดปัญหา: [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)

ติดตั้งเครื่องใหม่ — เข้าเครื่องครั้งเดียว ไม่ต้อง logout/login ไม่ต้องแก้ไฟล์เอง:

```bash
# 0. ก่อนเริ่ม: โดเมนอยู่ใน Cloudflare และเป็น Active แล้ว (ย้าย nameserver อาจรอหลายชั่วโมง)
#    มี SSH key บนคอมตัวเอง (ssh-keygen -t ed25519)

# 1. เข้าเครื่องเป็น root (หรือ user ที่ sudo ได้ → ใช้ "| sudo bash")
ssh root@<server-ip>

# 2. ช่วง A + B ในคำสั่งเดียว
curl -fsSL https://raw.githubusercontent.com/korwlik23/infra-stack/main/prepare.sh | bash
#    ช่วง A (root):   ถามรหัส sudo ของ deploy + SSH public key → อัปเดตระบบ, Docker, UFW,
#                     Fail2ban, ปิด root/password login (session นี้ไม่หลุด)
#    "เริ่มติดตั้งต่อเลยไหม? [Y/n]" → Enter = สลับเป็น deploy (su - deploy) แล้วรันช่วง B
#    ช่วง B (deploy): ถามโดเมน, อีเมล, ติดตั้ง n8n ไหม → รหัสผ่านสุ่มให้ทุกตัว → Portainer
#                     (สร้าง admin ให้), database, monitoring, n8n → โชว์ตาราง DNS record ที่ต้องสร้าง
#                     รอจน DNS ครบ → เปิด Traefik + HTTPS → สรุป URL / รหัส / ของที่ต้องจด

# หลังติดตั้ง (ssh deploy@<server-ip>)
infra status                        # container + DNS + HTTPS
infra secrets                       # รหัสทั้งหมดอีกครั้ง

# เว็บของคุณ (docs/26)
cd /opt/infra-stack
./scripts/create-project.sh myapp laravel
nano projects/myapp/.env            # APP_IMAGE, APP_KEY และ per-project keys
./scripts/deploy.sh myapp

# Optional stacks — เช็ค DNS ก่อนเปิดแต่ละตัว: ./scripts/check-dns.sh tools (messaging / storage)
docker compose --env-file .env -f docker/docker-compose.tools.yml up -d      # pgAdmin, Redis Insight
docker compose --env-file .env -f docker/docker-compose.messaging.yml up -d  # RabbitMQ
docker compose --env-file .env -f docker/docker-compose.storage.yml up -d    # MinIO
```

ทำทีละขั้นเอง: `git clone` → `sudo ./scripts/harden.sh` → `su - deploy` → `./install.sh`
(ทั้งสองสคริปต์รันซ้ำได้ ทำต่อจากที่ค้าง) · อัตโนมัติไม่ถาม: `INFRA_DOMAIN=… INFRA_EMAIL=… ./install.sh`

เครื่องที่ติดตั้งไว้ก่อนแล้วและจะ `git pull` เวอร์ชันนี้: อ่าน upgrade notes ใน
[docker/README.md](docker/README.md) ก่อน (ต้องย้าย volume ครั้งเดียว)

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
ใช้ยังไง ทำอะไรได้บ้าง แบบไม่ต้องมีพื้นฐาน แล้วติดตั้งตาม [docs/INSTALL.md](docs/INSTALL.md)

Start at [docs/00-introduction.md](docs/00-introduction.md).
Architecture details in [docs/architecture.md](docs/architecture.md),
requirements in [docs/requirements.md](docs/requirements.md),
roadmap in [docs/roadmap.md](docs/roadmap.md).
Installation checklist in [TODO.md](TODO.md).

## Versioning

Infrastructure is versioned like software — see [CHANGELOG.md](CHANGELOG.md).
Current: **v2.4.0** — one-command install (`prepare.sh` → `install.sh`): no logout/login,
no hand-edited `.env`, DNS records created while the installer waits.

## License

[MIT](LICENSE)
