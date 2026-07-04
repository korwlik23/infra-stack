# Requirements

## The stack must support

- Laravel (app + queue worker + scheduler)
- Next.js (standalone)
- n8n (automation, PostgreSQL backend, HTTPS webhooks)
- PostgreSQL (database ต่อ project, ไม่ expose ออก internet)
- Redis (cache / queue / session, มี password)
- Cloudflare (DNS, SSL, Proxy, WAF)
- Cloudflare R2 (object storage: รูป, วิดีโอ, uploads, backup)
- Traefik (reverse proxy + Let's Encrypt อัตโนมัติ)
- Monitoring (Netdata, Prometheus, Grafana, Uptime Kuma + Telegram alert)
- Backup (PostgreSQL + volumes, เก็บ offsite ที่ R2, ซ้อม restore ได้)
- CI/CD (GitHub → auto deploy)
- Scaling (Stage 1 → 4 โดยไม่รื้อโครงสร้าง)

## Non-functional

| ข้อ | เกณฑ์ |
|-----|-------|
| Reproducible | VPS ใหม่พร้อมใช้ใน 10–15 นาที ด้วย `install.sh` |
| Modular | เปิด/ปิด/อัปเดต service แยกกันได้ |
| Secure by default | ไม่มี secret ใน Git, database ไม่ expose, UFW + Fail2ban, SSH key only |
| Observable | เห็น CPU/RAM/Disk/Container/Logs ผ่าน browser ทั้งหมด |
| Recoverable | เครื่องพัง → เครื่องใหม่ + restore backup = กลับมาได้ |
| Versioned | Infrastructure มี version + changelog เหมือน software |

## สเปกเครื่องขั้นต่ำ

```text
ขั้นต่ำ:  4 vCPU / 8GB RAM / 60-75GB NVMe
แนะนำ:   6 vCPU+ / 12GB RAM+ / 100GB NVMe+
```

เป้าหมายแรก: Contabo Cloud VPS (Singapore) — ถ้ามี workflow สร้างคลิป/FFmpeg/
browser automation พร้อมกันเยอะ ๆ เครื่อง 8GB จะเริ่มตึง
