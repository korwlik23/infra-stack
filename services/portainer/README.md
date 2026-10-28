# Portainer

จัดการ Docker ทั้งเครื่องผ่าน Browser — containers, images, volumes, networks, logs

## Start

```bash
# จาก repo root (/opt/infra-stack) — อยู่ใน core stack
docker compose --env-file .env -f docker/docker-compose.core.yml up -d portainer
```

เปิด `https://portainer.<BASE_DOMAIN>` แล้ว**สร้าง admin ทันที**
(ถ้าปล่อยเกิน 5 นาที Portainer จะล็อกตัวเอง ต้อง restart container)

## Test / Rollback

```bash
docker compose --env-file .env -f docker/docker-compose.core.yml ps  # ต้องเป็น running
docker compose --env-file .env -f docker/docker-compose.core.yml stop portainer   # หยุด (ข้อมูลอยู่ใน volume portainer_data)
docker volume rm portainer_data   # ลบข้อมูลถาวร (ระวัง!)
```
