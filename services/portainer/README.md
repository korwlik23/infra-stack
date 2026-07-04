# Portainer

จัดการ Docker ทั้งเครื่องผ่าน Browser — containers, images, volumes, networks, logs

## Start

```bash
docker compose --env-file ../../.env up -d
```

เปิด `https://portainer.<BASE_DOMAIN>` แล้ว**สร้าง admin ทันที**
(ถ้าปล่อยเกิน 5 นาที Portainer จะล็อกตัวเอง ต้อง restart container)

## Test / Rollback

```bash
docker compose ps                       # ต้องเป็น running
docker compose down                     # ถอน (ข้อมูลอยู่ใน volume portainer_data)
docker volume rm portainer_portainer_data   # ลบข้อมูลถาวร (ระวัง!)
```
