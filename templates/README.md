# templates/

แม่แบบสำหรับ `scripts/create-project.sh` — ตัว script จะ copy โฟลเดอร์
แล้วแทนที่ `__PROJECT__` ด้วยชื่อ project ทุกไฟล์

| Template | ใช้กับ |
|----------|--------|
| `laravel/` | Laravel app + queue worker + scheduler |
| `nextjs/` | Next.js standalone |
| `n8n/` | n8n (PostgreSQL backend) |
| `ai-worker/` | Worker AI หลังบ้าน (queue consumer + resource limits) — v2.0 |

ทุก template รองรับ 2 โหมด deploy:
- **Pre-built image** จาก registry (default — `APP_IMAGE` ใน .env)
- **Build on server** — clone app ไว้ที่ `src/` แล้ว uncomment `build: ./src` (ดู docs/19-cicd.md)

## Placeholder ใน template

| Token | แทนด้วย | ตอนไหน |
|-------|---------|--------|
| `__PROJECT__` | ชื่อ project | ทุกไฟล์ |
| `__ROOT:KEY__` | ค่าจาก `.env` กลาง (คีย์ `KEY`) | เฉพาะไฟล์ `.env` ตอน create-project |

`__ROOT:KEY__` = ดึงค่า share กัน (DB/Redis/domain/TZ/R2) จาก `.env` กลางให้อัตโนมัติ
→ ลดการพิมพ์ซ้ำ + typo เช่น `DB_PASSWORD=__ROOT:POSTGRES_PASSWORD__`
ถ้า key ไม่มีใน `.env` กลาง (หรือเป็น CHANGE_ME) → script ใส่ `CHANGE_ME` + เตือน

การเพิ่ม template ใหม่: สร้างโฟลเดอร์ + `docker-compose.yml` + `.env.example` + `README.md`
ใช้ `__PROJECT__` และ `__ROOT:KEY__` ตามข้างบน
