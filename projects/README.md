# projects/

ที่วาง project ที่ deploy จริงบนเครื่องนี้ — สร้างด้วย:

```bash
./scripts/create-project.sh <name> <laravel|nextjs|n8n>
```

แต่ละ project เป็นอิสระ: มี `docker-compose.yml` + `.env` ของตัวเอง
up / down / update ได้โดยไม่กระทบตัวอื่น

⚠️ ไฟล์ `.env` และข้อมูล runtime ใน projects/ **ไม่ถูก commit** (ดู .gitignore)
สิ่งที่ควร commit คือ `docker-compose.yml`, `.env.example`, `README.md` ของ project
