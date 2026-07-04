# Grafana Dashboards

วางไฟล์ dashboard `.json` ในโฟลเดอร์นี้ → Grafana โหลดอัตโนมัติ (provisioned)

Dashboard แนะนำ (import จาก grafana.com แล้ว export JSON มาเก็บที่นี่):

| ID | ชื่อ | ใช้ดู |
|----|------|-------|
| 1860 | Node Exporter Full | CPU / RAM / Disk / Network |
| 193 | Docker monitoring | Container CPU / Memory |
| 9628 | PostgreSQL Database | PostgreSQL (ต้องเพิ่ม postgres-exporter) |
| 11835 | Redis Dashboard | Redis (ต้องเพิ่ม redis-exporter) |

เก็บ JSON ไว้ใน Git เพื่อให้ VPS เครื่องใหม่ได้ dashboard ชุดเดียวกันทันที
