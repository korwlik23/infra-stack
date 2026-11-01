# 19 — CI/CD (ไม่ใช้ GitHub Actions — ฟรี 100%)

🎯 push โค้ด → เว็บอัปเดตเอง โดยไม่จ่ายค่า CI

จะใช้ hosted CI ก็ได้ แต่วิธี build บนเซิร์ฟเวอร์ด้านล่างไม่ผูกกับโควตาของ CI
provider และ image ไม่ต้องเดินทางผ่าน registry

## แนวคิด: Build on Server + Git Poll

```text
push main → GitHub ← (poll ทุก 2 นาที) เซิร์ฟเวอร์
                             │ มี commit ใหม่
                             ▼
       git pull → build → migrate (+ seed) → rolling deploy (drain ตัวเก่า)
```

deploy เฉพาะ branch ที่ clone ไว้ (default `main`) — push branch อื่นไม่ขึ้นเว็บ

## ⚙️ เชื่อม project กับ GitHub (ครั้งเดียวต่อ project)

```bash
cd /opt/infra-stack
./scripts/setup-git.sh <project> <owner>/<repo>          # branch default: main
```

| repo | สิ่งที่ script ทำ |
|------|------------------|
| public | clone ผ่าน https เลย |
| private | สร้าง deploy key `~/.ssh/deploy_<project>` + host alias `github.com-<project>` แล้ว**โชว์ public key + ลิงก์** หน้า Deploy keys ของ repo → ไปกด Add (ไม่ติ๊ก write access) → รันคำสั่งเดิมซ้ำ |

จากนั้น script: clone เข้า `src/` (ของเดิมเก็บที่ `src.prev/`) · ตรวจว่ามี Dockerfile ·
เปิด `build: ./src` · แก้ `APP_IMAGE` ที่ยังเป็น placeholder → `<project>:latest`

```bash
./scripts/deploy.sh <project>      # deploy ครั้งแรกจาก git — เว็บตรงกับ main
./scripts/smoke.sh <project>
```

> host key ของ GitHub อ่านจาก `https://api.github.com/meta` (ผ่าน HTTPS) — ไม่เชื่อ key ที่ ssh เจอครั้งแรกแบบมั่ว ๆ
> 1 deploy key ใช้ได้กับ repo เดียว — GitHub ไม่ให้ใช้ key ซ้ำข้าม repo

## ⚙️ เปิด auto deploy (ครั้งเดียวต่อเครื่อง)

```bash
mkdir -p /opt/infra-stack/logs
crontab -e
```

```cron
*/2 * * * * /opt/infra-stack/scripts/auto-deploy.sh >> /opt/infra-stack/logs/auto-deploy.log 2>&1
```

`auto-deploy.sh` วนทุก project ที่ `src/` เป็น git clone → fetch → ถ้า commit ล่าสุดของ branch
≠ commit ที่ขึ้นเว็บแล้ว (`projects/<ชื่อ>/.deploy-commit`) → `deploy.sh`

| กลไก | ทำไม |
|------|------|
| `flock` — รันทีละรอบ | deploy หนึ่งตัวใช้ 1–2 นาที (build + drain 35s) — cron รอบถัดไปมาก่อนจบได้ |
| เทียบกับ `.deploy-commit` ไม่ใช่ HEAD | deploy.sh `git pull` ก่อน build — build ล้มแล้ว HEAD ก็เป็น commit ใหม่ไปแล้ว |
| commit ที่ล้มจำใน `.deploy-failed` | ไม่ลอง build ซ้ำทุก 2 นาที — รอ commit ใหม่ หรือ `deploy.sh` มือ (ผ่านแล้วล้างให้) |
| seed ไม่รันเอง | ไม่มีคนตอบ — เตือนใน log · ตั้ง `DEPLOY_AUTO_SEED=1` ถ้า seeder รันซ้ำได้แน่ ๆ (docs/25) |

`deploy.sh` เป็น **zero-downtime rolling deploy** (เปิดตัวใหม่รอ healthy → drain ตัวเก่า → ถอด)
ของพังไม่ได้รับ traffic — ดู [25-zero-downtime.md](25-zero-downtime.md)

## ⚠️ ระวัง

- **ทุกอย่างที่เข้า branch ที่ clone ไว้ = ขึ้นเว็บจริง** — ทำงานบน feature branch แล้ว merge เมื่อพร้อม
- Build บนเครื่องกิน CPU/RAM ชั่วคราว — auto-deploy.sh build ทีละตัวอยู่แล้ว
- `src/` ไม่ถูก commit เข้า infra-stack (อยู่ใน .gitignore) — มันเป็น repo ของ app เอง
- migration ต้องเป็น expand/contract ตาม [25-zero-downtime.md](25-zero-downtime.md)
- force-push branch → `git pull --ff-only` ล้ม → deploy ล้ม (กันโค้ดหาย) — แก้: `git -C projects/<ชื่อ>/src reset --hard @{u}` แล้ว deploy มือ

## 🧪 ทดสอบ

```bash
tail -f /opt/infra-stack/logs/auto-deploy.log           # push แล้วดู — ภายใน 2 นาทีต้องเห็น "deploying…" → ✅
cat projects/<ชื่อ>/.deploy-commit                       # commit ที่ขึ้นเว็บอยู่
git -C projects/<ชื่อ>/src log -1 --oneline @{u}          # commit ล่าสุดบน GitHub (หลัง fetch)
```
