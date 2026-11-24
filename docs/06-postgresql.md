# 06 — PostgreSQL

🎯 Database กลางตัวเดียว รองรับหลาย project (แยก database ต่อ project)

## ⚙️ วิธีทำ

```bash
infra up database
```

ตัวอย่าง `app_db` และ database สำหรับ bundled n8n template ถูกสร้างจาก
`services/postgres/init/01-create-databases.sql` ในครั้งแรก
database ของ project ใหม่: `create-project.sh` สร้างให้อัตโนมัติ (`<project>_db`)

⚠️ ตั้ง `POSTGRES_PASSWORD` ใน `.env` **ก่อน** start ครั้งแรก — postgres บันทึกรหัสลง volume
ตอน init แก้ `.env` ทีหลังจะไม่มีผล (app ได้ `password authentication failed`)

เพิ่มเองทีหลัง (`$POSTGRES_USER` อ่านจาก env ของ container — shell บน host ไม่มีตัวแปรนี้):

```bash
docker exec -it postgres sh -c 'psql -U "$POSTGRES_USER" -d postgres -c "CREATE DATABASE myapp_db;"'
```

## การต่อจาก app

```text
host:     postgres        (ผ่าน Docker network `backend`)
port:     5432
user:     user ของ project เอง (create-project.sh สร้างให้ — ดู DB_USERNAME / DATABASE_URL ใน .env ของ project)
password: สุ่มต่อ project
```

**ห้ามให้แอปใช้ `$POSTGRES_USER`** (superuser) — แอปเดียวโดนเจาะ = ทุก database + สั่งคำสั่งบนเครื่องได้
project ที่สร้างก่อน v2.15 ยังใช้ superuser อยู่: `infra db-user <ชื่อ>` แล้ว `infra restart <ชื่อ>` (docs/31)
superuser มีไว้สำหรับ backup / restore / `infra psql` เท่านั้น

## ⚠️ ระวัง

- **ไม่ expose 5432 ออก internet** — ถ้าจำเป็นต้องต่อจากเครื่องนอก ใช้ SSH tunnel:
  `ssh -L 5432:localhost:5432 deploy@<ip>` (และเปิด `127.0.0.1:5432` ใน compose ก่อน)
- อัปเกรด major version (16→17) ต้อง dump/restore — ห้ามเปลี่ยน image tag เฉย ๆ
- ตั้ง cron backup ตั้งแต่วันแรก — ดู [13-backup.md](13-backup.md)

## 🧪 ทดสอบ

```bash
docker exec postgres pg_isready
docker exec -it postgres sh -c 'psql -U "$POSTGRES_USER" -d postgres -c "\l"'   # เห็น database ทุกตัว
```
