# 02 — Security

🎯 ปิดทางเข้า server ให้เหลือเท่าที่จำเป็น ก่อนลงอย่างอื่นทั้งหมด

## ⚙️ ขั้นที่ 0: เตรียม SSH key ก่อนรัน harden (สำคัญกับ Contabo)

> ติดตั้งด้วย `prepare.sh` ([INSTALL.md](INSTALL.md)) ไม่ต้องทำขั้นนี้ — สคริปต์ถามให้วาง public key เอง
> ขั้นนี้สำหรับคนที่อยากส่ง key ขึ้นเครื่องก่อน หรือรัน `harden.sh` แบบไม่มีจอ

Contabo (และ provider ส่วนใหญ่) ให้แค่**รหัสผ่าน root** ไม่มี SSH key มาให้ —
ถ้ารัน `harden.sh` โดยที่เครื่องยังไม่มี key script จะ**ข้ามการปิด password login
โดยตั้งใจ** (กันโดนล็อกออกจากเครื่อง) ดังนั้นเตรียม key ก่อน:

**บนเครื่อง Windows ของเรา:**

```powershell
# 1. สร้าง key (ครั้งเดียวต่อเครื่อง — กด Enter รับค่า default ได้)
ssh-keygen -t ed25519

# 2. ส่ง public key ขึ้น server (เลือกตาม shell ที่ใช้ — ดู prompt)
#    cmd        (working directory: C:\Users\<user>)    → ใช้ %USERPROFILE%
#    PowerShell (working directory: C:\Users\<user>) → ใช้ $env:USERPROFILE

# แบบ cmd:
type %USERPROFILE%\.ssh\id_ed25519.pub | ssh root@<ip> "mkdir -p /root/.ssh && cat >> /root/.ssh/authorized_keys && chmod 700 /root/.ssh && chmod 600 /root/.ssh/authorized_keys"

# แบบ PowerShell:
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh root@<ip> "mkdir -p /root/.ssh && cat >> /root/.ssh/authorized_keys && chmod 700 /root/.ssh && chmod 600 /root/.ssh/authorized_keys"
```

**เช็คบน server ว่า key ถึงจริง** (ห้ามข้ามขั้นนี้):

```bash
cat /root/.ssh/authorized_keys   # ต้องเห็น ssh-ed25519 AAAA... ลงท้ายชื่อเครื่องเรา
```

⚠️ อย่าลบ `C:\Users\<user>\.ssh\id_ed25519` บนเครื่องเด็ดขาด — เป็นกุญแจดอกเดียว
ที่เข้าเครื่องได้ (backup ใส่ password manager ไว้ด้วย)

## ⚙️ วิธีทำ

ปกติ `prepare.sh` เรียกให้ (ช่วง A ของ [INSTALL.md](INSTALL.md)) — รันเองได้:

```bash
sudo ./scripts/harden.sh
```

สิ่งที่ script ทำ (คำถามทั้งหมดอยู่ต้นสคริปต์ ตอบแล้วปล่อยทำงานจนจบ):

1. สร้าง user `deploy` + sudo (เลิกใช้ root) และ**ถามรหัส sudo ของ deploy** (ถ้ารันใน terminal)
2. copy SSH key จาก root → deploy — ถ้าไม่มี key ที่ไหนเลย (login ด้วยรหัสผ่าน) **ถามให้วาง public key**
   และตรวจด้วย `ssh-keygen -l` ก่อนรับ
3. ใส่ deploy ใน group `docker` ไว้ก่อน + ติด Docker — `su - deploy` ต่อได้ทันที ไม่ต้อง logout/login
4. โอน repo ที่ clone ด้วย root ให้ deploy + ลิงก์คำสั่ง `infra` ไว้ที่ `/usr/local/bin`
5. ปิด Root Login + Password Login (เหลือ SSH key เท่านั้น) — แก้ทั้ง `sshd_config` และเขียน
   `/etc/ssh/sshd_config.d/00-infra-hardening.conf` (กัน `50-cloud-init.conf` ของ cloud image
   ที่ตั้ง `PasswordAuthentication yes` มาชนะ) แล้ว `sshd -t` ตรวจก่อน restart
   root login ถูกปิด**เฉพาะเมื่อ deploy มีรหัส sudo แล้ว** — ไม่มีรหัส (รันแบบไม่มีจอ) จะเหลือ root
   เข้าด้วย key ไว้ก่อน กันไม่มี user ไหนได้สิทธิ์ root ผ่าน SSH (เจอจริง 2026-10)
6. UFW: deny ทุกอย่างขาเข้า ยกเว้น SSH / 80 / 443
7. Fail2ban กัน brute force
8. ติดตั้ง `apache2-utils` (`htpasswd`) ไว้ใช้เอง — basicauth ของหน้าแอดมิน `install.sh` สร้างให้แล้ว
9. รัน apt แบบไม่ถาม (`DEBIAN_FRONTEND=noninteractive`, needrestart อัตโนมัติ, เก็บ config เดิม)
   — ไม่มีหน้าจอม่วงเด้งกลางทาง; ข้อความยาวลง `/var/log/infra-prepare.log` ล้มเมื่อไหร่โชว์ท้าย log ให้

## ⚠️ ระวัง (สำคัญที่สุดในเล่มนี้)

- **ก่อนปิด session เดิม** เปิด terminal ใหม่ทดสอบ `ssh deploy@<ip>` ให้เข้าได้ก่อน
  ไม่งั้นล็อกตัวเองออกจากเครื่อง
- ห้าม commit private key / `.env` เข้า Git เด็ดขาด — ดู `.gitignore`
- Database ports (5432, 6379) ไม่เปิดใน UFW — app ต่อผ่าน Docker network เท่านั้น

## ถ้าข้ามการตั้งรหัส sudo ของ deploy

harden.sh ถามรหัสให้แล้ว — ถ้าข้ามไป (หรือรันแบบไม่มีจอ) ท้ายสคริปต์จะเตือนว่ายังไม่ปิด root login
ตั้งรหัสในหน้าต่าง root แล้วรัน `sudo ./scripts/harden.sh` ซ้ำเพื่อปิด root:

```bash
passwd deploy
```

รหัสนี้ใช้กับ `sudo` เท่านั้น — login จากข้างนอกด้วยรหัสผ่านไม่ได้แล้ว
(PasswordAuthentication ถูกปิด) จึงไม่เปิดช่องโหว่เพิ่ม

และโอนสิทธิ์ repo ที่ clone ด้วย root ให้ deploy:

```bash
chown -R deploy:deploy /opt/infra-stack
```

## 🧪 ทดสอบ

```bash
sudo ufw status verbose          # เห็น 22, 80, 443 allow เท่านั้น
sudo fail2ban-client status sshd # มี jail ทำงาน
sudo sshd -T | grep -Ei '^(permitrootlogin|passwordauthentication) '   # ต้องเป็น no ทั้งคู่
ssh deploy@<ip>                  # ต้องเข้าได้โดย "ไม่ถามรหัสผ่าน" (ใช้ key)
ssh root@<ip>                    # ต้องถูกปฏิเสธ
```

## 🩹 ปัญหาที่เจอจริง + วิธีแก้ (จากการติดตั้งครั้งแรก 2026-07)

### 1. `ssh deploy@<ip>` ยังถามรหัสผ่าน

**สาเหตุที่เจอบ่อยสุด:** ส่ง key ขึ้น server ไม่สำเร็จเพราะใช้คำสั่งผิด shell —
รัน syntax PowerShell (`$env:USERPROFILE`) ใน cmd จะได้ error
`The filename, directory name, or volume label syntax is incorrect.`
แล้ว ssh ยังทำงานต่อด้วย **stdin ว่าง** → ได้ authorized_keys เป็น**ไฟล์เปล่า**
โดยไม่รู้ตัว

**วิธีแก้:** ใช้คำสั่งให้ตรง shell (ดูขั้นที่ 0) แล้ว `cat /root/.ssh/authorized_keys`
เช็คว่ามี key จริงทุกครั้ง จากนั้น copy ให้ deploy ใหม่:

```bash
cp /root/.ssh/authorized_keys /home/deploy/.ssh/authorized_keys
chown deploy:deploy /home/deploy/.ssh/authorized_keys
chmod 600 /home/deploy/.ssh/authorized_keys
```

### 2. รัน harden.sh ไปแล้วตอนยังไม่มี key — ต้องทำใหม่ไหม?

ไม่ต้องรื้อ — script ออกแบบให้**รันซ้ำได้** หลังเพิ่ม key ให้ root แล้วรัน
`sudo ./scripts/harden.sh` อีกรอบ — user ที่มีอยู่แล้วถูกข้าม, key ของ root ถูก copy
ให้ deploy (ถ้า deploy ยังไม่มี key) และรอบนี้จะปิด root/password login ให้ครบ

### 3. deploy ใช้ sudo ไม่ได้ (ถามรหัสแต่ไม่มีรหัส)

user ถูกสร้างแบบ disabled-password — ตั้งด้วย `passwd deploy` จากหน้าต่าง root
(ดูหัวข้อ "หลัง harden" ด้านบน)

## 🔄 Rollback

ถ้าล็อกตัวเองออก: ใช้ VNC console ของ provider (Contabo CCP มีให้)
แก้ `/etc/ssh/sshd_config` กลับแล้ว `systemctl restart ssh`
