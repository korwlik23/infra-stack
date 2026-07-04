# 19 — CI/CD (ไม่ใช้ GitHub Actions — ฟรี 100%)

🎯 push โค้ด → เว็บอัปเดตเอง โดยไม่จ่ายค่า CI

🤔 **เรื่องค่าใช้จ่าย GitHub Actions**: จริง ๆ ฟรีสำหรับ public repo และ private repo
ได้ฟรี 2,000 นาที/เดือน — แต่วิธี build บนเซิร์ฟเวอร์เองด้านล่างนี้**ไม่พึ่งอะไรเลย**
ไม่มีเพดานนาที และ image ไม่ต้องเดินทางผ่าน registry

## แนวคิด: Build on Server + Git Poll

```text
push → GitHub ← (poll ทุก 2 นาที) เซิร์ฟเวอร์
                        │ มี commit ใหม่
                        ▼
              git pull → docker compose build → up -d
```

## ⚙️ Setup ต่อ project

```bash
# 1. clone source ของ app ไว้ใน project (ผ่าน SSH deploy key แบบ read-only)
cd projects/zennuaflow
git clone git@github.com:korwlik23/zennuaflow.git src

# 2. เปิดโหมด build ใน docker-compose.yml ของ project
#    (uncomment บรรทัด "build: ./src" — ทุก template มีเตรียมไว้)

# 3. deploy ครั้งแรก
cd ../.. && ./scripts/deploy.sh zennuaflow
```

## ⚙️ เปิด auto deploy

```bash
crontab -e
```

```cron
*/2 * * * * /opt/infra-stack/scripts/auto-deploy.sh >> /var/log/infra-deploy.log 2>&1
```

`auto-deploy.sh` วนทุก project ที่มี `src/` → fetch → ถ้ามี commit ใหม่ → `deploy.sh`

`deploy.sh` เป็น **zero-downtime rolling deploy** อัตโนมัติ (เปิดตัวใหม่รอ healthy
ก่อนถอดตัวเก่า — ของพังไม่ได้รับ traffic) — ดู [25-zero-downtime.md](25-zero-downtime.md)

## Deploy key (read-only — ปลอดภัยกว่าใช้ key ส่วนตัว)

```bash
ssh-keygen -t ed25519 -f ~/.ssh/deploy_zennuaflow -N ""
# GitHub → repo → Settings → Deploy keys → Add (ไม่ติ๊ก write access)
# ~/.ssh/config:  Host github.com-zennuaflow → IdentityFile ~/.ssh/deploy_zennuaflow
```

## ⚠️ ระวัง

- Build บนเครื่องกิน CPU/RAM ชั่วคราว — เครื่อง 8GB build Next.js ได้ แต่อย่า build
  พร้อมกันหลายตัว (auto-deploy.sh รันทีละตัวอยู่แล้ว)
- `src/` ไม่ถูก commit เข้า infra-stack (อยู่ใน .gitignore) — มันเป็น repo ของ app เอง
- migrate database ไม่ auto — schema เปลี่ยนให้ deploy มือ + migrate เอง

## 🧪 ทดสอบ

```bash
./scripts/deploy.sh <name>            # deploy มือผ่านก่อน
tail -f /var/log/infra-deploy.log     # ดู auto-deploy ทำงาน
```
