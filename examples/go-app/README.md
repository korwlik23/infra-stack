# examples/go-app

Go service ตัวอย่างที่ทำตามข้อตกลงของ `templates/go` — ใช้ทดสอบ template และเป็นแม่แบบ app จริง

```bash
go run . migrate && go run . seed && go run .     # ต้องตั้ง DATABASE_URL
```

| คำสั่ง | ทำอะไร |
|--------|--------|
| `server` | ฟัง `:8080` — `/healthz` ping DB, `/` นับ roles |
| `server migrate` | รัน `migrations/*.sql` ที่ยังไม่เคยรัน (จำใน `schema_migrations`) |
| `server seed` | รัน `seeds/*.sql` — ต้องรันซ้ำได้ (`ON CONFLICT DO NOTHING`) |

ทดลองบนเซิร์ฟเวอร์: docs/29-deploy-go.md หัวข้อ "ทดสอบ template"
