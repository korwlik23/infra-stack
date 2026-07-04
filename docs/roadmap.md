# Roadmap

## 8 Phases (v1.0.0)

| Phase | งาน | สถานะ |
|-------|-----|-------|
| 1 | Requirement — [requirements.md](requirements.md) | ✅ |
| 2 | Architecture — [architecture.md](architecture.md) | ✅ |
| 3 | Folder Structure — docs/ docker/ services/ scripts/ templates/ projects/ monitoring/ backup/ environments/ | ✅ |
| 4 | Docker Base — networks, stack aggregation | ✅ |
| 5 | Core Services — Traefik, Portainer, PostgreSQL, Redis | ✅ |
| 6 | Monitoring — Netdata, Prometheus, Grafana, Uptime Kuma, Dozzle | ✅ |
| 7 | Automation — install, harden, update, backup, restore, create-project | ✅ |
| 8 | Documentation — คู่มือ 00–18 | ✅ |

## v2.0.0 — ✅ เสร็จแล้ว

- [x] pgAdmin + Redis Insight (tools stack)
- [x] postgres-exporter + redis-exporter → Grafana dashboards
- [x] Alertmanager → Telegram
- [x] CI/CD ไม่ใช้ GitHub Actions — deploy.sh + auto-deploy.sh ([19-cicd.md](19-cicd.md))
- [x] RabbitMQ (messaging stack)
- [x] MinIO (storage stack — ทางหนีถ้า R2 แพง)
- [x] Loki + Promtail (เลือกแทน ELK — ประหยัด RAM ~20 เท่า)
- [x] AI Worker template
- [x] Beszel — monitor หลาย server จากจอเดียว

## v2.1.0 — ✅ เสร็จแล้ว

- [x] Zero-downtime rolling deploy (`docker rollout` + healthcheck gate) — [25-zero-downtime.md](25-zero-downtime.md)
- [x] `rollback.sh` — กลับเวอร์ชันเก่าแบบ rolling
- [x] Templates: healthcheck + Traefik healthcheck labels

## ถัดไป (v2.x)

- [ ] **Deploy จริงบน Contabo Singapore** ตาม [00-introduction.md](00-introduction.md) ← ทำอันนี้ก่อน
- [ ] เปลี่ยน basicauth hash ทุกจุด (traefik/netdata/dozzle/redisinsight)
- [ ] ตั้ง Telegram bot + ใส่ token ใน alertmanager.yml (บนเซิร์ฟเวอร์)
- [ ] Import Grafana dashboards (1860, 193, 9628, 11835) แล้ว export JSON เก็บเข้า Git
- [ ] ซ้อม restore backup ครั้งแรก + จับเวลา disaster recovery
- [ ] วัด baseline การใช้ RAM/CPU เพื่อรู้จุด "ตึง" ก่อนถึง Stage 2

## v3.0 (อนาคตไกล)

- [ ] Stage 2: แยก Database Server / AI Worker Server ([18-scale.md](18-scale.md))
- [ ] ELK stack ถ้าย้ายไปเครื่องใหญ่และต้อง log analytics จริงจัง
- [ ] Kubernetes (Stage 4 — อีกหลายปีค่อยคิด)
