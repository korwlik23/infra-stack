# 19 — CI/CD (ไม่ใช้ GitHub Actions — ฟรี 100%)

🎯 push โค้ด → เว็บอัปเดตเอง โดยไม่จ่ายค่า CI

จะใช้ hosted CI ก็ได้ แต่วิธี build บนเซิร์ฟเวอร์ด้านล่างไม่ผูกกับโควตาของ CI
provider และ image ไม่ต้องเดินทางผ่าน registry

## แนวคิด: Build on Server + Git Poll

```text
push → GitHub ← (poll ทุก 2 นาที) เซิร์ฟเวอร์
                        │ มี commit ใหม่
                        ▼
              git pull → docker compose build → up -d
```

## ⚙️ Setup ต่อ project

```bash
# 1. clone source ของ app ไว้ใน project (ผ่าน SSH deploy key แบบ read-only — ดูหัวข้อล่าง)
#    ใช้ host alias "github.com-app" จาก ~/.ssh/config เพื่อให้ ssh ใช้ deploy key ของ repo นี้
cd projects/app
git clone git@github.com-app:<github-user>/<repo>.git src

# 2. เปิดโหมด build ใน docker-compose.yml ของ project
#    (uncomment บรรทัด "build: ./src" — ทุก template มีเตรียมไว้)
#    และตั้ง APP_IMAGE ใน .env เป็นชื่อ image ที่ถูกต้อง เช่น app:latest
#    (placeholder ghcr.io/<github-user>/… มี < > → build ล้ม "invalid reference format")

# 3. deploy ครั้งแรก
cd ../.. && ./scripts/deploy.sh app
```

## ⚙️ เปิด auto deploy

⚠️ สร้างไฟล์ log ก่อน (deploy เขียนไฟล์ใหม่ใน /var/log เองไม่ได้ — cron จะล้มเงียบ):

```bash
sudo touch /var/log/infra-deploy.log && sudo chown deploy:deploy /var/log/infra-deploy.log
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
ssh-keygen -t ed25519 -f ~/.ssh/deploy_app -N ""
cat ~/.ssh/deploy_app.pub
# GitHub → repo → Settings → Deploy keys → Add (ไม่ติ๊ก write access)
cat >> ~/.ssh/config <<'EOF'
Host github.com-app
  HostName github.com
  User git
  IdentityFile ~/.ssh/deploy_app
  IdentitiesOnly yes
EOF
ssh -T git@github.com-app      # ต้องเห็น "successfully authenticated"
```

1 deploy key ใช้ได้กับ repo เดียว — repo ถัดไปสร้าง key + Host alias ใหม่ (เช่น `github.com-shop`)

## ⚠️ ระวัง

- Build บนเครื่องกิน CPU/RAM ชั่วคราว — เครื่อง 8GB build Next.js ได้ แต่อย่า build
  พร้อมกันหลายตัว (auto-deploy.sh รันทีละตัวอยู่แล้ว)
- `src/` ไม่ถูก commit เข้า infra-stack (อยู่ใน .gitignore) — มันเป็น repo ของ app เอง
- เปิด migration อัตโนมัติด้วย `DEPLOY_MIGRATE=1` เฉพาะ project ที่ใช้
  expand/contract migrations ตาม [25-zero-downtime.md](25-zero-downtime.md)

## 🧪 ทดสอบ

```bash
./scripts/deploy.sh <name>            # deploy มือผ่านก่อน
tail -f /var/log/infra-deploy.log     # ดู auto-deploy ทำงาน
```
