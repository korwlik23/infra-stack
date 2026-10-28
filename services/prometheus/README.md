# Prometheus + Node Exporter + cAdvisor

เก็บ metrics ของเครื่องและ Docker containers (retention 30 วัน)
เป็น data source ให้ Grafana — ไม่ expose dashboard ออก internet

- **node-exporter** — CPU / RAM / Disk / Network ของ host
- **cadvisor** — metrics ราย container

Config หลักอยู่ที่ [monitoring/prometheus.yml](../../monitoring/prometheus.yml)
และ alert rules ที่ [monitoring/alerts/](../../monitoring/alerts/)

## Start / Test

```bash
# จาก repo root (/opt/infra-stack) — อยู่ใน monitoring stack
docker compose --env-file .env -f docker/docker-compose.monitoring.yml up -d prometheus node-exporter cadvisor
docker exec prometheus wget -qO- http://localhost:9090/-/healthy   # → Healthy
```
