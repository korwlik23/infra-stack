# Grafana

Dashboard กลาง — CPU, RAM, Docker, PostgreSQL, Redis, Network
เปิดที่ `https://grafana.<BASE_DOMAIN>` (user/pass จาก `.env`)

## Start

```bash
# จาก repo root (/opt/infra-stack) — อยู่ใน monitoring stack
docker compose --env-file .env -f docker/docker-compose.monitoring.yml up -d grafana
```

- Data source **Prometheus** ถูก provision อัตโนมัติ
- Dashboard JSON วางไว้ที่ `monitoring/dashboards/` → โผล่ในโฟลเดอร์ "InfraStack" เอง
- Dashboard แนะนำให้ import: **1860** (Node Exporter Full), **193** (Docker)

## Rollback

```bash
docker compose --env-file .env -f docker/docker-compose.monitoring.yml stop grafana   # ข้อมูล dashboard ที่สร้างใน UI อยู่ใน volume grafana_data
```
