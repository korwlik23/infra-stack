# Roadmap

## 8 Phases

| Phase | งาน | สถานะ |
|-------|-----|-------|
| 1 | Requirement — [requirements.md](requirements.md) | ✅ |
| 2 | Architecture — [architecture.md](architecture.md) | ✅ |
| 3 | Folder Structure — docs/ docker/ services/ scripts/ templates/ projects/ monitoring/ backup/ environments/ | ✅ |
| 4 | Docker Base — networks, stack aggregation | ✅ |
| 5 | Core Services — Traefik, Portainer, PostgreSQL, Redis | ✅ |
| 6 | Monitoring — Netdata, Prometheus, Grafana, Uptime Kuma, Dozzle | ✅ |
| 7 | Automation — install, harden, update, backup, restore, create-project | ✅ |
| 8 | Documentation — คู่มือ 00–18 | ✅ v1.0.0 |

## v1.x (ถัดไป)

- [ ] Deploy จริงบน Contabo Singapore ตาม [00-introduction.md](00-introduction.md)
- [ ] pgAdmin + Redis Insight (DB UI)
- [ ] postgres-exporter + redis-exporter → Grafana dashboards
- [ ] Alertmanager → Telegram
- [ ] CI/CD: GitHub Actions auto deploy ([13-backup.md](13-backup.md), docs/17)
- [ ] เก็บ Grafana dashboard JSON เข้า Git

## v2.0 (อนาคต)

- [ ] RabbitMQ (message queue)
- [ ] MinIO (self-hosted S3 — ทางหนีถ้า R2 แพง)
- [ ] ELK / Loki stack (log aggregation จริงจัง)
- [ ] AI Worker containers
- [ ] Beszel — monitor หลาย server จากจอเดียว
- [ ] Stage 2: แยก Database Server
