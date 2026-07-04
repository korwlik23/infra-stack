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

การเพิ่ม template ใหม่: สร้างโฟลเดอร์ + `docker-compose.yml` + `.env.example` + `README.md`
ใช้ `__PROJECT__` เป็น placeholder ทุกจุดที่เป็นชื่อ project
