# 🩹 แก้ปัญหาที่เจอบ่อย

> เรียงตามขั้นของ [INSTALL.md](INSTALL.md) — หาอาการที่ตรงกับที่เห็นบนจอ แล้วทำตาม "วิธีแก้"
> ปัญหาเฉพาะทางของแต่ละโปรแกรมอยู่ในหัวข้อ "🩹 ปัญหาที่เจอจริง" ของบทนั้นๆ ใน `docs/`

## เรื่องทั่วไปก่อน

| อาการ | วิธีแก้ |
|-------|---------|
| พิมพ์คำสั่งแล้วค้าง ไม่ไปไหน | กด `Ctrl + C` เพื่อยกเลิก แล้วอ่านคำสั่งใหม่ว่า copy มาครบไหม |
| อยู่ใน `nano` แล้วออกไม่ได้ | กด `Ctrl + X` → ถ้าถาม `Save modified buffer?` กด `Y` แล้ว Enter (หรือ `N` ถ้าไม่อยากบันทึก) |
| `command not found` | พิมพ์ผิด หรือรันผิดเครื่อง — ดูบรรทัดหน้าคำสั่งว่าเป็น `root@...` / `deploy@...` (VPS) หรือเครื่องตัวเอง |
| `No such file or directory` ตอนรัน `./install.sh` | ยังไม่ได้ `cd /opt/infra-stack` |
| ไม่แน่ใจว่าตอนนี้อยู่เครื่องไหน เป็นใคร | พิมพ์ `whoami` และ `hostname` |

## SSH และการเข้าเครื่อง

### ssh ยังถามรหัสผ่าน

ทั้งที่ส่งกุญแจไปแล้ว (ขั้น 4.3) — สาเหตุที่เจอบ่อยสุดคือ**ใช้คำสั่งผิด shell** เช่น รันคำสั่ง
PowerShell ใน cmd จะได้ error `The filename, directory name, or volume label syntax is incorrect.`
แต่ ssh ยังทำงานต่อด้วยข้อมูลว่าง → ได้ไฟล์กุญแจเปล่าบนเซิร์ฟเวอร์โดยไม่รู้ตัว

**วิธีแก้:**

1. login ด้วยรหัสผ่าน root แล้วเช็คไฟล์:

   ```bash
   cat /root/.ssh/authorized_keys
   ```

   ต้องเห็นบรรทัดขึ้นต้นด้วย `ssh-ed25519 AAAA...` — ถ้าว่างหรือไม่มีไฟล์ แปลว่ากุญแจไม่ถึง
2. `exit` กลับเครื่องตัวเอง → ทำขั้น 4.3 ใหม่ โดย**เปิด Windows PowerShell** (ไม่ใช่ Command Prompt)
3. ถ้าเคยรัน `harden.sh` ไปแล้ว ให้ copy กุญแจให้ deploy ด้วย (รันเป็น root):

   ```bash
   cp /root/.ssh/authorized_keys /home/deploy/.ssh/authorized_keys
   chown deploy:deploy /home/deploy/.ssh/authorized_keys
   chmod 600 /home/deploy/.ssh/authorized_keys
   ```

### ssh deploy@IP เข้าไม่ได้

ขึ้น `Permission denied (publickey)` หลังรัน `harden.sh`

- **อย่าปิดหน้าต่าง root ที่ยังเปิดอยู่** — ใช้มันแก้
- ในหน้าต่าง root รัน 3 คำสั่งในหัวข้อ [ssh ยังถามรหัสผ่าน](#ssh-ยังถามรหัสผ่าน) ข้อ 3
  แล้วลอง `ssh deploy@<IP>` จากหน้าต่างใหม่อีกครั้ง
- เครื่องตัวเองมีหลายกุญแจ? ระบุไฟล์ตรงๆ: `ssh -i ~/.ssh/id_ed25519 deploy@<IP>`

### ล็อกตัวเองออกจากเครื่องแล้ว (ปิดหน้าต่าง root ไปแล้วเข้าไม่ได้เลย)

ใช้ **console ของผู้ให้บริการ** (Contabo: Customer Control Panel → VNC; Hetzner: Console;
DigitalOcean: Droplet → Access → Console) — เป็นหน้าจอเครื่องโดยตรง ไม่ผ่าน SSH
login เป็น root ด้วยรหัสผ่าน แล้วแก้ตามหัวข้อ [ssh ยังถามรหัสผ่าน](#ssh-ยังถามรหัสผ่าน) ข้อ 3

### `WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!`

เกิดเมื่อติดตั้ง OS ใหม่บน VPS เดิม (IP เดิม แต่เครื่อง "ใหม่") — ถ้าคุณเพิ่ง reinstall เอง ปลอดภัย
ลบลายนิ้วมือเก่าบนเครื่องตัวเอง:

```bash
ssh-keygen -R <IP ของ VPS>
```

ถ้า**ไม่ได้** reinstall อะไรเลย อย่าเพิ่ง login — ติดต่อผู้ให้บริการก่อน

### `Connection timed out` / `Connection refused`

- เช็ค IP ว่าพิมพ์ถูก
- เครื่องเพิ่งสร้าง/รีบูต → รอ 2–3 นาที
- ผู้ให้บริการบางเจ้ามี firewall ที่หน้าเว็บ (Hetzner Firewall, Oracle Security List) — เปิด port 22, 80, 443

## ขั้น harden

| อาการ | วิธีแก้ |
|-------|---------|
| `no SSH key found for deploy ... skipping SSH hardening` | root ยังไม่มีกุญแจ → ทำขั้น 4.3–4.4 แล้วรัน `./scripts/harden.sh` ซ้ำ (รันซ้ำได้) |
| `run as root: sudo ./scripts/harden.sh` | กำลังรันเป็น deploy → ใส่ `sudo` ข้างหน้า หรือ login เป็น root |
| `fatal: destination path '/opt/infra-stack' already exists` | clone ไว้แล้ว → `cd /opt/infra-stack && git pull` แทน |
| deploy ใช้ `sudo` แล้วถามรหัส แต่ไม่รู้รหัส | ยังไม่ได้ตั้ง → จากหน้าต่าง root (หรือ console): `passwd deploy` |
| หน้าจอสีม่วง/น้ำเงินถามว่า restart service ไหน | ปกติ harden.sh ปิดไว้แล้ว ถ้ายังเจอ กด Enter (ค่า default) ได้เลย |

## ขั้น install.sh

| อาการ | วิธีแก้ |
|-------|---------|
| `permission denied while trying to connect to the Docker daemon socket` | ยังไม่ได้ออกแล้ว login ใหม่หลังรอบที่ 1 → `exit` → `ssh deploy@<IP>` → `cd /opt/infra-stack && ./install.sh` |
| `ERROR: BASE_DOMAIN ใน .env ยังเป็นค่า default` | แก้ `.env` ยังไม่ได้บันทึก → `nano .env` แก้ใหม่ แล้วกด `Ctrl + O` → Enter → `Ctrl + X` |
| `ERROR: ACME_EMAIL ใน .env ยังเป็นค่า default` | เหมือนข้อบน — อีเมลห้ามลงท้าย `@example.com` |
| `❌ portainer.<โดเมน>` + `ERROR: ยังไม่มี DNS record` | สร้าง record ที่ขาดใน Cloudflare (INSTALL ขั้นที่ 5) รอ 5 นาที แล้วรันซ้ำ — ถ้าเพิ่งย้าย nameserver อาจต้องรอหลายชั่วโมง เช็คว่าโดเมนเป็น Active ก่อน |
| `⚠️ ไม่ได้สุ่ม: POSTGRES_PASSWORD ...` | เครื่องนี้เคยติดตั้งมาก่อนและมีข้อมูลเดิม — ใส่รหัสเดิมใน `.env` เอง (สุ่มใหม่จะเข้าฐานข้อมูลเดิมไม่ได้) |
| ใส่รหัส sudo แล้วขึ้น `Sorry, try again` | พิมพ์ผิด (มองไม่เห็นตอนพิมพ์) — ลองใหม่ช้าๆ ถ้าลืมให้ตั้งใหม่ด้วย `passwd deploy` จาก root |

## เปิดหน้าเว็บในเบราว์เซอร์

ก่อนอื่นดู log ของ Traefik (ตัวที่ขอใบรับรอง):

```bash
docker logs traefik --tail 50
```

| อาการในเบราว์เซอร์ | สาเหตุ / วิธีแก้ |
|--------------------|------------------|
| "Your connection is not private" / `NET::ERR_CERT_...` | ใบรับรองยังไม่ออก — รอ 1–2 นาทีแล้ว Refresh ถ้ายังเป็น ดู log ข้างบนหา `acme` |
| log มี `429` / `too many failed authorizations` | Let's Encrypt แบนชั่วคราวเพราะขอซ้ำตอนไม่มี DNS — สร้าง DNS ให้ครบ แล้ว**รอ 1 ชั่วโมง** ห้ามรันซ้ำระหว่างรอ |
| log มี `NXDOMAIN` | ไม่มี DNS record ของชื่อนั้น → สร้างตามขั้นที่ 5 |
| "This site can't be reached" / `DNS_PROBE_FINISHED_NXDOMAIN` | DNS ยังไม่มีหรือยังไม่กระจาย → `nslookup <ชื่อ>.<โดเมน>` จากเครื่องตัวเอง |
| `ERR_TOO_MANY_REDIRECTS` | Cloudflare SSL ตั้งเป็น Flexible → เปลี่ยนเป็น **Full (strict)** (INSTALL ขั้น 2.4) |
| Cloudflare error **526** Invalid SSL certificate | เปิดเมฆส้มตอนเครื่องยังไม่มีใบรับรอง → เปลี่ยน record เป็น**เมฆเทา**รอใบรับรองออก แล้วค่อยเปิดส้ม |
| `404 page not found` ทุกโดเมน | Traefik มองไม่เห็น container — ดู log หา `client version ... is too old` แล้วแก้ตาม [04-traefik.md](04-traefik.md) |
| เบราว์เซอร์เด้งกล่องถาม username/password | ปกติ — ใช้ `DASHBOARD_USER` / `DASHBOARD_PASSWORD` (`grep DASHBOARD .env`) |

## Portainer

| อาการ | วิธีแก้ |
|-------|---------|
| ขึ้นว่า timed out / ให้ restart instance | เกิน 5 นาทีแล้ว → `docker restart portainer` แล้วรีบสร้างบัญชีภายใน 5 นาที |
| ถาม Setup token | `docker logs portainer 2>&1 \| grep -i token` — ใช้ token **ตัวล่าสุด** (ออกใหม่ทุกครั้งที่ restart) |

## ฐานข้อมูล

| อาการ | วิธีแก้ |
|-------|---------|
| STATUS ค้างที่ `starting` นานเกิน 2 นาที หรือเป็น `unhealthy` | ดูสาเหตุ: `docker logs postgres --tail 30` หรือ `docker logs redis --tail 30` |
| log postgres มี `password authentication failed` | รหัสใน `.env` ไม่ตรงกับที่ฐานข้อมูลจำไว้ตอนสร้างครั้งแรก — ใส่รหัสเดิมกลับใน `.env` |

## ลืมรหัสผ่าน

| รหัสของ | ดูหรือเปลี่ยน |
|---------|---------------|
| หน้า Traefik / Netdata / Dozzle / Redis Insight | ดู: `grep DASHBOARD .env` · เปลี่ยน: แก้ `DASHBOARD_PASSWORD` ใน `.env` แล้ว `./install.sh` |
| Grafana | ดู: `grep GRAFANA .env` — ถ้าเคยเปลี่ยนในหน้าเว็บแล้วลืม: `docker exec grafana grafana cli admin reset-admin-password <รหัสใหม่>` |
| Portainer / Uptime Kuma / Beszel | ตั้งเองตอนสร้างบัญชี ไม่ได้อยู่ใน `.env` — ดูคู่มือของโปรแกรมนั้นใน `services/<ชื่อ>/README.md` |
| sudo ของ deploy | ตั้งใหม่จาก root หรือ console ของผู้ให้บริการ: `passwd deploy` |

> ⚠️ แก้ `GRAFANA_ADMIN_PASSWORD` / `POSTGRES_PASSWORD` ใน `.env` หลังติดตั้งแล้ว**ไม่ได้เปลี่ยนรหัสจริง**
> — โปรแกรมพวกนี้จำรหัสไว้ตั้งแต่เปิดครั้งแรก

## ยังแก้ไม่ได้

รวบรวมข้อมูลนี้ก่อนถามคนอื่น (**ลบรหัสผ่านออกก่อนส่งให้ใครเสมอ**):

```bash
cat VERSION
docker ps -a
docker logs traefik --tail 50
```

พร้อมบอกว่าทำถึงขั้นไหนของ [INSTALL.md](INSTALL.md) และข้อความ error ที่เห็นบนจอ
