#!/usr/bin/env bash
# ============================================================
# InfraStack installer — run on a fresh Ubuntu VPS as user `deploy`
# (after scripts/harden.sh — ลำดับเต็มใน TODO.md)
#   cd /opt/infra-stack && ./install.sh
# Installs Docker (+rollout plugin), creates shared networks,
# prepares .env, then brings up the core stack.
# ============================================================
set -euo pipefail

cd "$(dirname "$0")"

echo "=============================================="
echo " InfraStack v$(cat VERSION) — installer"
echo "=============================================="

# ── 1. Docker ────────────────────────────────────────
if ! command -v docker >/dev/null 2>&1; then
  echo "[1/6] Installing Docker…"
  curl -fsSL https://get.docker.com | sh
  sudo systemctl enable --now docker
else
  echo "[1/6] Docker already installed: $(docker --version)"
fi

# ให้ user ปัจจุบันใช้ docker ได้โดยไม่ต้อง sudo (สิทธิ์มีผลหลัง login ใหม่)
if [ "$(id -u)" -ne 0 ] && ! id -nG "$USER" | grep -qw docker; then
  echo "Adding $USER to docker group…"
  sudo usermod -aG docker "$USER"
  echo ""
  echo "⚠️  สิทธิ์ group docker มีผลตอน login ใหม่เท่านั้น:"
  echo "    exit → ssh เข้ามาใหม่ → cd /opt/infra-stack && ./install.sh"
  exit 0
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "ERROR: docker compose plugin missing. Install docker-compose-plugin first." >&2
  exit 1
fi

# ── 2. docker-rollout plugin (zero-downtime deploy) ──
# ห้ามเช็คด้วย `docker rollout --help` — Docker 29 พิมพ์ help รวมแล้ว exit 0
# ทั้งที่ไม่มี plugin (เจอจริงตอน deploy ครั้งแรก) → เช็คไฟล์ตรง ๆ
ROLLOUT_PLUGIN="$HOME/.docker/cli-plugins/docker-rollout"
if [ -x "$ROLLOUT_PLUGIN" ]; then
  echo "[2/6] docker-rollout already installed"
else
  echo "[2/6] Installing docker-rollout plugin (zero-downtime deploy)…"
  mkdir -p "$HOME/.docker/cli-plugins"
  curl -fsSL https://raw.githubusercontent.com/wowu/docker-rollout/main/docker-rollout \
    -o "$HOME/.docker/cli-plugins/docker-rollout"
  chmod +x "$HOME/.docker/cli-plugins/docker-rollout"
fi

# ── 3. Shared networks ───────────────────────────────
echo "[3/6] Creating shared networks (proxy, backend, monitoring)…"
docker network inspect proxy >/dev/null 2>&1 || docker network create proxy
docker network inspect backend >/dev/null 2>&1 || docker network create backend
docker network inspect monitoring >/dev/null 2>&1 || docker network create monitoring

# ── 4. Environment file ──────────────────────────────
if [ ! -f .env ]; then
  # หยุดแทนการรอ Enter — ระหว่างรอแก้ .env ใน terminal เดียวกันไม่ได้
  cp .env.example .env
  chmod 600 .env
  echo "[4/6] Created .env from .env.example — แก้ค่าแล้วรัน ./install.sh อีกครั้ง:"
  echo ""
  echo "  nano .env   # BASE_DOMAIN, ACME_EMAIL และรหัสผ่านทุกตัวที่เป็น CHANGE_ME"
  exit 0
else
  echo "[4/6] .env already exists — keeping it."
fi

env_val() { grep -E "^$1=" .env | head -1 | cut -d= -f2- | tr -d ' ' || true; }

# ค่าที่ core stack ต้องใช้ — ถ้ายังเป็น example.com จะไม่ได้ cert ทั้งเครื่อง
# (Let's Encrypt ปฏิเสธ @example.com) → หยุดก่อน start ดีกว่าขึ้นมาแบบใช้ไม่ได้
BASE_DOMAIN_VAL="$(env_val BASE_DOMAIN)"
ACME_EMAIL_VAL="$(env_val ACME_EMAIL)"
if [ -z "$BASE_DOMAIN_VAL" ] || [ "$BASE_DOMAIN_VAL" = "example.com" ]; then
  echo "ERROR: BASE_DOMAIN ใน .env ยังเป็นค่า default — แก้แล้วรัน ./install.sh ใหม่" >&2
  exit 1
fi
case "$ACME_EMAIL_VAL" in
  ""|*@example.com)
    echo "ERROR: ACME_EMAIL ใน .env ยังเป็นค่า default — แก้แล้วรัน ./install.sh ใหม่" >&2
    exit 1 ;;
esac

# รหัสผ่านไม่ได้ใช้ใน core stack แต่ต้องตั้ง "ก่อน" start database stack ครั้งแรก
# postgres บันทึกรหัสลง volume ตอน init — แก้ .env ทีหลังจะไม่มีผล (auth failed)
for key in POSTGRES_PASSWORD REDIS_PASSWORD GRAFANA_ADMIN_PASSWORD; do
  if [ "$(env_val "$key")" = "CHANGE_ME" ]; then
    echo "⚠️  $key ยังเป็น CHANGE_ME — ตั้งค่าจริงก่อน start database/monitoring stack"
  fi
done

# Traefik อ่าน ACME email จาก .env ตรง ๆ (CLI flag ใน compose) — ไม่แก้ไฟล์ใน Git
echo "      Traefik ACME email → $ACME_EMAIL_VAL"

# ── 5. Traefik ACME storage ──────────────────────────
echo "[5/6] Preparing Traefik certificate storage…"
touch services/traefik/acme.json
chmod 600 services/traefik/acme.json

# ── 6. Core stack ────────────────────────────────────
echo "[6/6] Starting core stack (Traefik + Portainer)…"
docker compose --env-file .env -f docker/docker-compose.core.yml up -d

echo ""
echo "✅ Core stack running."
echo "Next steps:"
echo "  docker compose --env-file .env -f docker/docker-compose.database.yml up -d"
echo "  docker compose --env-file .env -f docker/docker-compose.monitoring.yml up -d"
echo "  ./scripts/create-project.sh <name> <laravel|nextjs|n8n|ai-worker>"
