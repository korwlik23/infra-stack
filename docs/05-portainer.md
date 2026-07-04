# 05 — Portainer

🎯 จัดการ Docker ทุก container ผ่าน browser — เลิกจำคำสั่งยาว ๆ

## ⚙️ วิธีทำ

อยู่ใน core stack แล้ว (`docker/docker-compose.core.yml`)
เปิด `https://portainer.<BASE_DOMAIN>` → สร้าง admin **ภายใน 5 นาที**หลัง start
(เกินแล้วต้อง `docker restart portainer` แล้วรีบเข้าใหม่)

หน้าสร้าง admin จะถาม **Setup token** — เอาจาก log:

```bash
docker logs portainer 2>&1 | grep -i token
```

token ออกใหม่ทุกครั้งที่ restart — ใช้ตัวล่าสุดเสมอ

## ใช้ทำอะไร

- ดู container / logs / stats ทุกตัว
- restart service ที่ค้าง
- เข้า console ของ container (แทน `docker exec -it`)
- จัดการ volumes / networks / images

## ⚠️ ระวัง

- ใช้รหัสผ่านยาว (16+ ตัว) — Portainer คุม Docker ทั้งเครื่อง = คุมเครื่องทั้งเครื่อง
- อย่า deploy stack ผ่าน Portainer UI สำหรับ service ใน repo นี้ —
  แก้ไฟล์ใน Git แล้ว `docker compose up -d` เพื่อให้ Git เป็น source of truth เสมอ
