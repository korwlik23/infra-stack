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

## ⚙️ migrate อัตโนมัติตอน deploy (v2.2.0+)

`deploy.sh` จะรัน `php artisan migrate --force` **ก่อนสลับ traffic** อัตโนมัติ
ถ้า project มี `DEPLOY_MIGRATE=1` ใน `.env` (template Laravel ตั้งให้แล้ว)

ลำดับ: build image ใหม่ → **migrate ด้วย image ใหม่** → rolling deploy
→ schema พร้อมก่อนโค้ดใหม่รับ traffic ถ้า migrate ล้ม `set -e` หยุดทันที ไม่ deploy ต่อ

🩹 **เหตุผลที่ต้องมี (post-mortem 2026-07-12):** ก่อนมีฟีเจอร์นี้ push โค้ดที่มี
migration ใหม่ → auto-deploy build+deploy โค้ดใหม่ **แต่ schema ยังเก่า** → app คืน 500
และ healthcheck `/up` ตอบ 200 อยู่ (แค่เช็คว่า framework boot ได้ ไม่เช็ค DB)
rolling deploy เลยคิดว่าสำเร็จ ทั้งที่หน้าเว็บพัง → เว็บดับจน migrate มือ

**project เก่าที่สร้างก่อน v2.2.0:** เพิ่ม `DEPLOY_MIGRATE=1` ใน `.env` เอง

## 🔄 Rollback

```bash
./scripts/rollback.sh automation-ai-seller-chat previous   # กลับเวอร์ชันก่อนหน้า
```

`deploy.sh` เก็บ image ก่อน build ใหม่ไว้เป็น tag `:previous` อัตโนมัติ (v2.2.0+)
→ rollback ได้เสมอโดยไม่ต้อง tag เวอร์ชันเอง (เก็บย้อนได้ 1 step)
อยากเก็บหลายเวอร์ชัน: tag image เองเป็น `:v1.4.2` แล้ว `rollback.sh <project> v1.4.2`

⚠️ **migration ไม่ย้อนอัตโนมัติ** — ถ้าใช้ expand/contract ถูกต้อง โค้ดเก่าจะยัง
อ่าน schema ใหม่ได้ → rollback โค้ดปลอดภัย (นี่คือเหตุผลที่ห้าม drop column ใน release เดียว)

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

## ⚠️ ข้อจำกัดของ healthcheck `/up` (รู้ไว้)

`/up` ของ Laravel เช็คแค่ว่า framework boot ได้ — **ไม่เช็คว่า migration ครบ**
ดังนั้น "deploy สำเร็จ" ไม่ได้แปลว่า "ทุกหน้าใช้ได้" เสมอ ทางกันสองชั้น:
1. `DEPLOY_MIGRATE=1` — migrate ก่อน traffic (แก้เคสที่เจอบ่อยสุด) ✅ ทำแล้ว
2. อยากเข้มกว่า: เขียน health route เองที่แตะ DB/Redis เบา ๆ แล้วตั้ง `HEALTHCHECK_PATH`
   ชี้ไปที่นั่น — ตัวใหม่ที่ query ตารางที่ยังไม่มีจะ fail healthcheck → rollout ไม่ผ่าน
