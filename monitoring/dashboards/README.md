# Grafana Dashboards

ไฟล์ `.json` ในโฟลเดอร์นี้ → Grafana โหลดเองในโฟลเดอร์ **InfraStack** (provisioned, เช็คทุก 30 วินาที)
ไม่ต้อง import เอง — เครื่องใหม่ได้ชุดเดียวกันทันทีหลัง `install.sh` / `git pull`

| ไฟล์ | ต้นทาง (grafana.com) | ใช้ดู |
|------|------|-------|
| `node-exporter-full.json` | 1860 Node Exporter Full ([rfmoz/grafana-dashboards](https://github.com/rfmoz/grafana-dashboards)) | ทั้งเครื่อง: CPU / RAM / Disk / Network |
| `docker-containers.json` | 193 Docker monitoring | ราย container: CPU / Memory / Network |

## เพิ่ม / อัปเดต dashboard

1. Import ใน UI (Dashboards → New → Import) แล้วตรวจว่ามีข้อมูลจริง
2. Export JSON (Share → Export → **ไม่ติ๊ก** "Export for sharing externally")
3. ก่อน commit ทำให้ใช้ได้ทุกเครื่อง:
   - ลบ `id` และตั้ง `uid` คงที่ขึ้นต้นด้วย `infra-` (ห้ามซ้ำกับ dashboard ที่ import ใน UI)
   - data source ที่เป็น `{"type":"prometheus","uid":"<สุ่มต่อเครื่อง>"}` → `"Prometheus"` (ชื่อที่ provision ทุกเครื่อง)
   - ตัวแปร `datasource` / `query` ใน templating: ล้าง `current` (เก็บค่าของเครื่องที่ export)

⚠️ dashboard ที่ export แบบ "for sharing externally" อ้าง `${DS_PROMETHEUS}` ซึ่งตอน provision ไม่มีใครเติมให้
→ ทุก panel ขึ้นสามเหลี่ยมแดง / N/A (เจอจริงกับ 193 — dashboard เก่าไม่มีช่องเลือก data source ตอน import)

แก้ dashboard ที่ provision ใน UI ได้แต่ save ทับไฟล์ไม่ได้ — แก้ JSON ในนี้แล้ว commit แทน

Dashboard อื่นที่น่าเพิ่ม: 9628 PostgreSQL · 11835 Redis (มี exporter อยู่ใน monitoring stack แล้ว)
