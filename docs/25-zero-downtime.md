# 25 — Zero-Downtime Deployment (v2.1)

🎯 Deploy แล้วเว็บไม่ดับสักวินาที และ**ของพังไม่มีทางถึงมือ user**

## 🤔 ปัญหาของ deploy แบบเดิม

`docker compose up -d` = หยุดตัวเก่า → เปิดตัวใหม่:

```text
ปัญหา 1: มีช่องว่าง 2-10 วินาทีที่ไม่มีใครรับ traffic (เว็บดับ)
ปัญหา 2: ถ้า image ใหม่พัง → เว็บดับยาว จนกว่าจะ rollback มือ
```

## ⚙️ วิธีที่ stack นี้ใช้: Rolling deploy ด้วย `docker rollout`

`scripts/deploy.sh` ทำให้อัตโนมัติเมื่อ project มี `ROLLOUT_SERVICE` ใน .env:

```text
1. เปิด container ใหม่ (v2) ขึ้นมา "คู่กับ" ตัวเก่า (v1)
2. รอ v2 ผ่าน Docker healthcheck (app ตอบ HTTP ได้จริง)
3. Traefik เริ่มกระจาย traffic ให้ v2 (LB สองตัวอัตโนมัติ)
4. ถอด v1 ออก → เหลือ v2 ตัวเดียว
   ✅ user ไม่เจอช่องว่างเลย

ถ้า v2 healthcheck ไม่ผ่าน:
   rollout ล้ม → v1 ไม่ถูกแตะ → เว็บยังปกติ, deploy fail เฉย ๆ
   ✅ "ระบบแตก" กลายเป็นแค่ log error ไม่ใช่ downtime
```

Plugin ติดตั้งโดย `install.sh` อยู่แล้ว (ไฟล์เดียวที่ `~/.docker/cli-plugins/docker-rollout`)

## เงื่อนไขที่ template จัดให้แล้ว

| เงื่อนไข | สถานะ |
|----------|--------|
| App เป็น stateless (session→Redis, ไฟล์→R2) | ✅ ออกแบบไว้ตั้งแต่ v1.0.0 |
| ไม่มี `container_name` บน service ที่รับ traffic | ✅ templates laravel/nextjs (v2.1) |
| มี `healthcheck` จริง (ตอบ HTTP ไม่ใช่แค่ process ขึ้น) | ✅ Laravel `/up`, Next.js fetch |
| Traefik healthcheck labels — ส่ง traffic เฉพาะตัว healthy | ✅ ใส่ให้แล้ว |

⚠️ **Healthcheck ต้อง "จริง"** — endpoint ควรแตะ database/Redis เบา ๆ ด้วย
ถ้าตอบ 200 ทั้งที่ต่อ db ไม่ได้ ของพังจะผ่านด่านเข้าไปรับ traffic

## 🗄️ Database Migration: จุดที่พังบ่อยสุด

ช่วง rolling มี**โค้ดเก่า+ใหม่รันคู่กัน**บน schema เดียว → migration ต้องเป็น
**expand / contract** (backward-compatible เสมอ):

```text
❌ ห้าม: rename column / drop column / เปลี่ยน type ในครั้งเดียว
   → โค้ดเก่า query column เดิม พังทันทีที่ migrate

✅ ทำเป็น 2 release:
   Release 1 (expand):   ADD COLUMN ใหม่ — โค้ดเขียนลงทั้งคู่, อ่านจากตัวใหม่
   (รอจน Release 1 นิ่ง)
   Release 2 (contract): DROP COLUMN เก่า — ไม่มีโค้ดไหนใช้แล้ว
```

กติกาสั้น ๆ: **migration ทุกตัวต้องรันได้โดยโค้ดเวอร์ชันก่อนหน้ายังทำงานต่อได้**

## 🔄 Rollback

```bash
./scripts/rollback.sh zennuaflow v1.4.2    # กลับ tag เก่า แบบ rolling เหมือนกัน
```

เงื่อนไข: **tag image ด้วยเวอร์ชันเสมอ** (`:v1.4.2` ไม่ใช่ `:latest` อย่างเดียว)
ไม่งั้นไม่มี "เวอร์ชันเก่า" ให้กลับ — และจำไว้ว่า migration ไม่ย้อนอัตโนมัติ
(ถ้าใช้ expand/contract ถูกต้อง โค้ดเก่าจะยังอ่าน schema ใหม่ได้ → rollback ปลอดภัย)

## ข้อยกเว้น (ตัวที่ rolling ไม่ได้ — และไม่เป็นไร)

| ตัว | เหตุผล | ผลตอน deploy |
|-----|--------|---------------|
| n8n | instance เดียวต่อ encryption key + volume | restart สั้น ๆ, workflow ค้างคิวไว้รันต่อ |
| queue/scheduler | ไม่รับ traffic จาก user | restart แล้วหยิบงานจากคิวต่อ ไม่มีใครเห็น |
| AI worker | ไม่รับ traffic | เหมือน queue |

## 🧪 วิธีทดสอบว่า zero-downtime จริง

เปิด terminal ที่สอง ยิงทุกวินาทีระหว่าง deploy:

```bash
while true; do curl -s -o /dev/null -w "%{http_code} " https://app.<domain>; sleep 1; done
# ระหว่างรัน ./scripts/deploy.sh <name> ต้องเห็น 200 ล้วน ไม่มี 502/000

# ทดสอบด่าน healthcheck: deploy image ที่พังโดยตั้งใจ
# → rollout ต้อง fail, เว็บต้องยังตอบ 200 ตลอด
```
