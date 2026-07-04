# __PROJECT__ (Next.js)

Next.js standalone container ต่อ Traefik (HTTPS อัตโนมัติ) — image ควร build
ด้วย `output: "standalone"` ใน `next.config.js` แล้ว expose port 3000

## Deploy

```bash
nano .env
docker compose up -d
```

DNS: เพิ่ม record `__PROJECT__.<domain>` ชี้ server IP ใน Cloudflare (Proxied)
