# Beszel (v2.0)

Monitor **หลาย server** จากจอเดียว — เบามาก (agent ~10MB RAM)
เตรียมไว้สำหรับวันที่มี Contabo + Hetzner + Oracle พร้อมกัน

## Setup ครั้งแรก

```bash
docker compose --env-file ../../.env up -d beszel
# เปิด https://servers.<BASE_DOMAIN> → สร้าง admin
# → Add System: host = <server-ip>, port = 45876 → copy public key
# ใส่ key ใน .env: BESZEL_AGENT_KEY="ssh-ed25519 AAAA..."
docker compose --env-file ../../.env up -d beszel-agent
```

## เพิ่ม server เครื่องที่สอง

บนเครื่องใหม่รันเฉพาะ agent (มีใน install ของ infra-stack อยู่แล้ว):
Add System ใน hub → เอา key ไปใส่ `.env` เครื่องนั้น → up agent

## หมายเหตุ

- Hub มี login ของตัวเอง — ไม่ต้องใส่ basicauth เพิ่ม
- agent ใช้ `network_mode: host` เพื่ออ่าน network stats จริงของเครื่อง
