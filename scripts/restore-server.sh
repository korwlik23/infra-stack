#!/usr/bin/env bash
# กู้ทั้งเครื่องจาก backup ลง VPS ใหม่ (เครื่องพัง / ย้ายเครื่อง) — docs/13-backup.md
# ใช้: ./scripts/restore-server.sh <source>
#   source = rclone path ของเครื่องเดิม เช่น r2:backup/old-vps  (rclone config ก่อน — docs/12)
#          | โฟลเดอร์ที่มี postgres/ mysql/ volumes/ secrets/ เช่น backup/archives (copy มาเอง)
# ก่อนรันบนเครื่องใหม่: prepare.sh (ช่วง A — ได้ user deploy + Docker) แล้วตอบ n ที่
#   "เริ่มติดตั้ง InfraStack ต่อเลยไหม" → su - deploy → รัน script นี้ (.env มาจากเครื่องเดิม)
#
# ขั้นตอน: ดึง backup ล่าสุด → ยืนยัน → secrets → volumes → core (install.sh)
#          → database + PostgreSQL → stack อื่นที่มีข้อมูล → บอกขั้นต่อ (projects + ย้าย DNS)
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"

SRC="${1:?usage: restore-server.sh <r2:bucket/host | local-dir>}"
# ระหว่างย้ายเครื่อง DNS ยังชี้เครื่องเดิม (check-dns จะบอก "ชี้ไปเครื่องอื่น") — cert ทุกชื่อมาจาก
# acme.json ที่ restore แล้ว Traefik ไม่ต้องขอใหม่ จึงข้ามการเช็ค/รอ DNS ทั้ง install.sh และ stack อื่น
export SKIP_DNS_CHECK=1
WARN=""
warn() { echo "⚠️  $*"; WARN="$WARN"$'\n'"  - $*"; }

docker info >/dev/null 2>&1 || { echo "ERROR: ใช้ docker ไม่ได้ — รัน ./install.sh ก่อน (ติดตั้ง Docker)" >&2; exit 1; }
command -v gpg >/dev/null 2>&1 || { echo "ERROR: ไม่มี gpg — sudo apt-get install -y gnupg" >&2; exit 1; }

latest_file() {   # latest_file <glob> — ไฟล์ชื่อท้ายสุดตามลำดับชื่อ (stamp ใหม่สุด)
  local f last=""
  for f in $1; do [ -e "$f" ] && last="$f"; done
  printf '%s' "$last"
}

# ── 1. รวม backup ชุดล่าสุดไว้ในโฟลเดอร์เดียว ─────────
if [[ "$SRC" == *:* ]]; then
  command -v rclone >/dev/null 2>&1 || { echo "ERROR: ไม่มี rclone — ติดตั้ง + config ตาม docs/12-r2.md" >&2; exit 1; }
  WORK="$ROOT/backup/archives/restore-$(date +%Y%m%d_%H%M%S)"
  mkdir -p "$WORK/postgres" "$WORK/mysql" "$WORK/volumes" "$WORK/secrets"
  echo "[1/7] Downloading latest backup from $SRC…"
  fetch_latest() {   # fetch_latest <kind> <regex>
    local f
    f="$(rclone lsf "$SRC/$1/" --files-only 2>/dev/null | grep -E "$2" | sort | tail -1 || true)"
    [ -n "$f" ] && rclone copyto "$SRC/$1/$f" "$WORK/$1/$f"
    return 0
  }
  fetch_latest secrets '^secrets_[0-9_]+\.tar\.gz\.gpg$'
  fetch_latest postgres '^all_[0-9_]+\.sql\.gz$'
  fetch_latest mysql '^all_[0-9_]+\.sql\.gz$'
  declare -A VLATEST=()
  while IFS= read -r f; do
    v="$(printf '%s' "$f" | sed -E 's/_[0-9]{8}_[0-9]{6}\.tar\.gz$//')"
    [ "$v" != "$f" ] && VLATEST[$v]="$f"
  done < <(rclone lsf "$SRC/volumes/" --files-only 2>/dev/null | grep -E '\.tar\.gz$' | sort)
  for v in "${!VLATEST[@]}"; do rclone copyto "$SRC/volumes/${VLATEST[$v]}" "$WORK/volumes/${VLATEST[$v]}"; done
else
  [ -d "$SRC" ] || { echo "ERROR: ไม่มีโฟลเดอร์ $SRC" >&2; exit 1; }
  WORK="$(cd "$SRC" && pwd)"
  echo "[1/7] Using local backup in $WORK"
fi

SECRETS="$(latest_file "$WORK/secrets/secrets_*.tar.gz.gpg")"
PGDUMP="$(latest_file "$WORK/postgres/all_*.sql.gz")"
MYDUMP="$(latest_file "$WORK/mysql/all_*.sql.gz")"
[ -n "$SECRETS" ] || { echo "ERROR: ไม่พบ secrets backup ใน $WORK/secrets — ไม่มี .env/รหัสผ่าน กู้เครื่องไม่ได้" >&2; exit 1; }

echo ""
echo "จะกู้จาก:"
echo "  secrets : $(basename "$SECRETS")"
echo "  postgres: $( [ -n "$PGDUMP" ] && basename "$PGDUMP" || echo '(ไม่มี — ข้าม)')"
echo "  mysql   : $( [ -n "$MYDUMP" ] && basename "$MYDUMP" || echo '(ไม่มี — ข้าม)')"
echo "  volumes : $(ls "$WORK/volumes" 2>/dev/null | grep -c '\.tar\.gz$' || true) ไฟล์"
echo ""
echo "⚠️  ใช้กับเครื่องใหม่เท่านั้น — .env ของเครื่องนี้จะถูกแทนด้วยของเครื่องเดิม"
echo "   volume ที่มีข้อมูลอยู่แล้วจะถูกข้าม (ไม่เขียนทับ)"
read -rp "Type 'restore' to continue: " CONFIRM
[ "$CONFIRM" = "restore" ] || { echo "aborted"; exit 1; }

# ── 2. secrets: .env, cert, projects, deploy keys, cron ──
echo "[2/7] Restoring secrets…"
./backup/scripts/secrets-restore.sh --yes "$SECRETS"

# ── 3. volumes — ก่อน start stack เพื่อให้ container เห็นข้อมูลตั้งแต่ start แรก ──
echo "[3/7] Restoring volumes…"
./backup/scripts/volumes-restore.sh --yes "$WORK/volumes" || warn "volume บางตัว restore ไม่สำเร็จ — ดู error ด้านบน"

# ── 4. core: networks + basicauth + DNS check + Traefik/Portainer (cert จาก acme.json เดิม) ──
echo "[4/7] Starting core stack (./install.sh)…"
./install.sh </dev/null

# ── 5. database + PostgreSQL ──
echo "[5/7] Starting database stack…"
docker compose --env-file .env -f docker/docker-compose.database.yml up -d
for i in $(seq 1 60); do
  [ "$(docker inspect -f '{{.State.Health.Status}}' postgres 2>/dev/null || true)" = "healthy" ] && break
  sleep 2
done
if [ "$(docker inspect -f '{{.State.Health.Status}}' postgres 2>/dev/null || true)" != "healthy" ]; then
  warn "postgres ไม่ healthy ใน 2 นาที — ยังไม่ได้ restore database (docker logs postgres)"
elif [ -n "$PGDUMP" ]; then
  ./backup/scripts/postgres-restore.sh --yes "$PGDUMP" || warn "restore PostgreSQL มี error — ดูรายการด้านบน"
fi

# MySQL — เฉพาะเครื่องเดิมที่มี project ใช้ --mysql (มี dump)
if [ -n "$MYDUMP" ]; then
  echo "[5/7] Starting MySQL + restoring…"
  docker compose --env-file .env -f docker/docker-compose.mysql.yml up -d
  for _ in $(seq 1 60); do
    [ "$(docker inspect -f '{{.State.Health.Status}}' mysql 2>/dev/null || true)" = "healthy" ] && break
    sleep 2
  done
  ./backup/scripts/mysql-restore.sh --yes "$MYDUMP" || warn "restore MySQL ไม่สำเร็จ — ดู error ด้านบน"
fi

# ── 6. stack อื่น — เปิดเฉพาะตัวที่มี volume ถูก restore (= เครื่องเดิมเปิดไว้) ──
echo "[6/7] Starting stacks that had data…"
for STACK in monitoring tools messaging storage; do
  FILE="docker/docker-compose.$STACK.yml"
  USED=""
  for V in $(docker compose --env-file .env -f "$FILE" config --volumes 2>/dev/null); do
    docker volume inspect "$V" >/dev/null 2>&1 && USED=1
  done
  [ -n "$USED" ] || { echo "  - $STACK: ไม่มีข้อมูลจากเครื่องเดิม — ข้าม"; continue; }
  docker compose --env-file .env -f "$FILE" up -d || warn "start $STACK ไม่สำเร็จ"
done

# ── 7. ขั้นต่อที่ต้องทำเอง ──
echo "[7/7] Next steps"
DOMAIN="$(grep -E '^BASE_DOMAIN=' .env | head -1 | cut -d= -f2- | tr -d ' \r')"
NEW_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
echo ""
echo "Projects — deploy ทีละตัว:"
for P in projects/*/docker-compose.yml; do
  [ -e "$P" ] || continue
  NAME="$(basename "$(dirname "$P")")"
  if grep -qE '^ *build:' "$P" && [ ! -d "projects/$NAME/src/.git" ]; then
    echo "  $NAME: build บนเครื่อง → clone source ก่อน (deploy key ถูก restore แล้ว — docs/19)"
    echo "         git clone <repo> projects/$NAME/src && ./scripts/deploy.sh $NAME"
  else
    echo "  ./scripts/deploy.sh $NAME"
  fi
done
echo ""
echo "ย้าย DNS (ทำหลังทดสอบผ่าน — เครื่องเดิมยังไม่ต้องปิด):"
echo "  1. ทดสอบเครื่องใหม่โดยไม่ย้าย DNS (cert เดิมจาก acme.json ใช้ได้เลย):"
echo "     curl -I --resolve portainer.$DOMAIN:443:$NEW_IP https://portainer.$DOMAIN"
echo "  2. ผ่านแล้ว → แก้ A record ทุกตัวใน Cloudflare เป็น $NEW_IP"
echo "  3. ย้ายภายในไม่กี่วัน — Traefik ต่ออายุ cert ผ่าน HTTP challenge ได้เมื่อ DNS ชี้มาเครื่องนี้แล้ว"
echo "  4. ตั้ง rclone (docs/12) ให้เครื่องนี้ backup ขึ้น R2 ต่อ"
if [ -n "$WARN" ]; then
  echo ""
  echo "⚠️  ต้องตามแก้:$WARN"
  exit 1
fi
echo ""
echo "✅ restore เสร็จ"
