# 09 — Grafana + Prometheus

🎯 Dashboard ประวัติย้อนหลัง 30 วัน + alert rules

## ⚙️ วิธีทำ

อยู่ใน monitoring stack แล้ว ประกอบด้วย:

- **Prometheus** — เก็บ metrics (scrape ทุก 15s, เก็บ 30 วัน)
- **node-exporter** — metrics ของ host
- **cadvisor** — metrics ราย container
- **Grafana** — `https://grafana.<BASE_DOMAIN>` (user/pass จาก `.env`)

Data source Prometheus + Loki ถูก provision อัตโนมัติ

## Dashboard เริ่มต้น

มาพร้อมระบบแล้ว — Dashboards → โฟลเดอร์ **InfraStack** (ไม่ต้อง import):

| Dashboard | ใช้ดู |
|-----------|-------|
| Node Exporter Full (1860) | ทั้งเครื่อง: CPU, RAM, swap, ดิสก์, network |
| Docker monitoring (193) | ราย container: ตัวไหนกิน CPU / RAM |

ไฟล์อยู่ที่ `monitoring/dashboards/` — วิธีเพิ่มตัวใหม่ดู [README ในโฟลเดอร์นั้น](../monitoring/dashboards/README.md)

⚠️ import 193 เองใน UI จะได้ทุก panel เป็นสามเหลี่ยมแดง / N/A — มันอ้าง `${DS_PROMETHEUS}` แต่ไม่มีช่องให้เลือก
data source ตอน import → ใช้ตัวในโฟลเดอร์ InfraStack แทน

## ดู log

Explore → data source **Loki** → `{container="<ชื่อ container>"}` (กรอง: `|= "ERROR"`)
— ดู log สดทีละตัวง่ายกว่าที่ `https://logs.<BASE_DOMAIN>` (Dozzle)

## Alert rules

อยู่ที่ `monitoring/alerts/basic-alerts.yml` — CPU>90%, RAM>90%, Disk>85%, core container down
Prometheus ส่ง alert ไป Alertmanager (อยู่ใน monitoring stack) — default ยังไม่ส่งไปไหน
เปิด Telegram: [services/alertmanager/README.md](../services/alertmanager/README.md)

## 🧪 ทดสอบ

```bash
docker exec prometheus wget -qO- http://localhost:9090/api/v1/targets | grep -o '"health":"up"' | wc -l
# ต้องได้ 5 (prometheus, node, cadvisor, postgres, redis) — postgres/redis ขึ้นหลัง start database stack
```
