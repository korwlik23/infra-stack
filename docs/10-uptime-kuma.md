# 10 — Uptime Kuma

🎯 รู้ก่อนลูกค้าว่าเว็บล่ม — ผ่าน Telegram

## ⚙️ วิธีทำ

อยู่ใน monitoring stack → เปิด `https://uptime.<BASE_DOMAIN>` สร้าง admin ครั้งแรก

## Monitors ที่ควรตั้ง

| Monitor | Type | Interval |
|---------|------|----------|
| เว็บทุก project | HTTP(s) 200 | 60s |
| API health endpoint | HTTP(s) keyword | 60s |
| n8n | HTTP(s) 200 | 60s |
| Grafana / Portainer | HTTP(s) | 300s |

## Telegram Alert

1. คุย `@BotFather` → `/newbot` → ได้ token
2. หา chat id: คุยกับ bot แล้วเปิด `https://api.telegram.org/bot<token>/getUpdates`
3. Uptime Kuma → Settings → Notifications → Telegram → ใส่ token + chat id
4. ผูกกับทุก monitor (ตั้ง default notification ได้)

## ⚠️ ระวัง

Uptime Kuma อยู่บนเครื่องเดียวกับเว็บ — ถ้า**ทั้งเครื่อง**ล่มมันเตือนไม่ได้
เสริมด้วย monitor ฟรีข้างนอก (เช่น UptimeRobot) ชี้มาที่โดเมนหลัก 1 ตัว
