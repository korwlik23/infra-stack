# __PROJECT__ (AI Worker)

Worker ประมวลผลหลังบ้าน — สร้างรูป/คลิป, AI chatbot flow, งานจาก n8n
รับงานจาก queue (Redis หรือ RabbitMQ) → ประมวลผล → อัปโหลดผลลัพธ์ขึ้น R2

## Pattern

```text
n8n / Laravel ──push job──▶ Redis/RabbitMQ ──▶ __PROJECT__ ──▶ R2
                                                (FFmpeg, AI API, …)
```

## Deploy

```bash
nano .env          # queue URL, API keys, resource limits
docker compose up -d
docker logs -f __PROJECT__
```

## ⚠️ ระวัง

- `mem_limit`/`cpus` ตั้งไว้กัน worker กินทั้งเครื่อง — งาน FFmpeg หนัก ๆ
  บนเครื่อง 8GB ไม่ควรเกิน 2-3GB ต่อ worker
- Scale: `docker compose up -d --scale __PROJECT__=2` (ลบ `container_name` ก่อน)
