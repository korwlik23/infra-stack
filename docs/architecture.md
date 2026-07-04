# Architecture

## หลักคิด: 3 Layers

```text
Infrastructure  →  Platform  →  Application
```

| Layer | ทำครั้งเดียว/แชร์ | ประกอบด้วย |
|-------|------------------|-----------|
| **Infrastructure** | ทำครั้งเดียวต่อเครื่อง | Ubuntu, Docker, Traefik, PostgreSQL, Redis, Cloudflare, R2 |
| **Platform** | ทุก project แชร์ | Portainer, Netdata, Grafana, Prometheus, Uptime Kuma, Dozzle, Watchtower, Backup, CI/CD |
| **Application** | Deploy อิสระต่อ project | ZennuaFlow, Trex, PrintsHub, BDO, Content Center, n8n, AI Workers |

## ภาพรวมบนเครื่องเดียว (Stage 1)

```text
VPS (Contabo Singapore)
│
├── Traefik ── HTTPS ทุกโดเมน
│      ├── zennuaflow.com
│      ├── n8n.domain.com
│      ├── portainer.domain.com
│      ├── grafana.domain.com
│      ├── netdata.domain.com
│      ├── uptime.domain.com
│      └── logs.domain.com (Dozzle)
│
├── PostgreSQL ── database ต่อ project (network: backend)
├── Redis ────── cache / queue / session (network: backend)
├── Monitoring ─ Netdata, Prometheus, Grafana, Uptime Kuma
├── Backup ───── pg_dumpall + volumes → Cloudflare R2
└── projects/ ── app containers (network: proxy + backend)
```

## Docker Networks

| Network | ใคร | ทำไม |
|---------|-----|------|
| `proxy` | Traefik + ทุก service ที่มีโดเมน | Traefik route ได้เฉพาะที่อยู่ network นี้ |
| `backend` | PostgreSQL, Redis, app containers | database ไม่โดน expose ออก internet |
| `monitoring` | Prometheus, exporters, Grafana | แยก traffic metrics |

## หลักการ Modular

- **หนึ่ง service = หนึ่งโฟลเดอร์ = หนึ่ง `docker-compose.yml`** ใน `services/`
- ❌ ห้ามทำ docker-compose ยักษ์ไฟล์เดียวที่มีทุก service — พอถึง 30–40 services จะดูแลไม่ได้
- `docker/docker-compose.*.yml` เป็นแค่ตัวรวม (`include:`) ไม่ใช่ที่เขียน config
- แต่ละ project ใน `projects/` เป็นอิสระ — up/down/update ไม่กระทบตัวอื่น

## Scaling Stages

| Stage | รูปแบบ | เมื่อไหร่ |
|-------|--------|----------|
| 1 | 1 VPS ทุกอย่างเครื่องเดียว | ตอนนี้ |
| 2 | App Server + Database Server + AI Worker | เมื่อ RAM/CPU ตึง |
| 3 | Load Balancer + App ×N + Redis + DB + Storage | เมื่อ traffic โต |
| 4 | Kubernetes | อีกหลายปี |

รายละเอียดการย้าย stage ดู [18-scale.md](18-scale.md)
