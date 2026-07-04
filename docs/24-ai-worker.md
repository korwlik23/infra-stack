# 24 — AI Worker (v2.0)

🎯 งาน AI หนัก ๆ (สร้างรูป/คลิป, chatbot flow) แยกออกจากเว็บ — เว็บไม่สะดุด

## Pattern

```text
n8n / Laravel ──push job──▶ Redis หรือ RabbitMQ ──▶ AI Worker ──▶ R2
   (รับคำสั่ง)                    (คิวงาน)            (FFmpeg, OpenAI, …)   (เก็บผลลัพธ์)
```

เว็บตอบ user ทันที ("กำลังสร้าง…") — worker ทำงานหลังบ้าน เสร็จแล้วแจ้งกลับผ่าน
webhook/queue

## ⚙️ วิธีทำ

```bash
./scripts/create-project.sh img-worker ai-worker
nano projects/img-worker/.env    # queue URL, OPENAI_API_KEY, R2, mem limit
cd projects/img-worker && docker compose up -d
```

Template มี `mem_limit`/`cpus` กัน worker กินทั้งเครื่อง (default 2g/2cpu)

## ⚠️ ระวัง

- เครื่อง 8GB: เว็บ + db + monitoring กินไป ~4-5GB — เหลือให้ worker ~2-3GB
  งานวิดีโอหนักจริงคือสัญญาณไป Stage 2 (แยก AI Worker ไปเครื่องของมัน — ดู [18-scale.md](18-scale.md))
- API key อยู่ใน `.env` ของ project เท่านั้น — ห้าม commit
