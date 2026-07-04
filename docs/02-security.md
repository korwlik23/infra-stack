# 02 — Security

🎯 ปิดทางเข้า server ให้เหลือเท่าที่จำเป็น ก่อนลงอย่างอื่นทั้งหมด

## ⚙️ ขั้นที่ 0: เตรียม SSH key ก่อนรัน harden (สำคัญกับ Contabo)

Contabo (และ provider ส่วนใหญ่) ให้แค่**รหัสผ่าน root** ไม่มี SSH key มาให้ —
ถ้ารัน `harden.sh` โดยที่เครื่องยังไม่มี key script จะ**ข้ามการปิด password login
โดยตั้งใจ** (กันโดนล็อกออกจากเครื่อง) ดังนั้นเตรียม key ก่อน:

**บนเครื่อง Windows ของเรา:**

```powershell
# 1. สร้าง key (ครั้งเดียวต่อเครื่อง — กด Enter รับค่า default ได้)
ssh-keygen -t ed25519

# 2. ส่ง public key ขึ้น server (เลือกตาม shell ที่ใช้ — ดู prompt)
#    cmd        (prompt: C:\Users\kil>)      → ใช้ %USERPROFILE%
#    PowerShell (prompt: PS C:\Users\kil>)   → ใช้ $env:USERPROFILE

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

```bash
sudo ./scripts/harden.sh
```

สิ่งที่ script ทำ:

1. สร้าง user `deploy` + sudo (เลิกใช้ root)
2. copy SSH key จาก root → deploy
3. ปิด Root Login + Password Login (เหลือ SSH key เท่านั้น)
4. UFW: deny ทุกอย่างขาเข้า ยกเว้น SSH / 80 / 443
5. Fail2ban กัน brute force

## ⚠️ ระวัง (สำคัญที่สุดในเล่มนี้)

- **ก่อนปิด session เดิม** เปิด terminal ใหม่ทดสอบ `ssh deploy@<ip>` ให้เข้าได้ก่อน
  ไม่งั้นล็อกตัวเองออกจากเครื่อง
- ห้าม commit private key / `.env` เข้า Git เด็ดขาด — ดู `.gitignore`
- Database ports (5432, 6379) ไม่เปิดใน UFW — app ต่อผ่าน Docker network เท่านั้น

## หลัง harden: ตั้งรหัส sudo ให้ deploy

user `deploy` ถูกสร้างแบบ**ไม่มีรหัสผ่าน** (login ใช้ SSH key เท่านั้น) แต่คำสั่ง
`sudo` ยังต้องใช้รหัส — ตั้งในหน้าต่าง root ก่อนปิด:

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

ไม่ต้องรื้อ — script ออกแบบให้**รันซ้ำได้** หลังเพิ่ม key แล้วรัน
`./scripts/harden.sh` อีกรอบ ส่วนที่ทำไปแล้วถูกข้าม และรอบนี้จะปิด
root/password login ให้ครบ

### 3. deploy ใช้ sudo ไม่ได้ (ถามรหัสแต่ไม่มีรหัส)

user ถูกสร้างแบบ disabled-password — ตั้งด้วย `passwd deploy` จากหน้าต่าง root
(ดูหัวข้อ "หลัง harden" ด้านบน)

## 🔄 Rollback

ถ้าล็อกตัวเองออก: ใช้ VNC console ของ provider (Contabo CCP มีให้)
แก้ `/etc/ssh/sshd_config` กลับแล้ว `systemctl restart ssh`
