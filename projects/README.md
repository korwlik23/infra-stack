# projects/

ที่วาง project ที่ deploy จริงบนเครื่องนี้ — สร้างด้วย:

```bash
infra new <name> <laravel|nextjs|go|n8n|ai-worker> [--mysql|--external-db]
infra git <name> <github-user>/<repo>   # เชื่อม GitHub → auto-deploy
```

แต่ละ project เป็นอิสระ: มี `docker-compose.yml` + `.env` ของตัวเอง
up / down / update ได้โดยไม่กระทบตัวอื่น

⚠️ ไฟล์ `.env` และข้อมูล runtime ใน projects/ **ไม่ถูก commit** (ดู .gitignore)
สิ่งที่ควร commit คือ `docker-compose.yml`, `.env.example`, `README.md` ของ project
