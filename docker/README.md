# docker/ — Stack Aggregation

รวม service ทีละกลุ่มด้วย Compose `include:` (ต้องใช้ Docker Compose ≥ 2.20)
Source of truth ของแต่ละ service อยู่ที่ `services/<name>/docker-compose.yml`

| Stack | ไฟล์ | ประกอบด้วย |
|-------|------|-----------|
| Core | `docker-compose.core.yml` | Traefik, Portainer |
| Database | `docker-compose.database.yml` | PostgreSQL, Redis |
| Monitoring | `docker-compose.monitoring.yml` | Netdata, Prometheus+exporters, Alertmanager, Grafana, Loki+Promtail, Uptime Kuma, Dozzle, Watchtower, Beszel |
| Tools | `docker-compose.tools.yml` | pgAdmin, Redis Insight |
| Messaging (v2.0) | `docker-compose.messaging.yml` | RabbitMQ |
| Storage (v2.0) | `docker-compose.storage.yml` | MinIO |

ลำดับการ start: **Core → Database → Monitoring** (Traefik ต้องมาก่อนเพราะสร้าง route ให้ตัวอื่น)
Tools / Messaging / Storage เปิดเมื่อต้องการเท่านั้น — ไม่บังคับ

ต้องการเปิดแค่บาง service? รันตรงที่โฟลเดอร์ service นั้นได้เลย:

```bash
docker compose --env-file ../../.env -f services/redis/docker-compose.yml up -d
```

## ⚠️ เรื่อง WARN "Found orphan containers"

ทุก stack ในโฟลเดอร์นี้แชร์ compose project เดียวกัน — เวลา `up -d` stack หนึ่ง
มันจะเห็น container ของ stack อื่นแล้วเตือนว่าเป็น "orphan" **ซึ่งปกติ ปล่อยผ่านได้**

**ห้ามเติม `--remove-orphans` ตามที่ข้อความชวนเด็ดขาด** — มันจะลบ container
ของ stack อื่นทิ้งทั้งหมด (เช่น up database แล้วใส่ flag นี้ = monitoring หายยกแผง)

## การอัปเดต repo บนเซิร์ฟเวอร์ (git pull)

```bash
cd /opt/infra-stack
git pull
./scripts/update.sh        # pull image + up -d ตาม stack
```

ถ้าเคยแก้ไฟล์บนเซิร์ฟเวอร์ด้วย nano แล้ว pull ชน conflict:
ไฟล์ config ทั่วไปให้ใช้ของ repo (`git checkout -- <ไฟล์>` ก่อน pull)
**ยกเว้นไฟล์ที่มี secret จริง** (เช่น alertmanager.yml ที่ใส่ token แล้ว) —
สำรองไว้ก่อน pull แล้วค่อย copy กลับ
