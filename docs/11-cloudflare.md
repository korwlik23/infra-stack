# 11 — Cloudflare

🎯 DNS + SSL + Proxy + WAF ฟรี หน้าเว็บทุกตัว

## ⚙️ วิธีทำ

1. เพิ่มโดเมนเข้า Cloudflare (ฟรี plan พอ) → เปลี่ยน nameserver ที่ registrar
2. DNS records ชี้ VPS:

```text
A    @              <server-ip>   Proxied 🟠
A    *  (หรือรายตัว) <server-ip>   Proxied 🟠
```

แนะนำสร้างรายตัว — **ครบทุก subdomain ของ stack ที่จะเปิด และสร้างก่อน start stack นั้น**
(service ที่มี traefik labels แต่ไม่มี DNS → ACME ล้มซ้ำจนโดน rate limit — ดู [04-traefik.md](04-traefik.md)):

| Stack | Subdomain |
|-------|-----------|
| Core (`install.sh` start ให้ทันที) | `traefik`, `portainer` |
| Monitoring | `grafana`, `netdata`, `uptime`, `logs`, `servers` |
| Tools | `pgadmin`, `redis` |
| Messaging | `mq` |
| Storage | `s3`, `minio` |
| Projects | `<ชื่อ project>` เช่น `app`, `n8n` (หรือค่า `APP_DOMAIN` ใน `.env` ของ project) |

เช็คว่าครบก่อน start stack ไหนก็ได้ — script อ่านรายชื่อจาก compose จริง และบอกว่าขาดตัวไหน:

```bash
./scripts/check-dns.sh core monitoring     # install.sh เช็ค core ให้อัตโนมัติ
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
- ตอนขอ cert ครั้งแรก ถ้า HTTP challenge ล้ม: ปิด Proxy (เมฆเทา) ชั่วคราว
  ให้ Traefik ออก cert ก่อน แล้วค่อยเปิดส้มกลับ
- อย่า proxy (ส้ม) record ที่ไม่ใช่ HTTP เช่น SSH
- API token ของ Cloudflare = secret — ห้าม commit
