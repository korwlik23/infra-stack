# Grafana

Dashboard กลาง — CPU, RAM, Docker, PostgreSQL, Redis, Network
เปิดที่ `https://grafana.<BASE_DOMAIN>` (user/pass จาก `.env`)

## Start

```bash
docker compose --env-file ../../.env up -d
```

- Data source **Prometheus** ถูก provision อัตโนมัติ
- Dashboard JSON วางไว้ที่ `monitoring/dashboards/` → โผล่ในโฟลเดอร์ "InfraStack" เอง
- Dashboard แนะนำให้ import: **1860** (Node Exporter Full), **193** (Docker)

## Rollback

```bash
docker compose down          # ข้อมูล dashboard ที่สร้างใน UI อยู่ใน volume grafana_data
```
