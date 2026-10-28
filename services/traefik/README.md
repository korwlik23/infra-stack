# Traefik

Reverse proxy + automatic HTTPS (Let's Encrypt) สำหรับทุก service ใน stack

## Start

อยู่ใน core stack — รันจาก repo root (`install.sh` ทำให้แล้ว):

```bash
touch services/traefik/acme.json && chmod 600 services/traefik/acme.json
docker compose --env-file .env -f docker/docker-compose.core.yml up -d traefik
```

## เพิ่ม service ใหม่ให้มี HTTPS

ใส่ labels ใน compose ของ service นั้น แล้วต่อ network `proxy`:

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.myapp.rule=Host(`myapp.${BASE_DOMAIN}`)"
  - "traefik.http.routers.myapp.entrypoints=websecure"
  - "traefik.http.routers.myapp.tls.certresolver=letsencrypt"
  - "traefik.http.services.myapp.loadbalancer.server.port=8080"
networks:
  - proxy
```

## หมายเหตุ

- Static config อยู่ใน `command:` ของ `docker-compose.yml` — ACME email มาจาก
  `ACME_EMAIL` ใน `.env` (แก้ `.env` แล้ว `up -d traefik` ใหม่)
- Dynamic config (middleware ใช้ซ้ำ เช่น `security-headers@file`) อยู่ที่ `dynamic/`
- Dashboard: `https://traefik.<BASE_DOMAIN>` — เปลี่ยน basicauth hash ก่อนใช้
  (`htpasswd -nb admin <password>` จาก package `apache2-utils`; ใน compose ต้อง escape `$` เป็น `$$`)
- `acme.json` เก็บ certificate — ห้าม commit (อยู่ใน .gitignore แล้ว)

## Test / Rollback

```bash
docker logs traefik --tail 50                                    # ดู ACME ออก cert สำเร็จไหม
docker compose --env-file .env -f docker/docker-compose.core.yml stop traefik   # หยุด (cert ยังอยู่ใน acme.json)
```
