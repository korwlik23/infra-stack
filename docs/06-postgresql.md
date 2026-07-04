# 06 — PostgreSQL

🎯 Database กลางตัวเดียว รองรับหลาย project (แยก database ต่อ project)

## ⚙️ วิธีทำ

```bash
docker compose --env-file .env -f docker/docker-compose.database.yml up -d
```

Database ต่อ project (zennuaflow_db, trex_db, printshub_db, bdo_db, n8n_db)
ถูกสร้างจาก `services/postgres/init/01-create-databases.sql` ในครั้งแรก

เพิ่มทีหลัง:

```bash
docker exec -it postgres psql -U $POSTGRES_USER -c "CREATE DATABASE myapp_db;"
```

## การต่อจาก app

```text
host:     postgres        (ผ่าน Docker network `backend`)
port:     5432
user:     $POSTGRES_USER
password: $POSTGRES_PASSWORD
```

## ⚠️ ระวัง

- **ไม่ expose 5432 ออก internet** — ถ้าจำเป็นต้องต่อจากเครื่องนอก ใช้ SSH tunnel:
  `ssh -L 5432:localhost:5432 deploy@<ip>` (และเปิด `127.0.0.1:5432` ใน compose ก่อน)
- อัปเกรด major version (16→17) ต้อง dump/restore — ห้ามเปลี่ยน image tag เฉย ๆ
- ตั้ง cron backup ตั้งแต่วันแรก — ดู [13-backup.md](13-backup.md)

## 🧪 ทดสอบ

```bash
docker exec postgres pg_isready
docker exec -it postgres psql -U $POSTGRES_USER -c "\l"   # เห็น database ทุกตัว
```
