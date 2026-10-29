# RabbitMQ (v2.0)

Message queue สำหรับงานที่ Redis queue เริ่มไม่พอ — routing, retry/DLQ,
หลาย consumer, งาน AI ที่รันนาน

## เมื่อไหร่ใช้ RabbitMQ แทน Redis queue

| งาน | ใช้ |
|-----|-----|
| Laravel queue ปกติ (เมล, notification) | Redis พอ |
| Workflow AI หลายขั้น, retry ซับซ้อน, fan-out หลาย worker | RabbitMQ |
| ต้องการ dead-letter queue / message TTL / priority | RabbitMQ |

## การต่อ

```text
AMQP:  amqp://$RABBITMQ_USER:$RABBITMQ_PASSWORD@rabbitmq:5672   (network backend)
UI:    https://mq.<BASE_DOMAIN>   (login เดียวกัน)
```

## Start / Test

```bash
# จาก repo root (/opt/infra-stack) — อยู่ใน messaging stack
docker compose --env-file .env -f docker/docker-compose.messaging.yml up -d rabbitmq
docker exec rabbitmq rabbitmq-diagnostics -q ping    # → Ping succeeded
```

volume `rabbitmq_data` เก็บ message ที่ persistent — `./scripts/backup.sh` เก็บให้อัตโนมัติ
(copy ขณะรัน: message ที่เข้ามาตอน 03:00 อาจไม่อยู่ใน backup รอบนั้น)
ถ้ามี queue สำคัญ
