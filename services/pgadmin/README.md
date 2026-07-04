# pgAdmin 4

จัดการ PostgreSQL ผ่าน Browser (เหมือน phpMyAdmin) — `https://pgadmin.<BASE_DOMAIN>`
Login ด้วย `PGADMIN_EMAIL` / `PGADMIN_PASSWORD` จาก `.env`

## เพิ่ม server ครั้งแรก

Add New Server → Connection:

```text
Host:     postgres      (ผ่าน network backend)
Port:     5432
Username: $POSTGRES_USER
Password: $POSTGRES_PASSWORD
```

## Start

```bash
docker compose --env-file ../../.env up -d
```

⚠️ pgAdmin เห็น database ทั้งหมด — ใช้รหัสผ่านแข็งแรง และถ้าไม่ได้ใช้ประจำ
ปิดไว้ (`docker compose down`) เปิดเฉพาะตอนต้องการก็ได้
