# 17 — Deploy n8n

🎯 n8n production: PostgreSQL backend + HTTPS webhook + backup ครบ

## ⚙️ วิธีทำ

```bash
./scripts/create-project.sh n8n n8n     # ใช้ database n8n_db (สร้างให้ถ้ายังไม่มี)
nano projects/n8n/.env     # N8N_ENCRYPTION_KEY (openssl rand -hex 24) — APP_DOMAIN/DB เติมให้แล้ว
# DNS: n8n.<domain> ใน Cloudflare (ก่อน deploy)
./scripts/deploy.sh n8n
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
- Volume (config + binary data) ชื่อจริงคือ `<project>_<project>_data` — project ชื่อ `n8n`
  ได้ `n8n_n8n_data` — `./scripts/backup.sh` เก็บให้อัตโนมัติ (backup ทุก named volume ในเครื่อง)
- `N8N_ENCRYPTION_KEY` อยู่ใน `projects/<name>/.env` — ถูกเก็บใน secrets backup (เข้ารหัส) ด้วย

## 🧪 ทดสอบ

สร้าง workflow: Webhook trigger → ยิง `curl -X POST https://n8n.<domain>/webhook-test/...`
→ เห็น execution สำเร็จ
