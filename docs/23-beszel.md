# 23 — Beszel (Multi-Server Monitoring, v2.0)

🎯 มีหลาย VPS เมื่อไหร่ ดูทุกเครื่องจากจอเดียว

Netdata/Grafana ดูลึก**เครื่องเดียว** — Beszel ตอบคำถาม "ทุกเครื่องยัง OK ไหม"
ใน 3 วินาที (CPU/RAM/Disk/Docker ของทุก server + alert)

## ⚙️ วิธีทำ

Hub อยู่ใน monitoring stack แล้ว → `https://servers.<BASE_DOMAIN>`
ขั้นตอน pairing agent: [services/beszel/README.md](../services/beszel/README.md)

## เพิ่มเครื่องใหม่ (Stage 2+)

```bash
# บนเครื่องใหม่ — clone infra-stack แล้ว:
cd services/beszel
# ใส่ BESZEL_AGENT_KEY จากหน้า Add System ของ hub ใน .env
docker compose --env-file ../../.env up -d beszel-agent
```

## หมายเหตุ

ตอนมีเครื่องเดียว Beszel ยังไม่จำเป็น (Netdata พอ) — ติดไว้เพื่อให้
โครงพร้อมตอนซื้อเครื่องที่สอง ไม่ต้องรื้อ monitoring ใหม่
