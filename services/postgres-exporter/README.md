# postgres-exporter

แปลง metrics ของ PostgreSQL ให้ Prometheus เก็บ (port 9187, internal เท่านั้น)
→ ใช้กับ Grafana dashboard **9628** (PostgreSQL Database)

อยู่ใน monitoring stack แล้ว — start เดี่ยว:

```bash
# จาก repo root (/opt/infra-stack) — อยู่ใน monitoring stack
docker compose --env-file .env -f docker/docker-compose.monitoring.yml up -d postgres-exporter
```

ทดสอบ: Prometheus → Status → Targets → job `postgres` ต้อง UP
