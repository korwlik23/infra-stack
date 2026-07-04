# 20 — RabbitMQ (v2.0)

🎯 Message queue จริงจัง สำหรับงานที่ Redis queue ไม่พอ

## เมื่อไหร่ถึงต้องใช้

| สัญญาณ | อยู่ต่อ Redis | ย้าย RabbitMQ |
|--------|--------------|----------------|
| Queue เมล/notification ธรรมดา | ✅ | |
| งาน AI หลายขั้นตอน ต้อง retry + dead-letter | | ✅ |
| Fan-out: 1 event → หลาย worker คนละหน้าที่ | | ✅ |
| ต้องการ priority / TTL / delayed message | | ✅ |

**อย่าเพิ่งเปิดถ้ายังไม่เจอสัญญาณ** — RabbitMQ กิน RAM ~150-300MB และเพิ่มของให้ดูแล

## ⚙️ วิธีทำ

```bash
# เพิ่ม RABBITMQ_USER / RABBITMQ_PASSWORD ใน .env ก่อน
docker compose --env-file .env -f docker/docker-compose.messaging.yml up -d
```

- UI: `https://mq.<BASE_DOMAIN>` · AMQP จาก app: `amqp://user:pass@rabbitmq:5672`
- รายละเอียด: [services/rabbitmq/README.md](../services/rabbitmq/README.md)

## 🧪 ทดสอบ

```bash
docker exec rabbitmq rabbitmq-diagnostics -q ping   # Ping succeeded
```
