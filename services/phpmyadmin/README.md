# phpMyAdmin

จัดการ MySQL ผ่าน Browser — `https://mysql.<BASE_DOMAIN>` (สำหรับ project ที่สร้างด้วย `--mysql` — docs/27)

ถามรหัส 2 ชั้น:

1. หน้าต่าง login ของ browser — `DASHBOARD_USER` / `DASHBOARD_PASSWORD` (`infra secrets`)
2. หน้า login ของ phpMyAdmin — เลือกได้:
   - `root` / `MYSQL_ROOT_PASSWORD` (`.env` กลาง) — เห็นทุก database
   - user ของ project (`DB_USERNAME` / `DB_PASSWORD` ใน `projects/<name>/.env`) — เห็นเฉพาะ database ตัวเอง (ปลอดภัยกว่า)

## Start

```bash
# DNS record mysql.<BASE_DOMAIN> → IP เครื่อง ก่อน (infra เช็คให้)
infra up tools phpmyadmin
```

⚠️ root เห็นและลบได้ทุก database — `infra backup` ก่อนแก้ข้อมูล · ไม่ได้ใช้ประจำปิดไว้ได้
(`infra stop tools phpmyadmin`)
