# docker/ — Stack Aggregation

รวม service ทีละกลุ่มด้วย Compose `include:` (ต้องใช้ Docker Compose ≥ 2.20)
Source of truth ของแต่ละ service อยู่ที่ `services/<name>/docker-compose.yml`

| Stack | ไฟล์ | ประกอบด้วย |
|-------|------|-----------|
| Core | `docker-compose.core.yml` | Traefik, Portainer |
| Database | `docker-compose.database.yml` | PostgreSQL, Redis |
| Monitoring | `docker-compose.monitoring.yml` | Netdata, Prometheus+exporters, Alertmanager, Grafana, Loki+Promtail, Uptime Kuma, Dozzle, Watchtower, Beszel |
| Tools | `docker-compose.tools.yml` | pgAdmin, Redis Insight |
| Messaging (v2.0) | `docker-compose.messaging.yml` | RabbitMQ |
| Storage (v2.0) | `docker-compose.storage.yml` | MinIO |

ลำดับการ start: **Core → Database → Monitoring** (Traefik ต้องมาก่อนเพราะสร้าง route ให้ตัวอื่น)
Tools / Messaging / Storage เปิดเมื่อต้องการเท่านั้น — ไม่บังคับ

ต้องการเปิดแค่บาง service? รันตรงที่โฟลเดอร์ service นั้นได้เลย:

```bash
docker compose --env-file ../../.env -f services/redis/docker-compose.yml up -d
```
