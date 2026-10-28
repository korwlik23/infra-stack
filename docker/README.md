# docker/ — Stack Aggregation

รวม service ทีละกลุ่มด้วย Compose `include:` (ต้องใช้ Docker Compose ≥ 2.20)
Source of truth ของแต่ละ service อยู่ที่ `services/<name>/docker-compose.yml`

| Stack | ไฟล์ | Compose project | ประกอบด้วย |
|-------|------|-----------------|-----------|
| Core | `docker-compose.core.yml` | `infra-core` | Traefik, Portainer |
| Database | `docker-compose.database.yml` | `infra-database` | PostgreSQL, Redis |
| Monitoring | `docker-compose.monitoring.yml` | `infra-monitoring` | Netdata, Prometheus+exporters, Alertmanager, Grafana, Loki+Promtail, Uptime Kuma, Dozzle, Watchtower, Beszel |
| Tools | `docker-compose.tools.yml` | `infra-tools` | pgAdmin, Redis Insight |
| Messaging (v2.0) | `docker-compose.messaging.yml` | `infra-messaging` | RabbitMQ |
| Storage (v2.0) | `docker-compose.storage.yml` | `infra-storage` | MinIO |

ลำดับการ start: **Core → Database → Monitoring** (Traefik ต้องมาก่อนเพราะสร้าง route ให้ตัวอื่น)
Tools / Messaging / Storage เปิดเมื่อต้องการเท่านั้น — ไม่บังคับ

ทุกคำสั่งรันจาก repo root (`/opt/infra-stack`)

ต้องการ start / restart แค่บาง service? ระบุชื่อ service ต่อท้าย stack ของมัน:

```bash
docker compose --env-file .env -f docker/docker-compose.database.yml up -d redis
```

⚠️ อย่ารัน `docker compose up` จากในโฟลเดอร์ `services/<name>/` ตรง ๆ — จะได้ compose
project ใหม่ (ชื่อโฟลเดอร์) ที่ชื่อ container ชนกับ stack ที่รันอยู่ (`container name … is already in use`)

แต่ละ stack มี compose project ของตัวเอง จึงไม่มี WARN "Found orphan containers" ข้าม stack
และ `--remove-orphans` ของ stack หนึ่งไม่แตะ container ของ stack อื่น

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

## ⚠️ อัปเกรดเครื่องที่ติดตั้งก่อนแยก project ต่อ stack (ครั้งเดียว)

เครื่องที่ติดตั้งก่อนเวอร์ชันนี้รันทุก stack ใต้ project เดียวชื่อ `docker` และ volume ชื่อ
`docker_<name>` (เช่น `docker_postgres_data`) — ตอนนี้ volume ถูก pin เป็น `<name>`
(เช่น `postgres_data`) ถ้า `git pull` แล้ว up เลยจะเจอ:

- `container name "/postgres" is already in use` (container เดิมยังอยู่ใต้ project `docker`) หรือ
- ถ้าลบ container เดิมทิ้งเอง → stack ขึ้นมากับ **volume ใหม่ที่ว่างเปล่า** (database ว่าง)

ทำตามนี้ก่อน up stack ใด ๆ:

```bash
cd /opt/infra-stack
./scripts/backup.sh                                    # backup ก่อนเสมอ
git checkout -- services/traefik/traefik.yml 2>/dev/null || true   # ไฟล์นี้ถูกลบจาก repo แล้ว (email ย้ายไป .env)
git pull
./scripts/migrate-volumes.sh                           # stop container เดิม + copy docker_<name> → <name>
docker compose --env-file .env -f docker/docker-compose.core.yml up -d
docker compose --env-file .env -f docker/docker-compose.database.yml up -d
docker compose --env-file .env -f docker/docker-compose.monitoring.yml up -d
# + tools / messaging / storage ถ้าเคยเปิดไว้
```

ตรวจว่าข้อมูลครบ (เช่น `docker exec -it postgres sh -c 'psql -U "$POSTGRES_USER" -c "\l"'`)
แล้วค่อยลบ volume เดิม: `docker volume rm docker_<name>`
