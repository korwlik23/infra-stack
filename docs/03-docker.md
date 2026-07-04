# 03 — Docker

🎯 Docker + Compose plugin พร้อมใช้ และมี shared networks

## ⚙️ วิธีทำ

```bash
./install.sh        # ติดตั้ง Docker + สร้าง network proxy/backend + up core stack
```

หรือ manual:

```bash
curl -fsSL https://get.docker.com | sh
sudo systemctl enable --now docker
sudo usermod -aG docker deploy      # ให้ user deploy ใช้ docker ได้ (logout/login ใหม่)
docker network create proxy
docker network create backend
```

## 🧪 ทดสอบ

```bash
docker --version && docker compose version   # ต้อง ≥ 2.20 (ใช้ include:)
docker network ls | grep -E "proxy|backend"
docker run --rm hello-world
```

## ⚠️ ระวัง

- การใส่ user เข้า group `docker` = ให้สิทธิ์เทียบเท่า root — ใช้กับ user ที่ไว้ใจเท่านั้น
- อย่า expose Docker socket (`/var/run/docker.sock`) ให้ container ที่ไม่จำเป็น
  ใน stack นี้มีเฉพาะ: Traefik, Portainer, Netdata, Dozzle, Watchtower (ทั้งหมด :ro ยกเว้น Watchtower)
