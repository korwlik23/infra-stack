# Netdata

Real-time monitoring ของทั้งเครื่อง — CPU, RAM, Disk, Network, Docker,
PostgreSQL, Redis (auto-detect) ดูผ่าน `https://netdata.<BASE_DOMAIN>`

## Start

```bash
docker compose --env-file ../../.env up -d
```

## หมายเหตุ

- Dashboard ถูกป้องกันด้วย basicauth ผ่าน Traefik — เปลี่ยน hash ก่อนใช้
- Netdata เห็นข้อมูล host เพราะ mount `/proc`, `/sys` แบบ read-only
- ถ้ามีหลาย server ในอนาคต ค่อยต่อ Netdata Cloud หรือใช้ Beszel รวมจอเดียว
