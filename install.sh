#!/usr/bin/env bash
# ============================================================
# InfraStack — ช่วง B: ติดตั้งระบบ (รันด้วย user deploy หลัง prepare.sh / scripts/harden.sh)
#   cd /opt/infra-stack && ./install.sh
# รอบเดียวจบ: ถามโดเมน/อีเมล/n8n → Docker → รหัสผ่าน → database → monitoring → n8n
# → รอ DNS (โชว์ตาราง record ที่ต้องสร้าง) → เปิด Traefik + HTTPS → สรุป URL/รหัส
# รันซ้ำได้: ขั้นที่ทำแล้วจะถูกข้าม ทำต่อจากที่ค้าง
# ไม่ถามอะไร (อัตโนมัติ): INFRA_DOMAIN=… INFRA_EMAIL=… [INFRA_N8N_DOMAIN=…] ./install.sh
# ============================================================
set -euo pipefail

cd "$(dirname "$0")"

echo "=============================================="
echo " InfraStack v$(cat VERSION) — ช่วง B: ติดตั้งระบบ   (user: $(id -un))"
echo "=============================================="

if [ "$(id -u)" -eq 0 ]; then
  echo "ERROR: รันด้วย user deploy ไม่ใช่ root — พิมพ์: su - deploy แล้ว cd $(pwd) && ./install.sh" >&2
  exit 1
fi

INTERACTIVE=0
[ -t 0 ] && INTERACTIVE=1

COMPOSE=(docker compose --env-file .env)
# ข้อความยาวของ docker pull / compose ลงไฟล์ log — จอแสดงแค่ทีละขั้น; ล้มเมื่อไหร่โชว์ท้าย log ให้เลย
LOG="$(pwd)/install.log"
run() {
  if ! "$@" >>"$LOG" 2>&1; then
    echo "❌ ล้มที่: $*" >&2
    tail -20 "$LOG" | sed 's/^/   /' >&2
    echo "   log เต็ม: $LOG — แก้แล้วรัน ./install.sh ซ้ำได้ (ขั้นที่เสร็จแล้วจะถูกข้าม)" >&2
    exit 1
  fi
}

# ── 1. Docker ────────────────────────────────────────
if ! command -v docker >/dev/null 2>&1; then
  echo "[1/7] ติดตั้ง Docker… (อาจถามรหัส sudo ของ $(id -un))"
  curl -fsSL https://get.docker.com | sudo sh
  sudo systemctl enable --now docker
else
  echo "[1/7] Docker: $(docker --version)"
fi

# ใช้ docker ได้โดยไม่ต้อง sudo — ไม่ต้อง logout/login:
# ยังไม่อยู่ใน group → เพิ่ม; อยู่ใน group แต่ session นี้ยังไม่มีสิทธิ์ → รันตัวเองใหม่ผ่าน `sg docker`
# (prepare.sh เพิ่ม group ไว้ก่อน `su - deploy` แล้ว ปกติจะไม่เข้าเงื่อนไขนี้)
if ! id -nG "$(id -un)" | grep -qw docker; then
  sudo usermod -aG docker "$(id -un)"
fi
if ! id -nG | grep -qw docker; then
  exec sg docker -c "$(printf '%q ' "$0" "$@")"
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "ERROR: docker compose plugin missing. Install docker-compose-plugin first." >&2
  exit 1
fi

# docker-rollout plugin (zero-downtime deploy)
# ห้ามเช็คด้วย `docker rollout --help` — Docker 29 พิมพ์ help รวมแล้ว exit 0
# ทั้งที่ไม่มี plugin (เจอจริงตอน deploy ครั้งแรก) → เช็คไฟล์ตรง ๆ
ROLLOUT_PLUGIN="$HOME/.docker/cli-plugins/docker-rollout"
if [ ! -x "$ROLLOUT_PLUGIN" ]; then
  mkdir -p "$HOME/.docker/cli-plugins"
  curl -fsSL https://raw.githubusercontent.com/wowu/docker-rollout/main/docker-rollout -o "$ROLLOUT_PLUGIN"
  chmod +x "$ROLLOUT_PLUGIN"
fi

docker network inspect proxy >/dev/null 2>&1 || docker network create proxy >/dev/null
docker network inspect backend >/dev/null 2>&1 || docker network create backend >/dev/null
docker network inspect monitoring >/dev/null 2>&1 || docker network create monitoring >/dev/null

# openssl ใช้สุ่มรหัสผ่าน + สร้าง basicauth hash (Ubuntu มีมาให้แล้ว)
if ! command -v openssl >/dev/null 2>&1; then
  echo "ERROR: ไม่มี openssl — ติดตั้งก่อน: sudo apt-get install -y openssl แล้วรัน ./install.sh ใหม่" >&2
  exit 1
fi

env_val() { grep -E "^$1=" .env | head -1 | cut -d= -f2- | tr -d ' \r' || true; }
# ค่าที่ผ่าน validate แล้ว (โดเมน/อีเมล) ไม่มี | — แทนด้วย sed ได้; ไม่มี key → ต่อท้าย
set_env() {
  if grep -qE "^$1=" .env; then sed -i "s|^$1=.*|$1=$2|" .env; else printf '%s=%s\n' "$1" "$2" >> .env; fi
}
ask() {  # ask <ตัวแปร> <คำถาม> [ค่าเริ่มต้น]
  local reply
  read -r -p "$2${3:+ [$3]}: " reply || reply=""
  printf -v "$1" '%s' "${reply:-${3:-}}"
}
DOMAIN_RE='^([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}$'
EMAIL_RE='^[^@ ]+@[^@ ]+\.[^@ ]+$'

# ── 2. ตั้งค่า (.env) — ถามแค่ครั้งแรก ─────────────────
if [ ! -f .env ]; then
  cp .env.example .env
  chmod 600 .env
fi
grep -qE '^INFRA_N8N_DOMAIN=' .env || printf '\nINFRA_N8N_DOMAIN=\n' >> .env

DOMAIN="$(env_val BASE_DOMAIN)"
EMAIL="$(env_val ACME_EMAIL)"
N8N_DOMAIN="$(env_val INFRA_N8N_DOMAIN)"
need_domain=0; need_email=0
[ -n "$DOMAIN" ] && [ "$DOMAIN" != "example.com" ] || need_domain=1
case "$EMAIL" in ""|*@example.com) need_email=1 ;; esac

if [ $((need_domain + need_email)) -gt 0 ]; then
  if [ -n "${INFRA_DOMAIN:-}" ] || [ -n "${INFRA_EMAIL:-}" ]; then
    # โหมดอัตโนมัติ — ค่าจาก environment
    [ "$need_domain" = 0 ] || DOMAIN="${INFRA_DOMAIN:-}"
    [ "$need_email" = 0 ] || EMAIL="${INFRA_EMAIL:-}"
    N8N_DOMAIN="${INFRA_N8N_DOMAIN:-$N8N_DOMAIN}"
  elif [ "$INTERACTIVE" = 1 ]; then
    echo ""
    if [ "$need_domain" = 1 ]; then
      while :; do
        ask DOMAIN "1) โดเมนของคุณ (เช่น example.com)"
        DOMAIN="$(printf '%s' "$DOMAIN" | tr 'A-Z' 'a-z' | tr -d ' ')"
        [[ "$DOMAIN" =~ $DOMAIN_RE ]] && [ "$DOMAIN" != "example.com" ] && break
        echo "   ❌ ไม่ใช่โดเมน — พิมพ์แค่ชื่อ เช่น mysite.com (ไม่ต้องมี https:// หรือ www.)"
      done
      echo "   หน้าแอดมินจะเป็น portainer.$DOMAIN, grafana.$DOMAIN …"
    fi
    if [ "$need_email" = 1 ]; then
      while :; do
        ask EMAIL "2) อีเมล (Let's Encrypt ใช้แจ้งเตือนเรื่อง HTTPS cert)"
        [[ "$EMAIL" =~ $EMAIL_RE ]] && [[ "$EMAIL" != *@example.com ]] && break
        echo "   ❌ อีเมลไม่ถูกต้อง"
      done
    fi
    if [ -z "$N8N_DOMAIN" ] && [ ! -d projects/n8n ]; then
      ask want_n8n "3) ติดตั้ง n8n ด้วยไหม? [Y/n]"
      case "${want_n8n:-y}" in
        [Yy]*)
          while :; do
            ask N8N_DOMAIN "   ชื่อเว็บ n8n" "n8n.$DOMAIN"
            [[ "$N8N_DOMAIN" =~ $DOMAIN_RE ]] && break
            echo "   ❌ ไม่ใช่ชื่อเว็บ — เช่น n8n.$DOMAIN"
          done ;;
      esac
    fi
    echo ""
    echo "สรุป:"
    echo "  โดเมน     $DOMAIN"
    echo "  อีเมล     $EMAIL"
    echo "  ติดตั้ง   core · database · monitoring${N8N_DOMAIN:+ · n8n ($N8N_DOMAIN)}"
    ask go "เริ่ม? [Y/n]"
    case "${go:-y}" in [Yy]*) ;; *) echo "ยกเลิก — ยังไม่ได้บันทึกอะไร"; exit 0 ;; esac
  else
    echo "ERROR: ยังไม่ได้ตั้งโดเมน/อีเมล — รันใน terminal เพื่อตอบคำถาม หรือ:" >&2
    echo "  INFRA_DOMAIN=example.com INFRA_EMAIL=you@example.com ./install.sh" >&2
    exit 1
  fi
  [[ "$DOMAIN" =~ $DOMAIN_RE ]] && [ "$DOMAIN" != "example.com" ] \
    || { echo "ERROR: โดเมนไม่ถูกต้อง: '$DOMAIN'" >&2; exit 1; }
  [[ "$EMAIL" =~ $EMAIL_RE ]] && [[ "$EMAIL" != *@example.com ]] \
    || { echo "ERROR: อีเมลไม่ถูกต้อง: '$EMAIL'" >&2; exit 1; }
  set_env BASE_DOMAIN "$DOMAIN"
  set_env ACME_EMAIL "$EMAIL"
  set_env INFRA_N8N_DOMAIN "$N8N_DOMAIN"
fi
# n8n ที่ติดตั้งไว้แล้ว (รันซ้ำ / ติดตั้งมือก่อนหน้า) → รวมในการเช็ค DNS + สรุป
if [ -z "$N8N_DOMAIN" ] && [ -f projects/n8n/.env ]; then
  N8N_DOMAIN="$(grep -E '^APP_DOMAIN=' projects/n8n/.env | cut -d= -f2- | tr -d ' \r')"
fi

# ── 3. รหัสผ่าน ───────────────────────────────────────
echo "[2/7] รหัสผ่านทุกระบบ…"
# volume ที่ "จำรหัสผ่านไว้แล้ว" ของแต่ละ key — postgres/grafana/pgadmin/rabbitmq/portainer ตั้งรหัส
# ตอน init ครั้งแรกเท่านั้น redis/minio มี project ที่ copy รหัสไปแล้ว → ถ้า volume มีอยู่
# ห้ามสุ่มใหม่ ไม่งั้นรหัสใน .env จะไม่ตรงของจริง (auth failed)
password_volume() {
  case "$1" in
    POSTGRES_PASSWORD)        echo postgres_data ;;
    REDIS_PASSWORD)           echo redis_data ;;
    GRAFANA_ADMIN_PASSWORD)   echo grafana_data ;;
    PGADMIN_PASSWORD)         echo pgadmin_data ;;
    RABBITMQ_PASSWORD)        echo rabbitmq_data ;;
    MINIO_ROOT_PASSWORD)      echo minio_data ;;
    PORTAINER_ADMIN_PASSWORD) echo portainer_data ;;
    *)                        echo "" ;;
  esac
}

# สุ่มรหัสให้ทุก *_PASSWORD ที่ยังเป็น CHANGE_ME — มือใหม่ไม่ต้องตั้งเองทีละตัว และไม่มีทาง
# เผลอ start database ด้วยรหัส CHANGE_ME (postgres จะจำรหัสนั้นถาวร)
# hex = ไม่มีอักขระพิเศษ → ใส่ใน URL/DSN (DATABASE_URL, REDIS_URL) ได้โดยไม่ต้อง encode
fill_passwords() {
  local key vol generated="" skipped=""
  # .env เก่าก่อนมี key เหล่านี้ → เติมให้
  local kv
  for kv in DASHBOARD_USER=admin DASHBOARD_PASSWORD=CHANGE_ME BACKUP_ENCRYPTION_PASSWORD=CHANGE_ME \
            PORTAINER_ADMIN_PASSWORD=CHANGE_ME; do
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
  [ -z "$generated" ] || echo "      สุ่มให้แล้ว:$generated"
  # PORTAINER_ADMIN_PASSWORD ข้ามได้ปกติ (admin สร้างไว้แล้ว) — ไม่ต้องเตือน
  skipped="${skipped/ PORTAINER_ADMIN_PASSWORD/}"
  [ -z "$skipped" ] || echo "⚠️  ไม่ได้สุ่ม:$skipped — service นี้มีข้อมูลอยู่แล้วและจำรหัสเดิมไว้ ตั้งใน .env ให้ตรงของจริงเอง"
}
fill_passwords

# Dashboard basicauth — หน้าแอดมินที่ไม่มี login ของตัวเอง (Traefik dashboard, Netdata, Dozzle,
# Redis Insight) ใช้ middleware กลาง dashboard-auth@file — สร้างใหม่จาก .env ทุกครั้งที่รัน install.sh
# ไฟล์อยู่นอก Git (.gitignore): ไม่ต้องแก้ compose เอง ไม่ต้อง escape $ และ git pull ไม่ชน
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
touch services/traefik/acme.json
chmod 600 services/traefik/acme.json

# ── 4. เปิดทุกอย่างก่อน — ยกเว้น Traefik (ยังไม่ขอ cert จนกว่า DNS พร้อม) ──────
echo "[3/7] เปิด Portainer…"
run "${COMPOSE[@]}" -f docker/docker-compose.core.yml up -d portainer

echo "[4/7] เปิด database (PostgreSQL, Redis)…"
run "${COMPOSE[@]}" -f docker/docker-compose.database.yml up -d
# create-project.sh สร้าง database ของ n8n ด้วย psql — ต้องรอ postgres พร้อมก่อน
for _ in $(seq 1 60); do
  [ "$(docker inspect -f '{{.State.Health.Status}}' postgres 2>/dev/null)" = "healthy" ] && break
  sleep 2
done

echo "[5/7] เปิด monitoring… (ดาวน์โหลดราว 3 GB ครั้งแรก 2–5 นาที)"
run "${COMPOSE[@]}" -f docker/docker-compose.monitoring.yml up -d

# Portainer: สร้าง admin ผ่าน API ทันที — ไม่ต้องแข่งกับเวลา 5 นาทีหลัง start
# (ยิงตรงเข้า container ทาง network ภายใน ไม่ต้องรอ DNS/HTTPS)
PORTAINER_PASS="$(env_val PORTAINER_ADMIN_PASSWORD)"
PORTAINER_STATE=manual
portainer_ip="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' portainer | awk '{print $1}')"
if [ -n "$portainer_ip" ] && [ -n "$PORTAINER_PASS" ] && [ "$PORTAINER_PASS" != "CHANGE_ME" ]; then
  for _ in $(seq 1 30); do
    curl -fsS -m 3 "http://$portainer_ip:9000/api/system/status" >/dev/null 2>&1 && break
    sleep 2
  done
  token="$(docker logs portainer 2>&1 | grep -o 'setup_token=[A-Za-z0-9]*' | tail -1 | cut -d= -f2 || true)"
  body="$(printf '{"Username":"admin","Password":"%s"}' "$PORTAINER_PASS")"
  code="$(curl -sS -m 10 -o /dev/null -w '%{http_code}' -X POST "http://$portainer_ip:9000/api/users/admin/init" \
            -H 'Content-Type: application/json' ${token:+-H "X-Setup-Token: $token"} -d "$body" 2>/dev/null || true)"
  if [ "$code" = "200" ]; then
    PORTAINER_STATE=created
  else
    # สร้างไว้แล้ว (รันซ้ำ) → ลอง login ด้วยรหัสใน .env ว่ายังใช้ได้ไหม
    code="$(curl -sS -m 10 -o /dev/null -w '%{http_code}' -X POST "http://$portainer_ip:9000/api/auth" \
              -H 'Content-Type: application/json' -d "$body" 2>/dev/null || true)"
    [ "$code" = "200" ] && PORTAINER_STATE=created
  fi
fi

if [ -n "$N8N_DOMAIN" ]; then
  echo "[6/7] เปิด n8n ($N8N_DOMAIN)…"
  if [ ! -f projects/n8n/docker-compose.yml ]; then
    run ./scripts/create-project.sh n8n n8n
    sed -i "s|^APP_DOMAIN=.*|APP_DOMAIN=$N8N_DOMAIN|" projects/n8n/.env
  fi
  run ./scripts/deploy.sh n8n
else
  echo "[6/7] n8n: ไม่ได้เลือกติดตั้ง (ทีหลัง: ./scripts/create-project.sh n8n n8n — docs/17)"
fi

# ── 5. DNS → Traefik + HTTPS ─────────────────────────
echo "[7/7] DNS + HTTPS"
DNS_ARGS=(core monitoring)
[ -z "$N8N_DOMAIN" ] || DNS_ARGS+=("$N8N_DOMAIN")
start_proxy() { run "${COMPOSE[@]}" -f docker/docker-compose.core.yml up -d; }

HTTPS_STATE=pending
if [ "${SKIP_DNS_CHECK:-0}" = "1" ]; then
  # restore-server.sh (ย้ายเครื่อง): cert มาจาก acme.json เดิม DNS ยังชี้เครื่องเก่า — ไม่ต้องรอ
  echo "  ⚠️  SKIP_DNS_CHECK=1 — เปิด Traefik โดยไม่รอ DNS"
  start_proxy
  HTTPS_STATE=ok
elif docker inspect -f '{{.State.Running}}' traefik 2>/dev/null | grep -q true \
   && ./scripts/check-dns.sh "${DNS_ARGS[@]}" >/dev/null 2>&1; then
  start_proxy   # รันซ้ำ: DNS ครบอยู่แล้ว
  HTTPS_STATE=ok
else
  echo ""
  echo "══════════════════════════════════════════════"
  echo "  เหลือขั้นเดียว: สร้าง DNS record ใน Cloudflare"
  echo "══════════════════════════════════════════════"
  # Ctrl+C = ออกจากหน้ารอได้ — ระบบรอ DNS ต่อเองเบื้องหลัง แล้วเปิด HTTPS ให้เมื่อพร้อม
  interrupted=0
  trap 'interrupted=1' INT
  ./scripts/check-dns.sh --wait "${DNS_ARGS[@]}" || interrupted=1
  trap - INT
  if [ "$interrupted" = 0 ]; then
    start_proxy
    HTTPS_STATE=ok
  else
    echo ""
    setsid nohup bash -c "./scripts/check-dns.sh --wait $(printf '%q ' "${DNS_ARGS[@]}") && \
      $(printf '%q ' "${COMPOSE[@]}") -f docker/docker-compose.core.yml up -d" \
      >/tmp/infra-dns-wait.log 2>&1 </dev/null &
    echo "⏳ ออกจากหน้ารอแล้ว — ระบบเช็ค DNS ต่อเองเบื้องหลัง และเปิด HTTPS ให้เมื่อ record ครบ"
    echo "   ดูสถานะ: infra status"
  fi
fi

# รอ Let's Encrypt ออก cert (ยิงเข้า Traefik ในเครื่อง + ตรวจ cert จริง)
if [ "$HTTPS_STATE" = ok ]; then
  mapfile -t CERT_HOSTS < <(./scripts/check-dns.sh --list "${DNS_ARGS[@]}")
  printf '  ขอ HTTPS cert …'
  for _ in $(seq 1 36); do
    pending=0
    for h in "${CERT_HOSTS[@]}"; do
      curl -s -o /dev/null -m 5 --resolve "$h:443:127.0.0.1" "https://$h/" || pending=$((pending + 1))
    done
    [ "$pending" = 0 ] && break
    printf '.'
    sleep 5
  done
  if [ "$pending" = 0 ]; then
    echo " ✅ ครบ ${#CERT_HOSTS[@]} ชื่อ"
  else
    HTTPS_STATE=slow
    echo " ⏳ ยังไม่ครบ $pending ชื่อ — ปกติได้ภายในไม่กี่นาที ดูได้ด้วย: infra status"
  fi
fi

# ── 6. สรุป ───────────────────────────────────────────
IP="$(curl -4 -fsS -m 5 https://1.1.1.1/cdn-cgi/trace 2>/dev/null | sed -n 's/^ip=//p' || true)"
IP="${IP:-$(hostname -I | awk '{print $1}')}"
DOMAIN="$(env_val BASE_DOMAIN)"
echo ""
echo "══════════════════════════════════════════════"
echo "  ✅ ติดตั้งเสร็จ"
echo "══════════════════════════════════════════════"
echo "⚠️  ทำตอนนี้เลย (ใครเปิดก่อนได้เป็นเจ้าของ):"
n=1
if [ -n "$N8N_DOMAIN" ]; then
  echo "  $n. https://$N8N_DOMAIN → สร้างบัญชี owner"; n=$((n + 1))
fi
echo "  $n. https://uptime.$DOMAIN → สร้างบัญชี admin"; n=$((n + 1))
echo "  $n. https://servers.$DOMAIN → สร้างบัญชี admin"; n=$((n + 1))
if [ "$PORTAINER_STATE" != created ]; then
  echo "  $n. https://portainer.$DOMAIN → สร้าง admin ภายใน 5 นาที (หมดเวลา: docker restart portainer)"
fi
echo ""
echo "login ได้เลย:"
[ "$PORTAINER_STATE" != created ] || \
  echo "  Portainer  https://portainer.$DOMAIN   admin / $PORTAINER_PASS"
echo "  Grafana    https://grafana.$DOMAIN   $(env_val GRAFANA_ADMIN_USER) / $(env_val GRAFANA_ADMIN_PASSWORD)"
echo "  Netdata · Logs · Traefik  (netdata. / logs. / traefik.$DOMAIN)   $DASH_USER / $DASH_PASS"
echo ""
echo "🔑 จดเก็บนอกเครื่อง (password manager) — หายแล้วกู้ข้อมูลไม่ได้:"
echo "  BACKUP_ENCRYPTION_PASSWORD   $(env_val BACKUP_ENCRYPTION_PASSWORD)"
[ ! -f projects/n8n/.env ] || \
  echo "  N8N_ENCRYPTION_KEY           $(grep -E '^N8N_ENCRYPTION_KEY=' projects/n8n/.env | cut -d= -f2-)"
echo "  (ดูอีกครั้งได้ด้วย: infra secrets)"
if [ "$HTTPS_STATE" != ok ]; then
  echo ""
  echo "⏳ HTTPS ยังไม่พร้อม — ลิงก์ด้านบนจะเปิดได้เมื่อ DNS ครบและได้ cert (ดู: infra status)"
fi
echo ""
echo "ครั้งหน้าเข้าเครื่อง:  ssh $(id -un)@$IP"
echo "ทำต่อ (ไม่บังคับ):    ตั้ง backup ขึ้น Cloudflare R2 — docs/13-backup.md"
echo "เพิ่มเว็บของคุณ:      ./scripts/create-project.sh <ชื่อ> <laravel|nextjs|n8n|ai-worker> — docs/26"
