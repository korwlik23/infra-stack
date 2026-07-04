# PostgreSQL 16

Database กลางของทุก project — app ต่อผ่าน Docker network `backend`
(host = `postgres`, port = `5432`) ไม่ expose ออก internet

## Start

```bash
docker compose --env-file ../../.env up -d
```

Database ต่อ project ถูกสร้างอัตโนมัติจาก `init/01-create-databases.sql`
(เฉพาะครั้งแรกที่ volume ว่าง)

## เพิ่ม database ใหม่ภายหลัง

```bash
docker exec -it postgres psql -U $POSTGRES_USER -c "CREATE DATABASE myapp_db;"
```

## Test / Backup / Rollback

```bash
docker exec postgres pg_isready               # ต้องได้ accepting connections
../../backup/scripts/postgres-backup.sh       # backup ทุก database
docker compose down                           # ถอน (ข้อมูลอยู่ใน volume)
```

⚠️ `docker volume rm postgres_postgres_data` = **ลบข้อมูลทั้งหมดถาวร** — ต้องมี backup ก่อนเสมอ
