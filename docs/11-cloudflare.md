# 11 — Cloudflare

🎯 DNS + SSL + Proxy + WAF ฟรี หน้าเว็บทุกตัว

## ⚙️ วิธีทำ

1. เพิ่มโดเมนเข้า Cloudflare (ฟรี plan พอ) → เปลี่ยน nameserver ที่ registrar
2. DNS records ชี้ VPS:

```text
A    @              <server-ip>   Proxied 🟠
A    *  (หรือรายตัว) <server-ip>   Proxied 🟠
```

แนะนำสร้างรายตัว: `portainer`, `grafana`, `netdata`, `uptime`, `logs`, `n8n` + โดเมน project

3. SSL/TLS → mode **Full (strict)** (เรามี cert จริงจาก Let's Encrypt ฝั่ง Traefik)
4. เปิด: Always Use HTTPS, WAF managed rules (ฟรี tier), Bot Fight Mode

## ⚠️ ระวัง

- **ห้ามใช้ mode "Flexible"** — จะเกิด redirect loop กับ Traefik
- ตอนขอ cert ครั้งแรก ถ้า HTTP challenge ล้ม: ปิด Proxy (เมฆเทา) ชั่วคราว
  ให้ Traefik ออก cert ก่อน แล้วค่อยเปิดส้มกลับ
- อย่า proxy (ส้ม) record ที่ไม่ใช่ HTTP เช่น SSH
- API token ของ Cloudflare = secret — ห้าม commit
