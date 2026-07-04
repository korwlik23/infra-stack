# __PROJECT__ (n8n)

Automation platform — ใช้ PostgreSQL เป็น database (ไม่ใช่ SQLite) + HTTPS ผ่าน Traefik

## Deploy

```bash
docker exec -it postgres psql -U infra -c "CREATE DATABASE n8n_db;"
nano .env      # ตั้ง N8N_ENCRYPTION_KEY (openssl rand -hex 24) — เก็บรักษาให้ดี
docker compose up -d
```

## ระวัง

- `N8N_ENCRYPTION_KEY` หาย = credentials ใน workflow ทั้งหมดกู้ไม่ได้
- Workflow data อยู่ทั้งใน PostgreSQL และ volume — backup ทั้งคู่
- webhook URL ต้องเป็น HTTPS domain จริง (ตั้งผ่าน `WEBHOOK_URL` แล้ว)
