# 21 — MinIO (v2.0)

🎯 S3 ของตัวเอง — ทางหนีถ้า R2 แพง หรืออยากเก็บไฟล์ไว้กับตัว

## R2 vs MinIO

| | Cloudflare R2 | MinIO (self-hosted) |
|--|---------------|---------------------|
| พื้นที่ | ไม่จำกัด ($0.015/GB) | จำกัดตามดิสก์ VPS |
| Egress | ฟรี | ผ่าน bandwidth VPS |
| ดูแล | ไม่ต้อง | ต้อง backup เอง |
| เหมาะกับ | media หนัก, public files | ไฟล์ internal, latency ต่ำ, ความเป็นส่วนตัว |

**คำแนะนำ: ใช้ R2 เป็นหลักต่อไป** — เปิด MinIO เมื่อมีเหตุ (R2 แพงขึ้น / ต้อง private จริง ๆ)

## ⚙️ วิธีทำ

```bash
# เพิ่ม MINIO_ROOT_USER / MINIO_ROOT_PASSWORD ใน .env
docker compose --env-file .env -f docker/docker-compose.storage.yml up -d
```

- Console: `https://minio.<BASE_DOMAIN>` → สร้าง bucket + access key ต่อ app
- App ชี้ endpoint `http://minio:9000` (ภายใน) หรือ `https://s3.<BASE_DOMAIN>` (ภายนอก)
- ย้ายจาก R2: แค่เปลี่ยน `AWS_ENDPOINT` + credentials — โค้ดเดิมทุกบรรทัด

## 🧪 ทดสอบ

```bash
docker exec minio mc ready local     # → healthy
```
