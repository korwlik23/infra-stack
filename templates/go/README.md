# __PROJECT__ (Go)

Go HTTP service ต่อ Traefik (HTTPS อัตโนมัติ) — image ต้อง expose port 8080
และเป็น **alpine** (มี `sh` + `wget` ให้ healthcheck และ drain ใช้)

## ข้อตกลงฝั่ง app (ตัวอย่างครบ: `examples/go-app/` ใน infra-stack)

| ต้องมี | ทำไม |
|--------|------|
| ฟัง `:8080` | Traefik ส่ง traffic มาที่ port นี้ |
| `GET /healthz` ตอบ 200 เมื่อพร้อม (ping DB) | rolling deploy รอตัวใหม่ healthy ก่อนสลับ |
| `/app/server migrate` | `deploy.sh` รันก่อนสลับ traffic ทุกครั้ง |
| `/app/server seed` (รันซ้ำได้) | ข้อมูลพื้นฐาน — ถามก่อน seed เมื่อไฟล์ใน `seeds/` เปลี่ยน |

ใช้ golang-migrate / goose แทน subcommand ได้ — แก้ `DEPLOY_MIGRATE_CMD` / `DEPLOY_SEED_CMD` ใน .env

## Deploy

```bash
cd /opt/infra-stack
./scripts/setup-git.sh __PROJECT__ <owner>/<repo>    # clone + เปิด build (private repo จะได้ deploy key ไปวางใน GitHub)
./scripts/deploy.sh __PROJECT__                      # build + migrate + ถาม seed + rolling
./scripts/smoke.sh __PROJECT__
```

DNS: เพิ่ม record `__PROJECT__.<domain>` ชี้ server IP ใน Cloudflare (Proxied)

รายละเอียด: docs/29-deploy-go.md · zero-downtime: docs/25-zero-downtime.md
