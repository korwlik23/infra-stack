# Netdata

Real-time monitoring ของทั้งเครื่อง — CPU, RAM, Disk, Network, Docker,
PostgreSQL, Redis (auto-detect) ดูผ่าน `https://netdata.<BASE_DOMAIN>`

## Start

```bash
# จาก repo root (/opt/infra-stack) — อยู่ใน monitoring stack
infra up monitoring netdata
```

## หมายเหตุ

- Dashboard ถูกป้องกันด้วย basicauth กลางของ Traefik (`dashboard-auth@file`) — login ด้วย
  `DASHBOARD_USER` / `DASHBOARD_PASSWORD` ใน `.env` (install.sh สร้างให้)
- Netdata เห็นข้อมูล host เพราะ mount `/proc`, `/sys` แบบ read-only
- ถ้ามีหลาย server ในอนาคต ค่อยต่อ Netdata Cloud หรือใช้ Beszel รวมจอเดียว
