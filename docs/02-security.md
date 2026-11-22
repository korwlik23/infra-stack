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

## 🔑 เข้าเครื่องด้วยชื่อสั้น: `ssh mainvps`

แทนที่จะพิมพ์ `ssh -i "C:\Users\<user>\.ssh\<key>" deploy@<ip>` ทุกครั้ง (พิมพ์ path ผิดนิดเดียว →
ssh ไม่ใช้ key → ถามรหัส → fail2ban แบน — ดูปัญหาข้อ 4) ตั้งชื่อเล่นให้เครื่องไว้ในไฟล์ `~/.ssh/config`
ครั้งเดียว แล้วพิมพ์แค่ `ssh mainvps`

### ทำบน PC เครื่องที่เข้า VPS ได้อยู่แล้ว (มีไฟล์ key แล้ว)

**1. ดูชื่อไฟล์ key ที่มี** (PowerShell):

```powershell
dir $env:USERPROFILE\.ssh
```

ไฟล์ที่**ไม่มี** `.pub` คือกุญแจลับ (เช่น `id_ed25519` หรือ `id_ed25519_mainvps`) — จดชื่อไว้

**2. เปิดไฟล์ config** (ยังไม่มี Notepad จะถามว่าสร้างใหม่ไหม → Yes):

```powershell
notepad $env:USERPROFILE\.ssh\config
```

**3. วางข้อความนี้** — แก้ `<IP ของ VPS>` และชื่อไฟล์ key ให้ตรงของตัวเอง แล้ว Save (Ctrl+S):

```
Host mainvps
    HostName <IP ของ VPS>
    User deploy
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
```

| บรรทัด | ความหมาย |
|--------|---------|
| `Host mainvps` | ชื่อเล่นที่จะพิมพ์ — ตั้งอะไรก็ได้ (`Host mainvps vps1` = ใช้ได้ 2 ชื่อ) |
| `HostName` | IP จริงของ VPS |
| `User` | user ที่ใช้ login (`deploy` หลังรัน harden) |
| `IdentityFile` | path ของกุญแจลับ — `~` = `C:\Users\<user>` (ใช้ได้บน Windows ด้วย) |
| `IdentitiesOnly yes` | ใช้ key นี้ตัวเดียว ไม่ลองทุก key ที่มี (ลองหลายตัว = นับเป็น login พลาด → โดนแบนได้) |

> ⚠️ ชื่อไฟล์ต้องเป็น `config` เฉยๆ **ไม่มี `.txt`** — ถ้า Save แล้วได้ `config.txt` ให้เปลี่ยนชื่อ:
> `ren $env:USERPROFILE\.ssh\config.txt config`
> และห้ามสร้างด้วย `Set-Content -Encoding utf8` / `Out-File` ใน PowerShell 5.1 — ได้ไฟล์ที่มี BOM
> แล้ว ssh ขึ้น `Bad configuration option` (Notepad ของ Windows 10/11 บันทึกแบบไม่มี BOM — ใช้ได้)

**4. เช็คว่า ssh อ่านถูก แล้วเข้า:**

```powershell
ssh -G mainvps | findstr /b /c:"hostname " /c:"user " /c:"identityfile "
ssh mainvps
```

`ssh -G` ไม่ได้ต่อเครื่องจริง แค่แสดงค่าที่จะใช้ — ต้องเห็น IP / `deploy` / path key ถูกต้อง
มีหลายเครื่อง → เพิ่มก้อน `Host ...` ต่อท้ายไฟล์เดียวกันได้เลย (เว้นบรรทัดคั่น)

**Mac / Linux:** ไฟล์เดียวกันที่ `~/.ssh/config` (`nano ~/.ssh/config`) แล้ว `chmod 600 ~/.ssh/config`

### ทำบน PC เครื่องใหม่ (ยังไม่มี key ของ VPS)

server ปิด password login แล้ว — PC ใหม่ต้องมี key ที่ server รู้จักก่อน ถึงจะเข้าได้ เลือกทางเดียว:

**ทาง A — สร้าง key ใหม่ให้ PC นี้ (แนะนำ: เครื่องหาย/ขาย ลบ key ของเครื่องนั้นทิ้งได้ตัวเดียว)**

1. บน **PC ใหม่** สร้าง key แล้วแสดง public key:

   ```powershell
   ssh-keygen -t ed25519 -f $env:USERPROFILE\.ssh\id_ed25519_mainvps
   type $env:USERPROFILE\.ssh\id_ed25519_mainvps.pub
   ```

   copy บรรทัด `ssh-ed25519 AAAA...` ทั้งบรรทัด — ไฟล์ `.pub` เปิดเผยได้ ส่งผ่านแชท/อีเมลหาตัวเองได้
2. บน **PC เครื่องเดิมที่เข้าได้** (หรือ VNC console ของ provider) เพิ่ม key นั้นให้ server:

   ```bash
   ssh mainvps
   echo '<วาง ssh-ed25519 AAAA... ทั้งบรรทัด>' >> ~/.ssh/authorized_keys
   ```

3. กลับมา **PC ใหม่** ทำขั้น 2–4 ของหัวข้อด้านบน โดยใช้ `IdentityFile ~/.ssh/id_ed25519_mainvps`

**ทาง B — copy กุญแจเดิมไปใช้**

copy ไฟล์กุญแจลับ (ไม่มี `.pub`) ไปไว้ที่ `C:\Users\<user>\.ssh\` ของ PC ใหม่ ผ่าน **USB / password manager
เท่านั้น** — ห้ามส่งทาง LINE / อีเมล / Google Drive ที่แชร์ (ใครได้ไฟล์นี้ = เข้า server ได้)
แล้วทำขั้น 2–4 ด้านบน ถ้า ssh ขึ้น `UNPROTECTED PRIVATE KEY FILE` / `bad permissions` ให้ล็อกสิทธิ์ไฟล์:

```powershell
icacls $env:USERPROFILE\.ssh\<ชื่อไฟล์ key> /inheritance:r /grant:r "$($env:USERNAME):R"
```

**เลิกใช้ PC เครื่องไหน** → บน server ลบบรรทัด key ของเครื่องนั้นออกจาก `~/.ssh/authorized_keys`
(`nano ~/.ssh/authorized_keys` — ท้ายบรรทัดมีชื่อเครื่องที่สร้าง key บอกอยู่)

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

### 4. `Connection timed out` ทั้งที่เครื่องเปิดอยู่ — โดน fail2ban แบน IP (เจอจริง 2026-11)

**อาการ:** `ssh ... port 22: Connection timed out` แต่ ping เครื่องได้ / เว็บบนเครื่องยังเปิดได้
และก่อนหน้านั้นเคยเห็น `Warning: Identity file ... not accessible` (path key ผิด เช่นพิมพ์
`C:\Users\<user>.ssh\...` ขาด `\` หน้า `.ssh`)

**สาเหตุ:** path key ผิด → ssh ไม่ได้ส่ง key → server ปฏิเสธ (หรือถามรหัสแล้วพิมพ์ผิด) ซ้ำหลายรอบ →
fail2ban นับเป็นการเดารหัส **แบน IP เรา** (default: พลาด 5 ครั้งใน 10 นาที = แบน 10 นาที) ช่วงที่โดนแบน
server เงียบใส่ → ขึ้น timeout แม้แก้ path ถูกแล้ว (และลองซ้ำระหว่างโดนแบน = ยืดเวลาแบน)

**เช็คจาก Windows** — port 22 ต้อง `False` แต่ ping `True`:

```powershell
Test-NetConnection <IP ของ VPS> -Port 22
```

**วิธีแก้** — เลือกทางเดียว:

- รอ 15 นาทีโดย**ไม่ลอง ssh เลย** แล้วลองใหม่ด้วย path ที่ถูก (หรือ `ssh mainvps` — ดูหัวข้อด้านบน)
- หรือเข้าจาก IP อื่น (hotspot มือถือ) / VNC console แล้วปลดแบน:

  ```bash
  sudo fail2ban-client status sshd                    # ดู "Banned IP list"
  sudo fail2ban-client set sshd unbanip 203.0.113.10  # ใส่ IP จากรายการ — ไม่ต้องพิมพ์ < >
  ```

**กันไม่ให้เกิดอีก:** ใช้ `~/.ssh/config` + `IdentitiesOnly yes` (หัวข้อ `ssh mainvps` ด้านบน) — ไม่ต้องพิมพ์ path
อีก ไม่แนะนำใส่ IP บ้านใน `ignoreip` ของ fail2ban — IP บ้านในไทยส่วนใหญ่เปลี่ยนเรื่อยๆ (dynamic)

> ถ้า `ssh` ผ่าน hotspot แล้ว**ถามรหัสผ่านของ deploy และเข้าได้** = password login ยังเปิดอยู่
> (harden ยังไม่ได้ปิด เพราะตอนรันยังไม่มี key) — ทดสอบ `ssh -o PasswordAuthentication=no mainvps`
> ให้เข้าได้ก่อน แล้วรัน `sudo ./scripts/harden.sh` ซ้ำ (ข้อ 2) เพื่อปิด

## 🛡️ อัปเดต kernel (ช่องโหว่ kernel)

`unattended-upgrades` ลง security update ให้ทุกวัน แต่**ไม่ reboot** — kernel ใหม่ใช้จริงหลัง reboot เท่านั้น

```bash
sudo apt update && sudo apt full-upgrade -y
cat /var/run/reboot-required 2>/dev/null && sudo reboot   # เว็บดับ ~1–2 นาที
uname -r                                                   # ต้องเป็นเวอร์ชันที่ประกาศว่าแก้แล้ว
```

เทียบกับประกาศของ Ubuntu (`ubuntu.com/security/CVE-…`) ไม่ใช่เลขเวอร์ชันของ kernel.org —
Ubuntu ใส่ patch ลง kernel สายของตัวเอง (24.04 = 6.8.x) เลขจึงดูเก่ากว่าแต่แก้แล้วได้

**CVE-2026-98432** (TCP use-after-free, CVSS 9.8, 2026-10): exploit ที่ได้ root ใช้ listener แบบ MPTCP —
Traefik (Go ≥ 1.24) เปิด MPTCP เอง → compose ของ Traefik ตั้ง `net.mptcp.enabled=0` ไว้แล้ว
(ค่านี้แยกตาม network namespace — ตั้งบน host อย่างเดียวไม่ถึง container) เป็นการลดความเสี่ยงเท่านั้น
ยังต้องอัปเดต kernel ที่แก้แล้ว (24.04: `6.8.0-149` ขึ้นไป) + reboot · ตรวจ: `docker exec traefik cat /proc/sys/net/mptcp/enabled` = `0`

## 🔄 Rollback

ถ้าล็อกตัวเองออก: ใช้ VNC console ของ provider (Contabo CCP มีให้)
แก้ `/etc/ssh/sshd_config` กลับแล้ว `systemctl restart ssh`

## 🛡️ ตรวจซ้ำหลังติดตั้ง

`infra audit` ตรวจทุกข้อในบทนี้ (และอีกหลายอย่าง — อัปเดต, ไฟล์ลับ, หน้าแอดมิน, cert, backup) แบบอ่านอย่างเดียว
checklist เต็ม: [30-security-checklist.md](30-security-checklist.md)
