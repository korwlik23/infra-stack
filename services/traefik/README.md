# Traefik

Reverse proxy + automatic HTTPS (Let's Encrypt) สำหรับทุก service ใน stack

## Start

```bash
touch acme.json && chmod 600 acme.json
docker compose --env-file ../../.env up -d
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

- แก้ `email` ใน `traefik.yml` ให้ตรงกับ `ACME_EMAIL`
- Dashboard: `https://traefik.<BASE_DOMAIN>` — เปลี่ยน basicauth hash ก่อนใช้
  (`htpasswd -nb admin <password>`; ใน compose ต้อง escape `$` เป็น `$$`)
- `acme.json` เก็บ certificate — ห้าม commit (อยู่ใน .gitignore แล้ว)

## Test / Rollback

```bash
docker logs traefik --tail 50      # ดู ACME ออก cert สำเร็จไหม
docker compose down                # ถอนการติดตั้ง (cert ยังอยู่ใน acme.json)
```
