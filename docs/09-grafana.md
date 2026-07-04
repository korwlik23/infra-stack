# 09 — Grafana + Prometheus

🎯 Dashboard ประวัติย้อนหลัง 30 วัน + alert rules

## ⚙️ วิธีทำ

อยู่ใน monitoring stack แล้ว ประกอบด้วย:

- **Prometheus** — เก็บ metrics (scrape ทุก 15s, เก็บ 30 วัน)
- **node-exporter** — metrics ของ host
- **cadvisor** — metrics ราย container
- **Grafana** — `https://grafana.<BASE_DOMAIN>` (user/pass จาก `.env`)

Data source Prometheus ถูก provision อัตโนมัติ

## Dashboard เริ่มต้น

Import จาก grafana.com (Dashboards → New → Import):

| ID | ชื่อ |
|----|------|
| 1860 | Node Exporter Full |
| 193 | Docker monitoring |

แล้ว export JSON เก็บที่ `monitoring/dashboards/` เพื่อให้เครื่องใหม่ได้ dashboard เดียวกัน

## Alert rules

อยู่ที่ `monitoring/alerts/basic-alerts.yml` — CPU>90%, RAM>90%, Disk>85%, core container down
(ส่ง Telegram ต้องเพิ่ม Alertmanager — อยู่ใน roadmap v1.x)

## 🧪 ทดสอบ

```bash
docker exec prometheus wget -qO- http://localhost:9090/api/v1/targets | grep -o '"health":"up"' | wc -l
# ต้องได้ ≥ 3 (prometheus, node, cadvisor)
```
