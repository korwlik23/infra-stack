# redis-exporter

แปลง metrics ของ Redis ให้ Prometheus เก็บ (port 9121, internal เท่านั้น)
→ ใช้กับ Grafana dashboard **11835** (Redis Dashboard)

อยู่ใน monitoring stack แล้ว — start เดี่ยว:

```bash
# จาก repo root (/opt/infra-stack) — อยู่ใน monitoring stack
docker compose --env-file .env -f docker/docker-compose.monitoring.yml up -d redis-exporter
```

ทดสอบ: Prometheus → Status → Targets → job `redis` ต้อง UP
