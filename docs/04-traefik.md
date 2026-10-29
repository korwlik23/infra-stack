# 04 — Traefik

🎯 ทุกโดเมนมี HTTPS อัตโนมัติ ไม่ต้องยุ่งกับ certificate เอง

🤔 ทำไม Traefik (ไม่ใช่ Nginx/Caddy): อ่าน Docker labels เอง —
เพิ่ม service ใหม่แค่ใส่ labels ไม่ต้องแก้ config กลางแล้ว reload

## ⚙️ วิธีทำ

```bash
# 1. ตั้ง ACME_EMAIL ใน .env — Traefik อ่านค่าเองผ่าน CLI flag ใน compose (ไม่มี traefik.yml แล้ว)
# 2. เตรียม cert storage
touch services/traefik/acme.json && chmod 600 services/traefik/acme.json
# 3. start (รวมอยู่ใน core stack — install.sh ทำข้อ 2-3 ให้แล้ว)
docker compose --env-file .env -f docker/docker-compose.core.yml up -d
```

รายละเอียด labels ดู [services/traefik/README.md](../services/traefik/README.md)

## ⚠️ ระวัง

- DNS ต้องชี้มาเครื่องนี้**ก่อน** start ไม่งั้น Let's Encrypt challenge ล้ม
  (โดน rate limit ได้ถ้าพลาดซ้ำ ๆ — 5 ครั้ง/ชั่วโมง/โดเมน) — `install.sh` เช็คของ core ให้แล้ว
  stack อื่นเช็คเองก่อน start: `./scripts/check-dns.sh monitoring` (หรือ `tools` / `messaging` / `storage`)
- ถ้าใช้ Cloudflare Proxy (ส้ม): ตั้ง SSL mode = **Full (strict)** ดู [11-cloudflare.md](11-cloudflare.md)
- หน้า Traefik dashboard, Netdata, Dozzle และ Redis Insight ใช้ basicauth กลาง
  `dashboard-auth@file` — `install.sh` สร้างไฟล์ `services/traefik/dynamic/auth.yml` (นอก Git)
  จาก `DASHBOARD_USER` / `DASHBOARD_PASSWORD` ใน `.env` ทุกครั้งที่รัน ไม่ต้องแก้ hash ใน compose
  - ดูรหัส: `grep DASHBOARD_PASSWORD .env`
  - เปลี่ยนรหัส: แก้ `DASHBOARD_PASSWORD` ใน `.env` → `./install.sh` (Traefik โหลดไฟล์ใหม่เอง)
  - ถ้าเห็น 404 ทุกหน้าที่ใช้ basicauth: ยังไม่มี `auth.yml` → รัน `./install.sh`

## 🧪 ทดสอบ

```bash
docker logs traefik --tail 50 | grep -i acme   # ออก cert สำเร็จ
curl -I https://portainer.<BASE_DOMAIN>        # ได้ 200/302 พร้อม TLS
```

## 🩹 ปัญหาที่เจอจริง (2026-07): ทุกโดเมนเป็น "404 page not found"

**อาการ:** DNS ถูก, Host rule ถูก, container อยู่ network proxy ครบ แต่ 404 ทุกโดเมน
**เช็ค:** `docker logs traefik` — ถ้าเห็น

```text
ERR ... client version 1.24 is too old. Minimum supported API version is 1.40
```

**สาเหตุ:** Traefik รุ่นเก่า (เช่น v3.1) คุยกับ Docker Engine รุ่นใหม่ (29+) ไม่ได้
เพราะ Docker ตัด API เวอร์ชันเก่าทิ้ง → Traefik มองไม่เห็น container เลย
จึงไม่มี router เกิดขึ้นแม้ config จะถูกทุกอย่าง

**วิธีแก้:** ใช้ image `traefik:v3` (pin แค่ major) แล้ว pull + recreate:

```bash
docker compose --env-file .env -f docker/docker-compose.core.yml pull
docker compose --env-file .env -f docker/docker-compose.core.yml up -d
```

**วิธีแยกปัญหาแบบนี้เร็ว ๆ:** ยิงตรงเข้า Traefik ข้าม Cloudflare —
`curl -sk -H "Host: portainer.<BASE_DOMAIN>" https://localhost -o /dev/null -w "%{http_code}"`
ได้ 404 = ปัญหาที่ Traefik/labels, ได้ 200/307 = ปัญหาอยู่ชั้น Cloudflare/browser cache

## 🩹 log เต็มไปด้วย "NXDOMAIN … Unable to obtain ACME certificate" + โดน 429 rate limit

**สาเหตุ:** มี service ที่ติด traefik labels แต่**ยังไม่ได้สร้าง DNS record**
(เช่น `traefik.`, `servers.`, `redis.` subdomain) — Traefik พยายามขอ cert ซ้ำ ๆ
จน Let's Encrypt แบน 1 ชั่วโมง (`429 too many failed authorizations`)

**วิธีแก้ (เลือกหนึ่งต่อ service):**
1. สร้าง A record ของ subdomain นั้นชี้มาเครื่อง → error หายเอง (rate limit หมดอายุใน ~1 ชม.)
2. ยังไม่ใช้ service นั้น → ปิด router: แก้ compose เป็น `traefik.enable=false` แล้ว up -d

**กฎ:** เปิด service ที่มี traefik labels เมื่อไหร่ → สร้าง DNS record ทันทีทุกครั้ง
แล้วเช็คด้วย `./scripts/check-dns.sh <stack>` ก่อน `up -d` (บอกว่าขาด record ตัวไหน)
