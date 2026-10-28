# PostgreSQL 16

Database กลางของทุก project — app ต่อผ่าน Docker network `backend`
(host = `postgres`, port = `5432`) ไม่ expose ออก internet

## Start

```bash
# จาก repo root (/opt/infra-stack) — อยู่ใน database stack
docker compose --env-file .env -f docker/docker-compose.database.yml up -d postgres
```

Database ตัวอย่าง (`app_db`, `n8n_db`) ถูกสร้างจาก `init/01-create-databases.sql`
(เฉพาะครั้งแรกที่ volume ว่าง) — database ของ project ใหม่ `create-project.sh` สร้างให้

## เพิ่ม database ใหม่ภายหลัง (ด้วยมือ)

`POSTGRES_USER` อ่านจาก env ของ container (shell บน host ไม่มีตัวแปรนี้):

```bash
docker exec -it postgres sh -c 'psql -U "$POSTGRES_USER" -d postgres -c "CREATE DATABASE myapp_db;"'
```

## Test / Backup / Rollback

```bash
docker exec postgres pg_isready               # ต้องได้ accepting connections
./backup/scripts/postgres-backup.sh          # backup ทุก database
docker compose --env-file .env -f docker/docker-compose.database.yml stop postgres   # หยุด (ข้อมูลอยู่ใน volume)
```

⚠️ `docker volume rm postgres_data` = **ลบข้อมูลทั้งหมดถาวร** — ต้องมี backup ก่อนเสมอ
