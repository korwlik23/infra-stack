# Uptime Kuma

เช็คว่า Website / API / n8n ยังออนไลน์อยู่ไหม + แจ้งเตือน Telegram
เปิดที่ `https://uptime.<BASE_DOMAIN>` แล้วสร้าง admin ครั้งแรก

## Monitors ที่ควรตั้ง

- ทุกโดเมนของ project (HTTP 200)
- API health endpoints
- n8n webhook endpoint
- PostgreSQL / Redis (TCP ผ่าน internal host)

## Telegram Alert

1. คุยกับ `@BotFather` → สร้าง bot → ได้ token
2. Settings → Notifications → Telegram → ใส่ token + chat id
3. ผูก notification เข้ากับทุก monitor
