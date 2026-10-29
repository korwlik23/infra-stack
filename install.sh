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
  echo "[1/8] Installing Docker…"
  curl -fsSL https://get.docker.com | sh
  sudo systemctl enable --now docker
else
  echo "[1/8] Docker already installed: $(docker --version)"
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
  echo "[2/8] docker-rollout already installed"
else
  echo "[2/8] Installing docker-rollout plugin (zero-downtime deploy)…"
  mkdir -p "$HOME/.docker/cli-plugins"
  curl -fsSL https://raw.githubusercontent.com/wowu/docker-rollout/main/docker-rollout \
    -o "$HOME/.docker/cli-plugins/docker-rollout"
  chmod +x "$HOME/.docker/cli-plugins/docker-rollout"
fi

# ── 3. Shared networks ───────────────────────────────
echo "[3/8] Creating shared networks (proxy, backend, monitoring)…"
docker network inspect proxy >/dev/null 2>&1 || docker network create proxy
docker network inspect backend >/dev/null 2>&1 || docker network create backend
docker network inspect monitoring >/dev/null 2>&1 || docker network create monitoring

# openssl ใช้สุ่มรหัสผ่าน + สร้าง basicauth hash (Ubuntu มีมาให้แล้ว)
if ! command -v openssl >/dev/null 2>&1; then
  echo "ERROR: ไม่มี openssl — ติดตั้งก่อน: sudo apt-get install -y openssl แล้วรัน ./install.sh ใหม่" >&2
  exit 1
fi

env_val() { grep -E "^$1=" .env | head -1 | cut -d= -f2- | tr -d ' \r' || true; }

# volume ที่ "จำรหัสผ่านไว้แล้ว" ของแต่ละ key — postgres/grafana/pgadmin/rabbitmq ตั้งรหัส
# ตอน init ครั้งแรกเท่านั้น redis/minio มี project ที่ copy รหัสไปแล้ว → ถ้า volume มีอยู่
# ห้ามสุ่มใหม่ ไม่งั้นรหัสใน .env จะไม่ตรงของจริง (auth failed)
password_volume() {
  case "$1" in
    POSTGRES_PASSWORD)      echo postgres_data ;;
    REDIS_PASSWORD)         echo redis_data ;;
    GRAFANA_ADMIN_PASSWORD) echo grafana_data ;;
    PGADMIN_PASSWORD)       echo pgadmin_data ;;
    RABBITMQ_PASSWORD)      echo rabbitmq_data ;;
    MINIO_ROOT_PASSWORD)    echo minio_data ;;
    *)                      echo "" ;;
  esac
}

# สุ่มรหัสให้ทุก *_PASSWORD ที่ยังเป็น CHANGE_ME — มือใหม่ไม่ต้องตั้งเองทีละตัว และไม่มีทาง
# เผลอ start database ด้วยรหัส CHANGE_ME (postgres จะจำรหัสนั้นถาวร)
# hex = ไม่มีอักขระพิเศษ → ใส่ใน URL/DSN (DATABASE_URL, REDIS_URL) ได้โดยไม่ต้อง encode
fill_passwords() {
  local key vol generated="" skipped=""
  # .env เก่าก่อนมี key เหล่านี้ → เติมให้ (basicauth กลาง + รหัสเข้ารหัส backup secrets)
  local kv
  for kv in DASHBOARD_USER=admin DASHBOARD_PASSWORD=CHANGE_ME BACKUP_ENCRYPTION_PASSWORD=CHANGE_ME; do
    grep -qE "^${kv%%=*}=" .env || printf '\n%s\n' "$kv" >> .env
  done
  for key in $(grep -E '^[A-Z0-9_]+_PASSWORD=CHANGE_ME$' .env | cut -d= -f1); do
    vol="$(password_volume "$key")"
    if [ -n "$vol" ] && { docker volume inspect "$vol" >/dev/null 2>&1 \
                          || docker volume inspect "docker_$vol" >/dev/null 2>&1; }; then
      skipped="$skipped $key"
      continue
    fi
    sed -i "s|^$key=CHANGE_ME\$|$key=$(openssl rand -hex 24)|" .env
    generated="$generated $key"
  done
  [ -z "$generated" ] || echo "      สุ่มรหัสผ่านให้แล้ว:$generated  (ดูได้ด้วย: grep PASSWORD .env)"
  [ -z "$skipped" ] || echo "⚠️  ไม่ได้สุ่ม:$skipped — service นี้มีข้อมูลอยู่แล้วและจำรหัสเดิมไว้ ตั้งใน .env ให้ตรงของจริงเอง"
}

# ── 4. Environment file ──────────────────────────────
if [ ! -f .env ]; then
  # หยุดแทนการรอ Enter — ระหว่างรอแก้ .env ใน terminal เดียวกันไม่ได้
  cp .env.example .env
  chmod 600 .env
  echo "[4/8] Created .env from .env.example"
  fill_passwords
  echo ""
  echo "  แก้แค่ 2 ค่า แล้วรัน ./install.sh อีกครั้ง:"
  echo "  nano .env   # BASE_DOMAIN = โดเมนของคุณ, ACME_EMAIL = อีเมลจริง (รหัสผ่านสุ่มให้แล้ว)"
  exit 0
else
  echo "[4/8] .env already exists — keeping it."
  fill_passwords
fi

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

# เหลือ CHANGE_ME ได้เฉพาะตัวที่ fill_passwords ข้าม (มีข้อมูลเดิม) — ย้ำอีกรอบก่อนไปต่อ
for key in $(grep -E '^[A-Z0-9_]+_PASSWORD=' .env | cut -d= -f1); do
  if [ "$(env_val "$key")" = "CHANGE_ME" ]; then
    echo "⚠️  $key ยังเป็น CHANGE_ME — ตั้งให้ตรงรหัสจริงของ service ก่อน start stack นั้น"
  fi
done

# Traefik อ่าน ACME email จาก .env ตรง ๆ (CLI flag ใน compose) — ไม่แก้ไฟล์ใน Git
echo "      Traefik ACME email → $ACME_EMAIL_VAL"

# ── 5. Dashboard basicauth ───────────────────────────
# หน้าแอดมินที่ไม่มี login ของตัวเอง (Traefik dashboard, Netdata, Dozzle, Redis Insight)
# ใช้ middleware กลาง dashboard-auth@file — สร้างใหม่จาก .env ทุกครั้งที่รัน install.sh
# ไฟล์อยู่นอก Git (.gitignore): ไม่ต้องแก้ compose เอง ไม่ต้อง escape $ และ git pull ไม่ชน
echo "[5/8] Writing dashboard login (DASHBOARD_USER / DASHBOARD_PASSWORD)…"
DASH_USER="$(env_val DASHBOARD_USER)"
DASH_USER="${DASH_USER:-admin}"
# อ่านรหัสแบบไม่ตัดช่องว่าง (env_val ตัด) — ตัดแค่ quote ครอบและ \r
DASH_PASS="$(grep -E '^DASHBOARD_PASSWORD=' .env | head -1 | cut -d= -f2- | tr -d '\r' || true)"
case "$DASH_PASS" in
  \"*\"|\'*\') DASH_PASS="${DASH_PASS:1:-1}" ;;
esac
if ! [[ "$DASH_USER" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "ERROR: DASHBOARD_USER ใน .env ใช้ได้แค่ A-Z a-z 0-9 . _ - — แก้แล้วรัน ./install.sh ใหม่" >&2
  exit 1
fi
if [ -z "$DASH_PASS" ] || [ "$DASH_PASS" = "CHANGE_ME" ]; then
  echo "ERROR: DASHBOARD_PASSWORD ใน .env ว่าง — ใส่รหัสแล้วรัน ./install.sh ใหม่" >&2
  exit 1
fi
# ส่งรหัสทาง stdin — ไม่ให้โผล่ใน argument (ps เห็น)
DASH_HASH="$(printf '%s\n' "$DASH_PASS" | openssl passwd -apr1 -stdin)"
(
  umask 077
  cat > services/traefik/dynamic/auth.yml <<EOF
# สร้างโดย install.sh จาก DASHBOARD_USER / DASHBOARD_PASSWORD ใน .env
# ห้ามแก้มือ ห้าม commit — เปลี่ยนรหัส: แก้ .env แล้วรัน ./install.sh (Traefik โหลดใหม่เอง)
http:
  middlewares:
    dashboard-auth:
      basicAuth:
        users:
          - "$DASH_USER:$DASH_HASH"
EOF
)

# ── 6. DNS ───────────────────────────────────────────
# core stack ขอ cert ทันทีที่ start — ไม่มี record = ล้มซ้ำจน Let's Encrypt แบน ~1 ชม.
echo "[6/8] Checking DNS records for core stack…"
./scripts/check-dns.sh core

# ── 7. Traefik ACME storage ──────────────────────────
echo "[7/8] Preparing Traefik certificate storage…"
touch services/traefik/acme.json
chmod 600 services/traefik/acme.json

# ── 8. Core stack ────────────────────────────────────
echo "[8/8] Starting core stack (Traefik + Portainer)…"
docker compose --env-file .env -f docker/docker-compose.core.yml up -d

echo ""
echo "✅ Core stack running."
echo "หน้าแอดมิน (Traefik / Netdata / Dozzle / Redis Insight): user = $DASH_USER"
echo "  รหัส = DASHBOARD_PASSWORD ใน .env   (ดู: grep DASHBOARD_PASSWORD .env)"
echo ""
echo "⚠️  จด BACKUP_ENCRYPTION_PASSWORD เก็บนอกเครื่อง (password manager) — ถ้าเครื่องพัง"
echo "   ไม่มีรหัสนี้ = เปิด backup ของ .env/รหัสผ่านไม่ได้   (ดู: grep BACKUP_ENCRYPTION_PASSWORD .env)"
echo ""
echo "Next steps:"
echo "  docker compose --env-file .env -f docker/docker-compose.database.yml up -d"
echo "  ./scripts/check-dns.sh monitoring     # เช็ค DNS ก่อนเปิด monitoring"
echo "  docker compose --env-file .env -f docker/docker-compose.monitoring.yml up -d"
echo "  ./scripts/create-project.sh <name> <laravel|nextjs|n8n|ai-worker>"
echo "  ตั้ง backup รายวัน + ส่งขึ้น R2: docs/13-backup.md"
