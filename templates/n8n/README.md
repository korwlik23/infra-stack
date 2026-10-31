# __PROJECT__ (n8n)

Automation platform — ใช้ PostgreSQL เป็น database (ไม่ใช่ SQLite) + HTTPS ผ่าน Traefik

## Deploy

```bash
# database __PROJECT___db ถูกสร้างให้แล้วตอน create-project.sh (ถ้า postgres รันอยู่)
# N8N_ENCRYPTION_KEY สุ่มให้แล้ว — จดเก็บนอกเครื่อง: grep N8N_ENCRYPTION_KEY .env
cd ../.. && ./scripts/deploy.sh __PROJECT__
```

## ระวัง

- `N8N_ENCRYPTION_KEY` หาย = credentials ใน workflow ทั้งหมดกู้ไม่ได้
- Workflow data อยู่ทั้งใน PostgreSQL และ volume `__PROJECT_____PROJECT___data` — `./scripts/backup.sh`
  เก็บทั้งคู่ + `.env` (มี `N8N_ENCRYPTION_KEY`) แบบเข้ารหัสให้อัตโนมัติ
- webhook URL ต้องเป็น HTTPS domain จริง (ตั้งผ่าน `WEBHOOK_URL` แล้ว)
