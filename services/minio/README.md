# MinIO (v2.0)

Self-hosted S3 — ทางหนีถ้า Cloudflare R2 แพงขึ้น หรืออยากเก็บไฟล์เอง
API เดียวกับ S3/R2 → app แค่เปลี่ยน endpoint ไม่ต้องแก้โค้ด

## Endpoints

```text
S3 API:   https://s3.<BASE_DOMAIN>       (ใน network backend: http://minio:9000)
Console:  https://minio.<BASE_DOMAIN>    (login ด้วย MINIO_ROOT_USER/PASSWORD)
```

## Start

```bash
docker compose --env-file ../../.env up -d
```

จากนั้นสร้าง bucket + access key ผ่าน Console (อย่าใช้ root credential ใน app —
สร้าง key แยกต่อ app แล้วจำกัด policy)

## ⚠️ ระวัง

- ไฟล์อยู่บนดิสก์ VPS (75GB) — ต่างจาก R2 ที่ไม่จำกัด
  ใช้กับไฟล์ที่ต้องการ latency ต่ำ/ความเป็นส่วนตัว ส่วน media หนัก ๆ ยังควรอยู่ R2
- volume `minio_data` = ข้อมูลทั้งหมด — ต้องอยู่ในแผน backup ถ้าใช้จริง
