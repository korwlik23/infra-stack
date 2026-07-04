# 17 — Deploy n8n

🎯 n8n production: PostgreSQL backend + HTTPS webhook + backup ครบ

## ⚙️ วิธีทำ

```bash
./scripts/create-project.sh n8n n8n
docker exec -it postgres psql -U $POSTGRES_USER -c "CREATE DATABASE n8n_db;"
nano projects/n8n/.env     # APP_DOMAIN + N8N_ENCRYPTION_KEY (openssl rand -hex 24)
# DNS: n8n.<domain> ใน Cloudflare
cd projects/n8n && docker compose up -d
```

เปิด `https://n8n.<domain>` → สร้าง owner account

## ⚠️ ระวัง (สำคัญ)

- **`N8N_ENCRYPTION_KEY` หาย = credentials ทุก workflow กู้ไม่ได้** —
  เก็บสำเนา key ไว้ที่ปลอดภัยนอกเครื่อง (password manager)
- Webhook ต้องเป็น HTTPS โดเมนจริง — template ตั้ง `WEBHOOK_URL` ให้แล้ว
- Workflow ที่สร้างรูป/คลิป (FFmpeg ฯลฯ) กิน RAM มาก — ดู Netdata ช่วงรัน
  ถ้าตึงบ่อยพิจารณา queue mode + worker แยก หรืออัปเกรดเครื่อง

## Backup

- Workflow + credentials อยู่ใน `n8n_db` (โดน postgres-backup ทุกคืนอยู่แล้ว)
- Volume `n8n_data` (config + binary data) — เพิ่มชื่อ volume เข้า
  `volumes-backup.sh` เมื่อ deploy จริง

## 🧪 ทดสอบ

สร้าง workflow: Webhook trigger → ยิง `curl -X POST https://n8n.<domain>/webhook-test/...`
→ เห็น execution สำเร็จ
