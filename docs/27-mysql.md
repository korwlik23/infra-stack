# 27 — MySQL (ทางเลือก)

🎯 สำหรับ app ที่เขียนมากับ MySQL (เช่น Laravel ที่พัฒนาบน XAMPP) — ไม่ต้องแปลงไป PostgreSQL

MySQL **ไม่เปิดตอนติดตั้ง** เปิดเองเมื่อมี project แรกที่ใช้ — เครื่องที่ไม่มี project MySQL ไม่เสีย RAM

## ⚙️ วิธีทำ

สร้าง project ด้วย `--mysql` (ใช้ได้กับ template `laravel` และ `nextjs`):

```bash
./scripts/create-project.sh shop laravel --mysql
```

script ทำให้ครบ:

1. ยังไม่มี `MYSQL_ROOT_PASSWORD` ใน `.env` กลาง → สุ่มให้
2. เปิด MySQL stack (`docker/docker-compose.mysql.yml`, MySQL 8.4) ถ้ายังไม่เปิด แล้วรอจน healthy
3. สร้าง database `shop_db` + user `shop` ที่มีสิทธิ์**เฉพาะ database ตัวเอง** (ไม่ใช้ root)
4. เขียนค่าลง `projects/shop/.env`:
   - Laravel: `DB_CONNECTION=mysql`, `DB_HOST=mysql`, `DB_PORT=3306`, `DB_USERNAME`, `DB_PASSWORD`
   - Next.js: `DATABASE_URL=mysql://shop:<รหัส>@mysql:3306/shop_db`

จากนั้น deploy ตามปกติ (`./scripts/deploy.sh shop`) — migrate รันกับ MySQL เอง

## การต่อจาก app

```text
host:     mysql           (ผ่าน Docker network `backend` — ไม่เปิด port ออก internet)
port:     3306
user/pw:  ดูใน projects/<name>/.env
```

เข้า MySQL ด้วยมือ:

```bash
docker exec -it mysql sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot'
```

## Backup / restore

- `./scripts/backup.sh` dump ทุก database ด้วย `mysqldump --single-transaction` (ไม่ lock ตาราง)
  → `backup/archives/mysql/` + ส่งขึ้น R2 ถ้าตั้งไว้ · ไม่มี MySQL = ข้ามเฉย ๆ
- `restore-server.sh` เปิด MySQL + restore ให้เองเมื่อ backup มี dump ของ MySQL
- restore เอง: `./backup/scripts/mysql-restore.sh backup/archives/mysql/all_<stamp>.sql.gz`

## หน่วยความจำ

จำกัด InnoDB buffer pool ที่ 256M (เครื่อง 8 GB รันหลาย project) — ข้อมูลเยอะขึ้นแล้วช้า
เพิ่มใน `.env` กลาง เช่น `MYSQL_BUFFER_POOL=1G` แล้ว `./scripts/update.sh mysql`

## อัปเดต

```bash
./scripts/update.sh mysql      # ถามยืนยัน — backup ก่อนเสมอ
```

image `mysql:8.4` = LTS สาย 8.4 → pull ใหม่ได้แพตช์ล่าสุดของสายนี้โดยไม่ข้าม major
