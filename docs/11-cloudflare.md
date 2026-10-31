# 11 — Cloudflare

🎯 DNS + SSL + Proxy + WAF ฟรี หน้าเว็บทุกตัว

## ⚙️ วิธีทำ

1. เพิ่มโดเมนเข้า Cloudflare (ฟรี plan พอ) → เปลี่ยน nameserver ที่ registrar
2. DNS records ชี้ VPS:

```text
A    @              <server-ip>   Proxied 🟠
A    *  (หรือรายตัว) <server-ip>   Proxied 🟠
```

**ติดตั้งครั้งแรกไม่ต้องสร้างล่วงหน้า** — `install.sh` เปิดทุกอย่างยกเว้น Traefik แล้วโชว์ตารางชื่อที่ต้องสร้าง
พร้อม IP ของเครื่อง เช็คให้ทุก 30 วินาที และเปิด Traefik (ขอ cert) เมื่อครบเท่านั้น จึงไม่โดน rate limit

เปิด stack เพิ่มทีหลัง: **สร้างให้ครบทุก subdomain ของ stack นั้นก่อน start**
(service ที่มี traefik labels แต่ไม่มี DNS → ACME ล้มซ้ำจนโดน rate limit — ดู [04-traefik.md](04-traefik.md)):

| Stack | Subdomain |
|-------|-----------|
| Core | `traefik`, `portainer` |
| Monitoring | `grafana`, `netdata`, `uptime`, `logs`, `servers` |
| Tools | `pgadmin`, `redis` |
| Messaging | `mq` |
| Storage | `s3`, `minio` |
| Projects | `<ชื่อ project>` เช่น `app`, `n8n` (หรือค่า `APP_DOMAIN` ใน `.env` ของ project) |

เช็คว่าครบก่อน start stack ไหนก็ได้ — script อ่านรายชื่อจาก compose จริง บอกว่าขาดตัวไหน และ**ชี้มาเครื่องนี้จริงไหม**
(ชื่อที่ชี้ไปเครื่องอื่นขึ้น ❌ พร้อม IP; Proxied เมฆส้มเทียบ IP ไม่ได้ จึงเตือนให้ตรวจใน dashboard):

```bash
./scripts/check-dns.sh tools                 # stack เดียว
./scripts/check-dns.sh --wait tools          # รอจนครบ (เช็คทุก 30 วินาที)
./scripts/check-dns.sh core app.example.com  # ชื่อเต็มของเว็บ project ก็ได้
```

⏳ ถ้าเพิ่งเปลี่ยน nameserver ที่ registrar ไป Cloudflare อาจใช้เวลาหลายชั่วโมง (สูงสุด ~24 ชม.)
กว่าโดเมนจะ Active — ทำขั้นนี้ล่วงหน้าก่อนวันติดตั้ง

3. SSL/TLS → mode **Full (strict)** (เรามี cert จริงจาก Let's Encrypt ฝั่ง Traefik)
4. เปิด: Always Use HTTPS, WAF managed rules (ฟรี tier), Bot Fight Mode

## 🖥️ เครื่องที่ 2, 3, … ใช้โดเมนเดียวกัน (รันคู่เครื่องเดิม)

subdomain อย่าง `portainer.<โดเมน>` ชี้ไปเครื่องแรกอยู่แล้ว — ห้ามใช้ `BASE_DOMAIN` เดียวกัน
(เครื่องใหม่ขอ cert ไม่ผ่านเพราะ DNS ชี้ไปเครื่องอื่น และ `check-dns.sh` จับไม่ได้เพราะชื่อ resolve ได้)
ให้ตั้งชื่อย่อยของเครื่องนั้นแทน:

```bash
BASE_DOMAIN=sg.example.com      # ใน .env ของเครื่องใหม่ → portainer.sg.example.com ฯลฯ
```

สร้าง record เดียวครบทุกตัว — **ต้องเป็น DNS only (เมฆเทา)**:

```text
A    *.sg    <IP เครื่องใหม่>    DNS only ⚪
```

ทำไมเมฆเทา: SSL ฟรีของ Cloudflare ครอบแค่ชื่อชั้นเดียว (`*.example.com`) ไม่ครอบ
`portainer.sg.example.com` — ถ้าเปิดส้มจะได้ error SSL ที่ browser ส่วน cert ของเครื่องเองยังได้จาก
Let's Encrypt ตามปกติ (ข้อเสีย: ไม่ได้ WAF/ซ่อน IP ของ Cloudflare — ใช้กับหน้าแอดมินได้ ส่วนเว็บของ
ลูกค้าบนเครื่องนี้ให้ใช้ชื่อชั้นเดียว เช่น `APP_DOMAIN=shop.example.com` แบบส้มได้ตามปกติ)

## ⚠️ ระวัง

- **ห้ามใช้ mode "Flexible"** — จะเกิด redirect loop กับ Traefik
- **ติดตั้งครั้งแรกแนะนำสร้างทุก record เป็นเมฆเทา (DNS only)** ก่อน ([INSTALL.md](INSTALL.md) ขั้นที่ 5)
  ให้ Traefik ออก cert ให้ครบ (เปิดทุกหน้าแล้วเห็นรูปกุญแจ) แล้วค่อยเปิดส้มกลับ — ถ้าเปิดส้มตอนเครื่อง
  ยังไม่มี cert จะได้ Cloudflare error 526 หรือ HTTP challenge ล้ม
- อย่า proxy (ส้ม) record ที่ไม่ใช่ HTTP เช่น SSH
- API token ของ Cloudflare = secret — ห้าม commit
