# redis-exporter

แปลง metrics ของ Redis ให้ Prometheus เก็บ (port 9121, internal เท่านั้น)
→ ใช้กับ Grafana dashboard **11835** (Redis Dashboard)

อยู่ใน monitoring stack แล้ว — start เดี่ยว:

```bash
docker compose --env-file ../../.env up -d
```

ทดสอบ: Prometheus → Status → Targets → job `redis` ต้อง UP
