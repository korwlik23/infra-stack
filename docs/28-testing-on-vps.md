# 28 — ทดสอบ project บน VPS (สำหรับคนและ AI agent)

🎯 ให้ AI agent (Claude Code / Codex) หรือคนที่ไม่คุ้นเครื่อง ตรวจ project ที่ deploy แล้วได้เอง
โดยไม่ทำข้อมูลจริงเสียหาย — อะไรทำได้เลย อะไรต้องถามก่อน อะไรห้าม

🤔 VPS คือ **production** ข้อมูลใน database เป็นของจริง และ image ที่ build เป็นแบบ `--no-dev`
(ไม่มี PHPUnit / Pest / Jest ข้างใน) — "test" บน VPS จึงหมายถึง **smoke test** (เว็บขึ้นไหม, log มี error ไหม,
migration ครบไหม) ส่วน unit/feature test ให้รันบนเครื่อง dev หรือ CI

## ⚙️ ทางเข้า

```bash
ssh deploy@<vps>                 # คำสั่งทั้งหมดรันจาก /opt/infra-stack
cd /opt/infra-stack
```

> Windows: ใช้ `ssh` / `scp` ของ Windows (PowerShell) — คำสั่งยาวที่มี quote ซ้อนให้เขียนเป็นไฟล์ .sh
> แล้ว `scp` ขึ้นไปรัน (`ssh … 'bash /tmp/x.sh'`) แทนการพิมพ์ inline (PowerShell ตัด quote ข้างในทิ้ง)

## 🧪 Smoke test — ทำได้เลย ไม่ต้องถาม

```bash
./scripts/smoke.sh <project>                 # ตรวจครบชุด (อ่านอย่างเดียว)
./scripts/smoke.sh <project> /login /api/x   # + path เพิ่ม (ต้องได้ < 500)
```

ตรวจ: container รันและ healthy · ไม่มี service ค้าง image เก่า · health endpoint ได้ 200 ผ่าน Traefik ·
หน้าแรก < 500 · cert ใช้ได้ · error ใน log 15 นาทีล่าสุด · migration ค้าง (Laravel)
— `exit 1` เมื่อมี ❌ · ยิงผ่าน Traefik ของเครื่องเอง (`--resolve`) จึงใช้ได้แม้ DNS ยังไม่ย้ายมา

คำสั่งอ่านอย่างเดียวอื่น ๆ:

| ต้องการ | คำสั่ง |
|---------|--------|
| log ของ service | `docker compose --project-directory projects/<p> logs --since 30m <p>-app` |
| สถานะ container | `docker compose --project-directory projects/<p> ps` |
| ยิง URL ผ่าน Traefik | `curl -sSI --resolve <domain>:443:127.0.0.1 https://<domain>/path` |
| migration | `./scripts/artisan.sh <p> migrate:status` |
| route / config | `./scripts/artisan.sh <p> route:list` · `./scripts/artisan.sh <p> about` |
| อ่านข้อมูล (นับ/ค้น) | `./scripts/artisan.sh <p> tinker --execute 'echo App\Models\User::count();'` |

## ⚠️ ต้องได้ OK จากเจ้าของก่อน

เปลี่ยนสิ่งที่ผู้ใช้จริงเห็น หรือเขียน database:

| งาน | คำสั่ง |
|-----|--------|
| deploy โค้ดใหม่ | ดูหัวข้อถัดไป |
| seed | `./scripts/deploy.sh <p> --seed` (เติมข้อมูล ไม่ล้าง) |
| rollback | `./scripts/rollback.sh <p> previous` |
| tinker ที่ create / update / delete | — |
| แก้ `projects/<p>/.env` | ตามด้วย `./scripts/deploy.sh <p>` |

### Deploy โค้ดใหม่ (project ที่ `src/` ไม่ใช่ git clone)

```bash
# เครื่อง dev — เฉพาะไฟล์ที่ commit แล้ว (branch ที่เจ้าของอนุมัติ ปกติคือ main)
git archive --format=tar.gz -o app.tar.gz HEAD
scp app.tar.gz deploy@<vps>:/tmp/<p>.tar.gz

# VPS
./scripts/load-src.sh <p> /tmp/<p>.tar.gz    # src/ เดิมเก็บไว้ที่ src.prev/
./scripts/deploy.sh <p> --no-seed            # migrate (ถ้า DEPLOY_MIGRATE=1) + rolling deploy
./scripts/smoke.sh <p>
rm /tmp/<p>.tar.gz
```

`deploy.sh` เป็น rolling deploy: ตัวใหม่ไม่ healthy = ตัวเก่ารับ traffic ต่อ เว็บไม่ดับ
แต่ **migration ที่รันแล้วไม่ย้อนเอง** — migration ต้องเป็น expand/contract ([25-zero-downtime.md](25-zero-downtime.md))

## ⛔ ห้ามบน VPS

- `php artisan test` / `pest` / `phpunit` / `npm test` — test ที่ใช้ `RefreshDatabase` จะ**ล้าง database จริง**
  (และ image production ไม่มี dev dependency อยู่แล้ว)
- `migrate:fresh` · `migrate:reset` · `migrate:rollback` · `db:wipe` · `prisma migrate reset` · `prisma db push --force-reset`
- `docker compose down -v` · `docker volume rm` · `docker system prune --volumes`
- แสดงค่าใน `.env` (รหัส, key) บนจอ / ใน chat / ใน log — อ่านเฉพาะชื่อ key: `cut -d= -f1 projects/<p>/.env`
- login ผ่านหน้าเว็บด้วยรหัสจริงแทนเจ้าของ

## 🔄 Rollback

| พัง | ทำ |
|-----|----|
| โค้ดใหม่พัง | `./scripts/rollback.sh <p> previous` (image ก่อน deploy ล่าสุด) |
| อยากได้ src เดิมกลับมา build | `mv projects/<p>/src projects/<p>/src.bad && mv projects/<p>/src.prev projects/<p>/src` |
| ข้อมูลเสีย | `./scripts/restore.sh` / `mysql-restore.sh` ([13-backup.md](13-backup.md)) — ถามเจ้าของก่อนเสมอ |
