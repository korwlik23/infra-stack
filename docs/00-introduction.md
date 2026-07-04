# 00 — Introduction

InfraStack คือ **"ระบบปฏิบัติการของ Server" (Server Operating Platform)**
ไม่ใช่โปรเจกต์ Laravel ไม่ใช่โปรเจกต์ Docker — เป็นมาตรฐานสำหรับทุก VPS ของเรา

## ทำไมต้องมี

- ซื้อ VPS ใหม่ (Contabo / GreenCloud / Hetzner / Oracle) → clone + `./install.sh` → พร้อมใน 10–15 นาที
- ทุกเครื่องมีโครงสร้าง เครื่องมือ และมาตรฐานเดียวกัน
- ลดเวลาติดตั้งจากหลายชั่วโมงเหลือไม่กี่นาที
- เป็นทรัพย์สิน (Asset) ระยะยาวของบริษัท

## ลำดับการอ่าน

| ขั้น | คู่มือ |
|------|--------|
| เตรียมเครื่อง | [01-server-setup.md](01-server-setup.md) → [02-security.md](02-security.md) |
| ฐาน | [03-docker.md](03-docker.md) → [04-traefik.md](04-traefik.md) → [05-portainer.md](05-portainer.md) |
| Database | [06-postgresql.md](06-postgresql.md) → [07-redis.md](07-redis.md) |
| Monitoring | [08-netdata.md](08-netdata.md) → [09-grafana.md](09-grafana.md) → [10-uptime-kuma.md](10-uptime-kuma.md) |
| Network/Storage | [11-cloudflare.md](11-cloudflare.md) → [12-r2.md](12-r2.md) |
| Ops | [13-backup.md](13-backup.md) → [14-monitoring.md](14-monitoring.md) |
| Deploy | [15-deploy-laravel.md](15-deploy-laravel.md) → [16-deploy-nextjs.md](16-deploy-nextjs.md) → [17-deploy-n8n.md](17-deploy-n8n.md) |
| CI/CD | [19-cicd.md](19-cicd.md) — auto deploy ฟรี ไม่ใช้ GitHub Actions · [25-zero-downtime.md](25-zero-downtime.md) — deploy ไม่ให้เว็บดับ |
| v2.0 (เปิดเมื่อต้องการ) | [20-rabbitmq.md](20-rabbitmq.md) · [21-minio.md](21-minio.md) · [22-loki.md](22-loki.md) · [23-beszel.md](23-beszel.md) · [24-ai-worker.md](24-ai-worker.md) |
| อนาคต | [18-scale.md](18-scale.md) |

ทุกบทพยายามตอบ: 🎯 เป้าหมาย · 🤔 ทำไม · ⚙️ วิธีทำ · ⚠️ ข้อควรระวัง · 🧪 วิธีทดสอบ · 🔄 Rollback
