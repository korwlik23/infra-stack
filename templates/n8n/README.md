# __PROJECT__ (n8n)

Automation platform — ใช้ PostgreSQL เป็น database (ไม่ใช่ SQLite) + HTTPS ผ่าน Traefik

## Deploy

```bash
# database __PROJECT___db ถูกสร้างให้แล้วตอน create-project.sh (ถ้า postgres รันอยู่)
nano .env      # ตั้ง N8N_ENCRYPTION_KEY (openssl rand -hex 24) — เก็บรักษาให้ดี
cd ../.. && ./scripts/deploy.sh __PROJECT__
```

## ระวัง

- `N8N_ENCRYPTION_KEY` หาย = credentials ใน workflow ทั้งหมดกู้ไม่ได้
- Workflow data อยู่ทั้งใน PostgreSQL และ volume `__PROJECT_____PROJECT___data` — backup ทั้งคู่
  (`./backup/scripts/volumes-backup.sh __PROJECT_____PROJECT___data`)
- webhook URL ต้องเป็น HTTPS domain จริง (ตั้งผ่าน `WEBHOOK_URL` แล้ว)
