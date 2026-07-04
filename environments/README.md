# environments/

ตัวอย่าง `.env` ต่อ environment — copy ไป repo root ตามเครื่องที่ deploy:

```bash
cp environments/production.env.example .env   # บน production VPS
nano .env
```

| ไฟล์ | ใช้กับ |
|------|--------|
| `production.env.example` | VPS production (Contabo Singapore) |
| `staging.env.example` | เครื่อง staging |
| `development.env.example` | local dev |

ไฟล์ `.env` จริง**ห้าม commit** — เฉพาะ `.example` เท่านั้นที่อยู่ใน Git
