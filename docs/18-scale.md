# 18 — Scaling

🎯 โตได้โดยไม่รื้อโครงสร้าง — เพราะทุกอย่างเป็น container + config อยู่ใน Git

## Stage 1 → 2: แยก Database Server (เมื่อ RAM ตึง)

สัญญาณ: Netdata แสดง RAM > 85% ประจำ, PostgreSQL แย่ง memory กับ app

```text
เครื่อง A (App):  Traefik + apps + Redis + monitoring
เครื่อง B (DB):   PostgreSQL (+ Redis ถ้าจำเป็น)
```

วิธี: VPS ใหม่ → `install.sh` → up เฉพาะ database stack →
restore backup → เปลี่ยน `DB_HOST` ของทุก app → private network ระหว่างเครื่อง

## Stage 2 → 3: หลาย App Server + Load Balancer

สัญญาณ: CPU ตึงที่ app, ต้องการ zero-downtime deploy

```text
Cloudflare → LB → App1 + App2 → Redis / PostgreSQL / R2
```

ต้องมี: session ใน Redis (ทำแล้ว), ไฟล์ใน R2 (ทำแล้ว) — เพราะออกแบบไว้ตั้งแต่ Stage 1

## Stage 4: Kubernetes

อีกหลายปีค่อยคิด — ถึงตอนนั้น service ทุกตัวเป็น container อยู่แล้ว
การย้ายคือแปลง compose → manifests ไม่ใช่รื้อระบบ

## สิ่งที่ทำวันนี้เพื่อวันนั้น

- [x] ทุก state อยู่ใน PostgreSQL / Redis / R2 — app container เป็น stateless
- [x] config ทั้งหมดอยู่ใน Git — เครื่องใหม่ reproduce ได้
- [x] backup/restore ใช้งานได้จริง — การย้ายเครื่อง = restore ที่ซ้อมแล้ว
- [ ] วัด baseline: CPU/RAM ปกติใช้เท่าไหร่ (Grafana) เพื่อรู้ว่า "ตึง" คือเมื่อไหร่
