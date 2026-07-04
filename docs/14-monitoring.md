# 14 — Monitoring Playbook

🎯 รวมวิธีใช้เครื่องมือ monitoring ทั้งชุดเมื่อเกิดเหตุจริง

## เครื่องมือแต่ละตัวใช้เมื่อไหร่

| อาการ | เปิดอะไร |
|-------|----------|
| ได้ Telegram alert เว็บล่ม | Uptime Kuma → ดูว่าล่มตัวเดียวหรือหลายตัว |
| เครื่องหน่วง "ตอนนี้" | Netdata (real-time per-second) |
| อยากรู้ "เมื่อคืนเกิดอะไร" | Grafana (ย้อนหลัง 30 วัน) |
| Container ตัวไหน error | Dozzle (`logs.<domain>`) ดู log สด |
| อยาก restart อะไรสักตัว | Portainer |

## Incident checklist

```text
1. Uptime Kuma  → ขอบเขต: ล่มตัวเดียว หรือทั้งเครื่อง?
2. ssh เข้าได้ไหม → ไม่ได้ = ดู VNC console ของ provider
3. Netdata      → CPU? RAM? Disk เต็ม? (df -h)
4. Dozzle       → log ของ container ที่ล่ม
5. Portainer    → restart container
6. แก้เสร็จ     → จด root cause ไว้ใน docs/incidents/ (สร้างเมื่อใช้ครั้งแรก)
```

## เช็คสุขภาพประจำอาทิตย์ (5 นาที)

- [ ] Disk ใช้ไป < 80% (`df -h`)
- [ ] Backup ล่าสุดมีจริง + ขนาดสมเหตุผล
- [ ] Grafana: แนวโน้ม RAM/CPU ไม่ค่อย ๆ ไต่ขึ้น (memory leak)
- [ ] `docker ps` — ไม่มีตัวไหน restart loop
- [ ] Uptime Kuma — uptime ≥ 99.9%
