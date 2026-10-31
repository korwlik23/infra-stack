# 03 — Docker

🎯 Docker + Compose plugin พร้อมใช้ และมี shared networks

## ⚙️ วิธีทำ

```bash
# prepare.sh (ช่วง A, root) ติด Docker + ใส่ deploy ใน group docker ก่อน `su - deploy`
./install.sh        # (deploy) สร้าง network proxy/backend/monitoring + ทุก stack
```

หรือ manual:

```bash
curl -fsSL https://get.docker.com | sh
sudo systemctl enable --now docker
sudo usermod -aG docker deploy      # ให้ user deploy ใช้ docker ได้ (logout/login ใหม่)
docker network create proxy
docker network create backend
docker network create monitoring    # ขาดตัวนี้ monitoring stack ขึ้นไม่ได้ (external network not found)
```

## 🧪 ทดสอบ

```bash
docker --version && docker compose version   # ต้อง ≥ 2.20 (ใช้ include:)
docker network ls | grep -E "proxy|backend|monitoring"
docker run --rm hello-world
```

## ⚠️ ระวัง

- การใส่ user เข้า group `docker` = ให้สิทธิ์เทียบเท่า root — ใช้กับ user ที่ไว้ใจเท่านั้น
- อย่า expose Docker socket (`/var/run/docker.sock`) ให้ container ที่ไม่จำเป็น
  ใน stack นี้มีเฉพาะ: Traefik, Portainer, Netdata, Dozzle, Promtail, Beszel agent (ทั้งหมด :ro)
  และ Watchtower (read-write — ต้องสั่ง recreate container); cAdvisor mount `/var/run` แบบ :ro
