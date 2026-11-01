# 29 — Deploy Go

🎯 Go HTTP service + HTTPS + auto-deploy + migrate/seed ตอน deploy + rolling ไม่ดับ

## เตรียม app (ฝั่ง repo ของแอป)

ตัวอย่างครบที่ทำตามข้อตกลงทุกข้อ: [`examples/go-app/`](../examples/go-app/) — copy ไปเป็นจุดเริ่มได้เลย

| ต้องมี | ทำไม |
|--------|------|
| ฟัง `:8080` | Traefik ส่ง traffic มาที่ port นี้ |
| `GET /healthz` ตอบ 200 เมื่อพร้อม (ping DB) | rolling deploy รอตัวใหม่ healthy ก่อนสลับ |
| `server migrate` | `deploy.sh` รันก่อนสลับ traffic ทุกครั้ง — ต้องเป็น expand/contract (docs/25) |
| `server seed` รันซ้ำได้ | ข้อมูลพื้นฐาน — `INSERT … ON CONFLICT DO NOTHING` |
| image สุดท้ายเป็น **alpine** | healthcheck + drain ใช้ `sh`, `wget`, `touch` — scratch/distroless ไม่มี |
| binary ที่ `/app/server` | ค่า default ใน `.env` (`DEPLOY_MIGRATE_CMD=/app/server migrate`) |
| รับ SIGTERM → `srv.Shutdown` | request ที่ค้างจบก่อน container หยุด |

ใช้ golang-migrate / goose แทน subcommand ได้ — ใส่ binary ไว้ใน image แล้วแก้ `DEPLOY_MIGRATE_CMD`

## ⚙️ Deploy (ฝั่งเซิร์ฟเวอร์)

```bash
cd /opt/infra-stack
./scripts/create-project.sh myapi go             # + --mysql ถ้า app ใช้ MySQL
./scripts/setup-git.sh myapi <owner>/<repo>      # clone + เปิด build (private → วาง deploy key ใน GitHub)
# เพิ่ม DNS record myapi.<domain> ใน Cloudflare (ก่อน deploy)
./scripts/deploy.sh myapi                        # build → migrate → ถาม seed → rolling
./scripts/smoke.sh myapi
```

ต่อจากนั้น push เข้า `main` → auto-deploy ขึ้นเองใน 2 นาที ([19-cicd.md](19-cicd.md))

## ⚠️ ระวัง

- `DATABASE_URL` มีรหัสผ่าน — อักขระพิเศษต้อง URL-encode (`@` → `%40`)
- seed ห้ามมี user/รหัสตัวอย่าง — deploy ลง production จริง
- `DEPLOY_SEED_PATHS=seeds` = deploy จับว่าไฟล์ใน `/app/seeds` ของ image เปลี่ยน → ถามก่อน seed
  (ตัวอย่าง embed SQL ใน binary และ copy `seeds/` ไว้ใน image ให้จับได้)

## 🧪 ทดสอบ template (ไม่ต้องมี repo — ใช้ตัวอย่าง)

```bash
# เครื่อง dev
cd <infra-stack repo> && git archive --format=tar.gz -o /tmp/go-sample.tar.gz HEAD:examples/go-app
scp /tmp/go-sample.tar.gz deploy@<vps>:/tmp/
# VPS
./scripts/create-project.sh go-sample go
sed -i 's|# build: ./src|build: ./src|' projects/go-sample/docker-compose.yml   # setup-git.sh ทำให้เมื่อใช้ repo จริง
./scripts/load-src.sh go-sample /tmp/go-sample.tar.gz
./scripts/deploy.sh go-sample --seed && ./scripts/smoke.sh go-sample
# ลบทิ้ง: (cd projects/go-sample && docker compose down) && rm -rf projects/go-sample
#        && docker exec postgres psql -U <POSTGRES_USER> -d postgres -c 'DROP DATABASE "go-sample_db";'
```
