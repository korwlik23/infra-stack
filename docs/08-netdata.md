# 08 — Netdata

🎯 เห็นสุขภาพเครื่องแบบ real-time (per-second) โดยไม่ต้องตั้งค่าอะไร

## ⚙️ วิธีทำ

อยู่ใน monitoring stack:

```bash
docker compose --env-file .env -f docker/docker-compose.monitoring.yml up -d
```

เปิด `https://netdata.<BASE_DOMAIN>` (มี basicauth — เปลี่ยน hash ใน compose ก่อน)

## ใช้ดูอะไร

- CPU / RAM / Disk / Network แบบวินาทีต่อวินาที
- Docker containers (auto-detect)
- PostgreSQL / Redis (auto-detect เมื่อเห็น container)

## Netdata vs Grafana

| | Netdata | Grafana+Prometheus |
|--|---------|--------------------|
| จุดแข็ง | real-time, zero-config, debug ตอนเครื่องหน่วง | ย้อนหลัง 30 วัน, dashboard custom, alert rules |
| ใช้ตอน | "ตอนนี้เครื่องเป็นอะไร" | "อาทิตย์ที่แล้วเกิดอะไร / แนวโน้ม" |

ใช้คู่กัน — ไม่ใช่เลือกอย่างเดียว
