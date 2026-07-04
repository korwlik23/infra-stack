# docker/ — Stack Aggregation

รวม service ทีละกลุ่มด้วย Compose `include:` (ต้องใช้ Docker Compose ≥ 2.20)
Source of truth ของแต่ละ service อยู่ที่ `services/<name>/docker-compose.yml`

| Stack | ไฟล์ | ประกอบด้วย |
|-------|------|-----------|
| Core | `docker-compose.core.yml` | Traefik, Portainer |
| Database | `docker-compose.database.yml` | PostgreSQL, Redis |
| Monitoring | `docker-compose.monitoring.yml` | Netdata, Prometheus, Grafana, Uptime Kuma, Dozzle, Watchtower |

ลำดับการ start: **Core → Database → Monitoring** (Traefik ต้องมาก่อนเพราะสร้าง route ให้ตัวอื่น)

ต้องการเปิดแค่บาง service? รันตรงที่โฟลเดอร์ service นั้นได้เลย:

```bash
docker compose --env-file ../../.env -f services/redis/docker-compose.yml up -d
```
