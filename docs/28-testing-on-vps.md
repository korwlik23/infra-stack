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
infra check <project>                 # ตรวจครบชุด (อ่านอย่างเดียว)
infra check <project> /login /api/x   # + path เพิ่ม (ต้องได้ < 500)
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
| migration | `infra artisan <p> migrate:status` |
| route / config | `infra artisan <p> route:list` · `infra artisan <p> about` |
| อ่านข้อมูล (นับ/ค้น) | `infra artisan <p> tinker --execute 'echo App\Models\User::count();'` |

## ⚠️ ต้องได้ OK จากเจ้าของก่อน

เปลี่ยนสิ่งที่ผู้ใช้จริงเห็น หรือเขียน database:

| งาน | คำสั่ง |
|-----|--------|
| deploy โค้ดใหม่ | ดูหัวข้อถัดไป |
| seed | `infra deploy <p> --seed` (เติมข้อมูล ไม่ล้าง) |
| rollback | `infra rollback <p>` |
| tinker ที่ create / update / delete | — |
| แก้ `projects/<p>/.env` | `infra env <p>` (แก้แล้วใช้ค่าใหม่ให้เลย — เว็บไม่ดับ) |

### Deploy โค้ดใหม่

project ที่ `src/` เป็น git clone (`setup-git.sh` — ปกติ): **push เข้า `main` = deploy** (auto-deploy ทุก 2 นาที)
— ห้าม push แทนเจ้าของ · ตรวจผล (อ่านอย่างเดียว ทำได้เลย):

```bash
infra logs auto-deploy                             # ✅ ขึ้นแล้ว · ❌ ล้ม (เว็บเดิมยังอยู่) · ⏸ รอเจ้าของตอบเรื่อง seed
cat projects/<p>/.deploy-commit                     # commit ที่ขึ้นเว็บอยู่
```

deploy เดี๋ยวนี้ไม่รอ cron: `infra deploy <p>` (ต้องได้ OK) — project ใหม่จะถาม seed ให้เจ้าของตอบเอง

project ที่ `src/` ยังเป็นไฟล์ copy (ไม่ได้ setup-git):

```bash
# เครื่อง dev — เฉพาะไฟล์ที่ commit แล้ว (branch ที่เจ้าของอนุมัติ ปกติคือ main)
git archive --format=tar.gz -o app.tar.gz HEAD
scp app.tar.gz deploy@<vps>:/tmp/<p>.tar.gz

# VPS
infra load <p> /tmp/<p>.tar.gz    # src/ เดิมเก็บไว้ที่ src.prev/
infra deploy <p> --no-seed            # migrate (ถ้า DEPLOY_MIGRATE=1) + rolling deploy
infra check <p>
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
| โค้ดใหม่พัง | `infra rollback <p>` (image ก่อน deploy ล่าสุด) |
| อยากได้ src เดิมกลับมา build | `mv projects/<p>/src projects/<p>/src.bad && mv projects/<p>/src.prev projects/<p>/src` |
| ข้อมูลเสีย | `infra restore postgres` / `infra restore mysql` ([13-backup.md](13-backup.md)) — ถามเจ้าของก่อนเสมอ |
