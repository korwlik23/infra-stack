# 04 — Traefik

🎯 ทุกโดเมนมี HTTPS อัตโนมัติ ไม่ต้องยุ่งกับ certificate เอง

🤔 ทำไม Traefik (ไม่ใช่ Nginx/Caddy): อ่าน Docker labels เอง —
เพิ่ม service ใหม่แค่ใส่ labels ไม่ต้องแก้ config กลางแล้ว reload

## ⚙️ วิธีทำ

```bash
# 1. แก้ email ใน services/traefik/traefik.yml ให้ตรง ACME_EMAIL
# 2. เตรียม cert storage
touch services/traefik/acme.json && chmod 600 services/traefik/acme.json
# 3. start (รวมอยู่ใน core stack)
docker compose --env-file .env -f docker/docker-compose.core.yml up -d
```

รายละเอียด labels ดู [services/traefik/README.md](../services/traefik/README.md)

## ⚠️ ระวัง

- DNS ต้องชี้มาเครื่องนี้**ก่อน** start ไม่งั้น Let's Encrypt challenge ล้ม
  (โดน rate limit ได้ถ้าพลาดซ้ำ ๆ — 5 ครั้ง/ชั่วโมง/โดเมน)
- ถ้าใช้ Cloudflare Proxy (ส้ม): ตั้ง SSL mode = **Full (strict)** ดู [11-cloudflare.md](11-cloudflare.md)
- เปลี่ยน basicauth hash ของ dashboard ก่อนใช้จริง

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
