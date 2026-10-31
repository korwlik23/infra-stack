# 🩹 แก้ปัญหาที่เจอบ่อย

> เรียงตามขั้นของ [INSTALL.md](INSTALL.md) — หาอาการที่ตรงกับที่เห็นบนจอ แล้วทำตาม "วิธีแก้"
> ปัญหาเฉพาะทางของแต่ละโปรแกรมอยู่ในหัวข้อ "🩹 ปัญหาที่เจอจริง" ของบทนั้นๆ ใน `docs/`

## เรื่องทั่วไปก่อน

| อาการ | วิธีแก้ |
|-------|---------|
| พิมพ์คำสั่งแล้วค้าง ไม่ไปไหน | กด `Ctrl + C` เพื่อยกเลิก แล้วอ่านคำสั่งใหม่ว่า copy มาครบไหม |
| อยู่ใน `nano` แล้วออกไม่ได้ | กด `Ctrl + X` → ถ้าถาม `Save modified buffer?` กด `Y` แล้ว Enter (หรือ `N` ถ้าไม่อยากบันทึก) |
| สคริปต์ขึ้น `❌ ล้มที่: …` | บรรทัดใต้นั้นคือสาเหตุ (ท้าย log 20 บรรทัด) — แก้ตามหัวข้อด้านล่าง แล้ววางคำสั่งเดิมซ้ำ ขั้นที่เสร็จแล้วจะถูกข้าม · log เต็ม: ช่วง A `/var/log/infra-prepare.log`, ช่วง B `/opt/infra-stack/install.log` |
| เน็ตหลุด / ปิดหน้าต่างกลางทาง | login ใหม่แล้วรันคำสั่งของช่วงนั้นซ้ำ — ช่วง A: `ssh root@<IP>` (ถ้า root ถูกปิดแล้ว: `ssh deploy@<IP>` แล้ววางคำสั่ง curl โดยเปลี่ยนท้ายเป็น `sudo bash`) · ช่วง B: `ssh deploy@<IP>` แล้ว `cd /opt/infra-stack && ./install.sh` |
| `command not found` | พิมพ์ผิด หรือรันผิดเครื่อง — ดูบรรทัดหน้าคำสั่งว่าเป็น `root@...` / `deploy@...` (VPS) หรือเครื่องตัวเอง |
| `No such file or directory` ตอนรัน `./install.sh` | ยังไม่ได้ `cd /opt/infra-stack` |
| ไม่แน่ใจว่าตอนนี้อยู่เครื่องไหน เป็นใคร | พิมพ์ `whoami` และ `hostname` |

## SSH และการเข้าเครื่อง

### ssh ยังถามรหัสผ่าน

ทั้งที่วาง key ไปแล้ว (INSTALL ขั้น 5.2) — สาเหตุที่เจอบ่อยสุดคือ copy ไม่ครบบรรทัด หรือ copy ไฟล์
ผิดตัว (`id_ed25519` ที่ไม่มี `.pub` คือกุญแจลับ **ห้ามวาง**) — ต้องเป็นบรรทัดเดียวขึ้นต้นด้วย `ssh-ed25519 AAAA...`

**วิธีแก้** (จากหน้าต่าง VPS ที่ยังเปิดอยู่ หรือ console ของผู้ให้บริการ — ใช้ root หรือ `sudo`):

1. ดู key ที่เครื่องมี:

   ```bash
   cat /home/deploy/.ssh/authorized_keys
   ```

2. บนคอมตัวเอง (PowerShell — ไม่ใช่ Command Prompt) แสดง public key: `type $env:USERPROFILE\.ssh\id_ed25519.pub`
   (Mac: `cat ~/.ssh/id_ed25519.pub`) แล้วเทียบว่าตรงกันไหม
3. ไม่ตรงหรือไม่มี → เพิ่มบรรทัดนั้นเข้าไป:

   ```bash
   echo '<วาง ssh-ed25519 AAAA... ทั้งบรรทัด>' >> /home/deploy/.ssh/authorized_keys
   chown deploy:deploy /home/deploy/.ssh/authorized_keys
   chmod 600 /home/deploy/.ssh/authorized_keys
   ```

### ssh deploy@IP เข้าไม่ได้

ขึ้น `Permission denied (publickey)` หลังรัน `harden.sh`

- **อย่าปิดหน้าต่าง root ที่ยังเปิดอยู่** — ใช้มันแก้
- ในหน้าต่างนั้นทำตามหัวข้อ [ssh ยังถามรหัสผ่าน](#ssh-ยังถามรหัสผ่าน) ข้อ 1–3
  แล้วลอง `ssh deploy@<IP>` จากหน้าต่างใหม่อีกครั้ง
- เครื่องตัวเองมีหลายกุญแจ? ระบุไฟล์ตรงๆ: `ssh -i ~/.ssh/id_ed25519 deploy@<IP>`

### ล็อกตัวเองออกจากเครื่องแล้ว (ปิดหน้าต่างไปแล้วเข้าไม่ได้เลย)

ใช้ **console ของผู้ให้บริการ** (Contabo: Customer Control Panel → VNC; Hetzner: Console;
GreenCloud: VNC; DigitalOcean: Droplet → Access → Console) — เป็นหน้าจอเครื่องโดยตรง ไม่ผ่าน SSH
และยัง login ด้วยรหัสผ่านได้ (การปิด password login มีผลแค่กับ SSH) login เป็น root หรือ user เดิม
ของผู้ให้บริการ แล้วแก้ตามหัวข้อ [ssh ยังถามรหัสผ่าน](#ssh-ยังถามรหัสผ่าน)

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

## ช่วง A — prepare

| อาการ | วิธีแก้ |
|-------|---------|
| `ต้องรันด้วย root` | login เป็น user อื่น → เปลี่ยน `bash` ท้ายคำสั่งเป็น `sudo bash` |
| `❌ รองรับเฉพาะ Ubuntu` | ติดตั้ง OS ใหม่เป็น Ubuntu 24.04 / 22.04 จากหน้า control panel ของผู้ให้บริการ |
| `⚠️ port 80/443 มีโปรแกรมอื่นใช้อยู่` | ผู้ให้บริการติด nginx/apache มาให้ → `sudo systemctl disable --now nginx apache2` แล้ววางคำสั่งซ้ำ |
| `❌ ไม่ใช่ public key` ตอนวาง key | วางผิดไฟล์ — ต้องเป็นผลของ `type …id_ed25519.pub` (มี `.pub`) บรรทัดเดียว ขึ้นต้นด้วย `ssh-ed25519` |
| `⚠️ deploy ยังไม่มี SSH key — ข้ามการล็อก SSH` | กด Enter ข้ามตอนถาม key → วางคำสั่งเดิมซ้ำแล้ววาง key (รันซ้ำได้) |
| `⚠️ 'deploy' ยังไม่มีรหัส sudo → ยังไม่ปิด root login` | ข้ามการตั้งรหัส (หรือรันแบบไม่มีจอ) → `passwd deploy` แล้ววางคำสั่งเดิมซ้ำ |
| `❌ ล้มที่: apt-get …` | เน็ตของเครื่องหรือ mirror ของ Ubuntu มีปัญหา — รอ 5 นาทีแล้ววางคำสั่งซ้ำ; ถ้าขึ้น `Could not get lock` มี apt อีกตัวรันอยู่ (มักเป็น auto update หลังเปิดเครื่องใหม่) รอให้เสร็จก่อน |
| deploy ใช้ `sudo` แล้วถามรหัส แต่ไม่รู้รหัส | จาก root หรือ console ของผู้ให้บริการ: `passwd deploy` |

## ช่วง B — install.sh

| อาการ | วิธีแก้ |
|-------|---------|
| `ERROR: รันด้วย user deploy ไม่ใช่ root` | พิมพ์ `su - deploy` แล้ว `cd /opt/infra-stack && ./install.sh` |
| `❌ ไม่ใช่โดเมน` | พิมพ์แค่ชื่อ เช่น `mysite.com` — ไม่มี `https://`, `www.` หรือ `/` ท้าย |
| `ERROR: ยังไม่ได้ตั้งโดเมน/อีเมล` | รันแบบไม่มีจอให้ตอบ (เช่นผ่าน script) → รันใน terminal ปกติ หรือใส่ `INFRA_DOMAIN=… INFRA_EMAIL=…` หน้าคำสั่ง |
| ตาราง DNS ค้าง `⏳ ยังไม่มี` นานเกิน 10 นาที ทั้งที่สร้างแล้ว | เช็คใน Cloudflare ว่าสร้างที่โดเมนถูกตัว + กด Save แล้ว และโดเมนเป็น **Active** (ถ้าเพิ่งย้าย nameserver อาจรอหลายชั่วโมง → `Ctrl + C` ปล่อยให้ระบบรอเองเบื้องหลัง) |
| ตาราง DNS ขึ้น `❌ ชี้ไป x.x.x.x (เครื่องอื่น)` | มี record เดิมชี้เครื่องอื่น → Cloudflare กด **Edit** ที่แถวนั้นเปลี่ยน IP · ถ้าเครื่องเก่ายังใช้อยู่ ห้ามแย่งชื่อ → ใช้โดเมนย่อย ([11-cloudflare.md](11-cloudflare.md)) |
| `⏳ ยังไม่ครบ … ชื่อ` ตอนขอ HTTPS cert | ปกติได้ภายในไม่กี่นาที เช็คด้วย `infra status` — ค้างนานให้ดูหัวข้อ [เปิดหน้าเว็บในเบราว์เซอร์](#เปิดหน้าเว็บในเบราว์เซอร์) |
| `⚠️ ไม่ได้สุ่ม: POSTGRES_PASSWORD ...` | เครื่องนี้เคยติดตั้งมาก่อนและมีข้อมูลเดิม — ใส่รหัสเดิมใน `.env` เอง (สุ่มใหม่จะเข้าฐานข้อมูลเดิมไม่ได้) |
| `permission denied while trying to connect to the Docker daemon socket` | `install.sh` แก้ให้เอง (รันตัวเองใหม่ด้วยสิทธิ์ docker) — ถ้ายังเจอ: `exit` แล้ว `ssh deploy@<IP>` ใหม่ |

## เปิดหน้าเว็บในเบราว์เซอร์

ก่อนอื่นดู log ของ Traefik (ตัวที่ขอใบรับรอง):

```bash
docker logs traefik --tail 50
```

| อาการในเบราว์เซอร์ | สาเหตุ / วิธีแก้ |
|--------------------|------------------|
| "Your connection is not private" / `NET::ERR_CERT_...` | ใบรับรองยังไม่ออก — รอ 1–2 นาทีแล้ว Refresh ถ้ายังเป็น ดู log ข้างบนหา `acme` |
| log มี `429` / `too many failed authorizations` | Let's Encrypt แบนชั่วคราวเพราะขอซ้ำตอนไม่มี DNS — สร้าง DNS ให้ครบ แล้ว**รอ 1 ชั่วโมง** ห้ามรันซ้ำระหว่างรอ |
| log มี `NXDOMAIN` | ไม่มี DNS record ของชื่อนั้น → สร้างตาม INSTALL ขั้นที่ 7 (ดูชื่อที่ขาด: `infra status`) |
| "This site can't be reached" / `DNS_PROBE_FINISHED_NXDOMAIN` | DNS ยังไม่มีหรือยังไม่กระจาย → `nslookup <ชื่อ>.<โดเมน>` จากเครื่องตัวเอง |
| `ERR_TOO_MANY_REDIRECTS` | Cloudflare SSL ตั้งเป็น Flexible → เปลี่ยนเป็น **Full (strict)** (INSTALL ขั้น 2.4) |
| Cloudflare error **526** Invalid SSL certificate | เปิดเมฆส้มตอนเครื่องยังไม่มีใบรับรอง → เปลี่ยน record เป็น**เมฆเทา**รอใบรับรองออก แล้วค่อยเปิดส้ม |
| `404 page not found` ทุกโดเมน | Traefik มองไม่เห็น container — ดู log หา `client version ... is too old` แล้วแก้ตาม [04-traefik.md](04-traefik.md) |
| เบราว์เซอร์เด้งกล่องถาม username/password | ปกติ — ใช้ `DASHBOARD_USER` / `DASHBOARD_PASSWORD` (`grep DASHBOARD .env`) |

## Portainer

ปกติ `install.sh` สร้าง admin ให้แล้ว (user `admin` รหัส `PORTAINER_ADMIN_PASSWORD` — ดู `infra secrets`)
ตารางนี้ใช้เมื่อสรุปท้ายบอกให้ "สร้าง admin ภายใน 5 นาที" เท่านั้น

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
| Portainer | `infra secrets` (ถ้า install.sh สร้างให้) — ถ้าตั้งเองแล้วลืม ดู `services/portainer/README.md` |
| Uptime Kuma / Beszel / n8n | ตั้งเองตอนสร้างบัญชี ไม่ได้อยู่ใน `.env` — ดูคู่มือของโปรแกรมนั้นใน `services/<ชื่อ>/README.md` / docs/17 |
| ดูทุกตัวที่อยู่ใน `.env` | `infra secrets` |
| sudo ของ deploy | ตั้งใหม่จาก root หรือ console ของผู้ให้บริการ: `passwd deploy` |

> ⚠️ แก้ `GRAFANA_ADMIN_PASSWORD` / `POSTGRES_PASSWORD` ใน `.env` หลังติดตั้งแล้ว**ไม่ได้เปลี่ยนรหัสจริง**
> — โปรแกรมพวกนี้จำรหัสไว้ตั้งแต่เปิดครั้งแรก

## ยังแก้ไม่ได้

รวบรวมข้อมูลนี้ก่อนถามคนอื่น (**ลบรหัสผ่านออกก่อนส่งให้ใครเสมอ**):

```bash
cat VERSION
infra status
docker logs traefik --tail 50
tail -30 /opt/infra-stack/install.log
```

พร้อมบอกว่าทำถึงขั้นไหนของ [INSTALL.md](INSTALL.md) และข้อความ error ที่เห็นบนจอ
