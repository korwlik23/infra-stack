# Grafana

Dashboard กลาง — CPU, RAM, Docker, PostgreSQL, Redis, Network
เปิดที่ `https://grafana.<BASE_DOMAIN>` (user/pass จาก `.env`)

## Start

```bash
# จาก repo root (/opt/infra-stack) — อยู่ใน monitoring stack
infra up monitoring grafana
```

- Data source **Prometheus** ถูก provision อัตโนมัติ
- Dashboard JSON ใน `monitoring/dashboards/` → โผล่ในโฟลเดอร์ "InfraStack" เอง
  มาให้แล้ว: **Node Exporter Full** (1860), **Docker monitoring** (193)

## Rollback

```bash
infra stop monitoring grafana   # ข้อมูล dashboard ที่สร้างใน UI อยู่ใน volume grafana_data
```
