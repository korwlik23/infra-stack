# 30 — Security Checklist

## 🎯 เป้าหมาย

รายการเดียวที่บอกว่าเครื่องนี้ "ปลอดภัยพอ" หรือยัง ข้อที่มี 🤖 ให้ `infra audit` ตรวจอัตโนมัติ
ส่วนข้อที่เหลือ script ตรวจไม่ได้ ต้องเช็คเอง

## ⚙️ ตรวจอัตโนมัติ

```bash
infra audit
```

- อ่านอย่างเดียว ไม่แก้อะไร ทุกข้อที่ไม่ผ่านจะบอกคำสั่งแก้ให้
- ข้อ SSH / UFW ต้องใช้ sudo: script ขอรหัส sudo ครั้งเดียว ถ้ากด Enter ว่างจะข้ามข้อพวกนั้น (แสดงเป็น ⏭️)
- ผล: ✅ ผ่าน · ⚠️ ควรแก้ · ❌ ต้องแก้ · exit 1 เมื่อมี ❌
- ไม่พิมพ์รหัสผ่านหรือค่าลับออกมา บอกแค่ชื่อ key

ตรวจทุกสัปดาห์โดยอัตโนมัติ: `infra cron` จะตั้ง `audit.sh --notify` ทุกวันจันทร์ 08:00 ให้ และส่ง Telegram
**เฉพาะเมื่อมี ⚠️ หรือ ❌** (log อยู่ที่ `infra logs audit`) · ใน cron ข้อที่ต้อง sudo จะถูกข้าม
ถ้าต้องการให้ตรวจครบทุกข้อ ให้รัน `infra audit` เองใน terminal เดือนละครั้ง

## ✅ Checklist

### 1. เข้าเครื่อง (SSH)
- [ ] 🤖 root login ปิด (`PermitRootLogin no`)
- [ ] 🤖 login ด้วยรหัสผ่านปิด เหลือ SSH key อย่างเดียว
- [ ] private key บนคอมของคุณมี passphrase และสำรองไว้ใน password manager
- [ ] ลบ public key ของคน/เครื่องที่ไม่ใช้แล้วออกจาก `~/.ssh/authorized_keys` ของ `deploy`
- [ ] รหัส sudo ของ `deploy` จดไว้ใน password manager และไม่ใช้ซ้ำกับที่อื่น

### 2. Firewall
- [ ] 🤖 UFW เปิดอยู่ และ allow แค่ 22 / 80 / 443
- [ ] 🤖 fail2ban ทำงานอยู่
- [ ] 🤖 ไม่มี process อื่นฟัง port จากภายนอก
- [ ] 🤖 มีแค่ Traefik ที่ publish port ของ container ออกไป **Docker publish port ข้าม UFW ได้**:
      `ports: "5432:5432"` ใน compose = เปิดสู่ internet แม้ UFW จะไม่ allow
- [ ] firewall ของ provider (ถ้ามี) เปิดแค่ 22 / 80 / 443 เหมือนกัน

### 3. อัปเดต
- [ ] 🤖 `unattended-upgrades` เปิดอยู่ (security patch ลงเองทุกวัน)
- [ ] 🤖 ไม่มีอัปเดตที่รอ reboot · ไม่มี security update ค้าง
- [ ] 🤖 image ที่รันอยู่อายุไม่เกิน 180 วัน → `infra update <stack>` · project: `infra refresh <ชื่อ>`
- [ ] 🤖 cron `refresh` (PHP/Node/OS ใน image ของ project ได้แพตช์เอง) + `cve-scan` (แจ้ง CVE ที่มีแพตช์) ตั้งแล้ว — docs/31
- [ ] repo ของแอปติดตั้ง Renovate + เปิด Dependabot alerts (library ของแอปได้แพตช์เอง — docs/31)
- [ ] Dockerfile ของ app ใช้ base image ที่ยังได้ security support (เช่น PHP / Node เวอร์ชันที่ยังไม่ EOL)

### 4. รหัสผ่าน + ไฟล์ลับ
- [ ] 🤖 `.env`, `projects/*/.env`, `acme.json`, `auth.yml`, deploy key ได้สิทธิ์ `600`
- [ ] 🤖 `*_PASSWORD` ใน `.env` ตั้งครบ (ไม่มี `CHANGE_ME`) และยาว ≥ 16 ตัว
- [ ] 🤖 ไม่มีไฟล์ลับถูก commit เข้า Git (หลุดแล้วต้อง**เปลี่ยนรหัส**ด้วย ไม่ใช่แค่ลบไฟล์)
- [ ] รหัสหน้าแอดมิน (Portainer, Grafana, pgAdmin, Uptime Kuma, MinIO, RabbitMQ, Beszel) เปลี่ยนจากค่าที่สุ่มไว้ในบันทึก
      หรือเก็บใน password manager แล้ว **ไม่มีใครใช้บัญชีเดียวกันร่วมกัน**
- [ ] Portainer / Grafana เปิด 2FA หรือจำกัดผู้ใช้เท่าที่จำเป็น
- [ ] `BACKUP_ENCRYPTION_PASSWORD` และ R2 key จดไว้นอกเครื่อง (docs/13)

### 5. หน้าเว็บ + หน้าแอดมิน
- [ ] 🤖 มี basicauth กลาง และหน้าที่ไม่มี login ของตัวเอง (Traefik dashboard, Netdata, Dozzle, RedisInsight,
      phpMyAdmin) อยู่หลัง basicauth ทั้งหมด
- [ ] 🤖 cert HTTPS ใช้ได้ทุกโดเมน และเหลืออายุ ≥ 14 วัน
- [ ] ปิด stack ที่ไม่ได้ใช้แล้ว (`infra stop tools` ฯลฯ) — ยิ่งมีหน้าแอดมินน้อย ยิ่งโดนโจมตีได้น้อย
- [ ] หน้าแอดมินอยู่หลัง Cloudflare Access — โดยเฉพาะตัวที่ mount `docker.sock` (Portainer, Dozzle, Netdata) (docs/31)
- [ ] Cloudflare: proxy (เมฆสีส้ม) เปิดสำหรับเว็บ app · SSL mode = **Full (strict)** (docs/11)

### 6. App
- [ ] 🤖 Laravel: `APP_DEBUG=false`, `APP_ENV=production`, มี `APP_KEY`
- [ ] 🤖 Next.js: `NODE_ENV=production`
- [ ] 🤖 database ภายนอก (`--external-db`) ต่อผ่าน TLS (`sslmode=require`)
- [ ] 🤖 container ของ project ไม่มี `privileged` / `docker.sock` (= เป็น root ของเครื่องได้)
- [ ] 🤖 container ของ project ตั้ง `no-new-privileges` (docs/31)
- [ ] 🤖 project ต่อ Postgres ด้วย user ของตัวเอง ไม่ใช่ superuser → `infra db-user <ชื่อ>` (docs/31)
- [ ] 🤖 project ไม่ใช้ R2 key ตัวเดียวกับ backup (docs/31)
- [ ] 🤖 dependency ของ app ไม่มีช่องโหว่ร้ายแรงที่มีแพตช์แล้ว: `infra cve` (ดูใน image ที่รันจริง)
- [ ] ทุกคนที่ push เข้า repo ของแอปได้ เปิด GitHub 2FA (push เข้า main = รันโค้ดบนเซิร์ฟเวอร์)
- [ ] seeder ที่รันบน production ไม่สร้างบัญชีทดสอบหรือรหัส default (docs/25 หัวข้อ seed)
- [ ] หน้า login ของ app มี rate limit (Laravel: `throttle` middleware)

### 7. Backup + แจ้งเตือน
- [ ] 🤖 cron backup ตั้งแล้ว · backup ล่าสุดไม่เก่ากว่า 2 วัน
- [ ] 🤖 backup ส่งออกนอกเครื่อง (R2 / rclone)
- [ ] 🤖 ตั้ง Telegram แล้ว (deploy / backup / audit ล้มจะมีคนรู้)
- [ ] ซ้อม restore ลง VPS ทดลองแล้วอย่างน้อยหนึ่งครั้ง (`infra restore-server` — docs/13)
- [ ] R2 bucket ของ backup **ไม่เปิด public** และ API token ที่ใช้มีสิทธิ์แค่ bucket นั้น
- [ ] bucket ของ backup เปิด Bucket Lock (retention ≥ 30 วัน) — เครื่องโดนยึดก็ลบ backup ไม่ได้ (docs/31)

## 🔁 ทำเมื่อไหร่

| เมื่อ | ทำ |
|-------|----|
| ติดตั้งเสร็จ | `infra audit` ให้ไม่มี ❌ แล้วไล่ข้อที่ไม่มี 🤖 ครบหนึ่งรอบ |
| ทุกวัน | อัตโนมัติ (cron refresh + cve-scan) — Telegram บอกเมื่อมีแพตช์ deploy / CVE ใหม่ (docs/31) |
| ทุกสัปดาห์ | อัตโนมัติ (cron audit) — อ่าน Telegram ถ้ามีข้อความ · กด merge PR ของ Renovate ที่ค้าง |
| ทุกเดือน | `infra audit` ใน terminal (ตรวจครบรวม SSH/UFW) + ข้อ 4, 6 ที่ไม่มี 🤖 |
| คนออกจากทีม | ลบ SSH key ของเขา · เปลี่ยนรหัสหน้าแอดมินและ `DASHBOARD_PASSWORD` (แก้ `.env` แล้ว `./install.sh`) |
| สงสัยว่ารหัสหลุด | เปลี่ยนรหัสใน `.env` ทุกตัวที่เกี่ยว แล้ว restart stack นั้น · ดู `sudo fail2ban-client status sshd` และ `last` |

## 🧪 ทดสอบ

```bash
infra audit; echo "exit=$?"     # exit=0 = ไม่มี ❌
```

## 🔄 Rollback

`infra audit` ไม่แก้อะไร ไม่มีอะไรต้องย้อน · เอา cron รายสัปดาห์ออก: `crontab -e` แล้วลบบรรทัด `audit.sh`
