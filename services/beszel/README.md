# Beszel (v2.0)

Monitor **หลาย server** จากจอเดียว — เบามาก (agent ~10MB RAM)
เตรียมไว้สำหรับวันที่มี Contabo + Hetzner + Oracle พร้อมกัน

## Setup ครั้งแรก

⚠️ agent ถูกคอมเมนต์ไว้ใน compose — เพราะถ้า start โดยไม่มี KEY จะ restart loop
เปิดตามลำดับนี้:

```bash
docker compose --env-file ../../.env up -d beszel
# 1. เปิด https://servers.<BASE_DOMAIN> → สร้าง admin
# 2. Add System: host = <server-ip>, port = 45876 → copy public key
# 3. ใส่ key ใน /opt/infra-stack/.env: BESZEL_AGENT_KEY="ssh-ed25519 AAAA..."
# 4. เอา # ออกจาก service beszel-agent ใน docker-compose.yml นี้
docker compose --env-file ../../.env up -d beszel-agent
```

## เพิ่ม server เครื่องที่สอง

บนเครื่องใหม่รันเฉพาะ agent (มีใน install ของ infra-stack อยู่แล้ว):
Add System ใน hub → เอา key ไปใส่ `.env` เครื่องนั้น → up agent

## หมายเหตุ

- Hub มี login ของตัวเอง — ไม่ต้องใส่ basicauth เพิ่ม
- agent ใช้ `network_mode: host` เพื่ออ่าน network stats จริงของเครื่อง
