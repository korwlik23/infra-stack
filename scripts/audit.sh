#!/usr/bin/env bash
# ตรวจความปลอดภัยของเครื่อง — อ่านอย่างเดียว ไม่แก้อะไร (checklist เต็ม + วิธีแก้: docs/30-security-checklist.md)
# ใช้: infra audit            (หรือ ./scripts/audit.sh)
#      infra audit --notify   ส่งสรุปเข้า Telegram เมื่อมี ❌/⚠️ (cron รายสัปดาห์ — infra cron)
#
# ผลแต่ละข้อ: ✅ ผ่าน · ⚠️ ควรแก้ · ❌ ต้องแก้ · ⏭️ ตรวจไม่ได้ (เช่น ต้อง sudo)
# exit: 0 = ไม่มี ❌ · 1 = มี ❌ อย่างน้อยหนึ่งข้อ
#
# ข้อที่ต้อง sudo (SSH / UFW / fail2ban log) — ใน terminal ขอรหัส sudo ครั้งเดียว (Enter ว่าง = ข้ามข้อพวกนั้น)
# ใน cron ใช้ sudo -n: ไม่มีสิทธิ์แบบไม่ถามรหัส = ข้าม (⏭️) ไม่ใช่ล้ม
# ไม่พิมพ์รหัสผ่าน / ค่าลับใด ๆ ออกจอหรือ log — บอกแค่ชื่อ key
set -uo pipefail
cd "$(dirname "$(readlink -f "$0")")/.."
ROOT="$PWD"
# shellcheck source=scripts/lib/notify.sh
. "$ROOT/scripts/lib/notify.sh"

NOTIFY=0
[ "${1:-}" = "--notify" ] && NOTIFY=1

env_val() { grep -E "^$1=" "$ROOT/.env" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '\r' | sed -E 's/^"(.*)"$/\1/' || true; }
fenv() { grep -E "^$2=" "$1" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '\r' | sed -E 's/^"(.*)"$/\1/; s/^'"'"'(.*)'"'"'$/\1/; s/[[:space:]]+#.*$//; s/[[:space:]]+$//' || true; }

N_PASS=0; N_WARN=0; N_FAIL=0; N_SKIP=0; ISSUES=""
pass() { echo "  ✅ $1"; N_PASS=$((N_PASS + 1)); }
warn() { echo "  ⚠️  $1"; [ -z "${2:-}" ] || echo "      แก้: $2"; N_WARN=$((N_WARN + 1)); ISSUES="$ISSUES"$'\n'"⚠️ $1"; }
fail() { echo "  ❌ $1"; [ -z "${2:-}" ] || echo "      แก้: $2"; N_FAIL=$((N_FAIL + 1)); ISSUES="$ISSUES"$'\n'"❌ $1"; }
skip() { echo "  ⏭️  $1"; N_SKIP=$((N_SKIP + 1)); }
section() { echo ""; echo "── $1"; }

# ── sudo: root อยู่แล้ว / sudo ไม่ถามรหัส / ถามครั้งเดียวใน terminal ──
SUDO=""
if [ "$(id -u)" = 0 ]; then
  SUDO=" "
elif sudo -n true 2>/dev/null; then
  SUDO="sudo -n"
elif [ -t 0 ] && [ "$NOTIFY" = 0 ]; then
  echo "ข้อ SSH / UFW ต้องใช้ sudo — ใส่รหัส sudo ของ $(id -un) (Enter ว่าง = ข้ามข้อพวกนั้น)"
  sudo -v 2>/dev/null && SUDO="sudo -n"
fi
asroot() { if [ "$SUDO" = " " ]; then "$@"; else $SUDO "$@"; fi; }
# user ที่เป็นเจ้าของ cron / repo — รันด้วย sudo ก็ยังดู crontab ของ deploy ไม่ใช่ของ root
OWNER="${SUDO_USER:-$(id -un)}"

echo "=== InfraStack security audit — $(hostname -s) $(date '+%F %T') ==="

# ══════════════════════════════════════════════════════
section "1. SSH"
if [ -n "$SUDO" ] && SSHD="$(asroot sshd -T 2>/dev/null)"; then
  case "$(grep -i '^permitrootlogin ' <<<"$SSHD" | awk '{print $2}')" in
    no) pass "root login ปิดแล้ว" ;;
    prohibit-password|without-password)
        warn "root ยัง login ด้วย SSH key ได้ (PermitRootLogin prohibit-password)" \
             "ตั้งรหัส sudo ของ deploy (passwd deploy) แล้วรัน sudo ./scripts/harden.sh ซ้ำ — docs/02" ;;
    *)  fail "root login ด้วยรหัสผ่านได้ (PermitRootLogin yes)" "sudo ./scripts/harden.sh — docs/02" ;;
  esac
  if grep -qi '^passwordauthentication no' <<<"$SSHD"; then
    pass "SSH ด้วยรหัสผ่านปิดแล้ว (key เท่านั้น)"
  else
    fail "SSH ยัง login ด้วยรหัสผ่านได้ — โดนเดารหัสได้" "sudo ./scripts/harden.sh (ตรวจก่อนว่า ssh ด้วย key เข้าได้)"
  fi
  if grep -qi '^kbdinteractiveauthentication yes\|^challengeresponseauthentication yes' <<<"$SSHD"; then
    warn "KbdInteractiveAuthentication เปิดอยู่ (อีกทางที่ถามรหัสผ่านได้)" \
         "ใส่ KbdInteractiveAuthentication no ใน /etc/ssh/sshd_config.d/00-infra-hardening.conf แล้ว sudo systemctl restart ssh"
  fi
else
  skip "ตรวจ SSH ไม่ได้ (ต้อง sudo) — รันใน terminal: infra audit"
fi

# ══════════════════════════════════════════════════════
section "2. Firewall + กัน brute force"
if [ -n "$SUDO" ] && UFW="$(asroot ufw status 2>/dev/null)"; then
  if grep -q '^Status: active' <<<"$UFW"; then
    pass "UFW เปิดอยู่"
    # port ที่ allow นอกจาก SSH / 80 / 443
    EXTRA="$(grep -E 'ALLOW' <<<"$UFW" | awk '{print $1}' | sed 's/(v6)//' | sort -u \
             | grep -vxE '22(/tcp)?|OpenSSH|80(/tcp)?|443(/tcp)?|' | tr '\n' ' ' || true)"
    if [ -n "$EXTRA" ]; then
      warn "UFW เปิด port เพิ่มจาก 22/80/443: $EXTRA" "ไม่ได้ใช้แล้วปิด: sudo ufw delete allow <port>"
    else
      pass "UFW เปิดแค่ SSH / 80 / 443"
    fi
  else
    fail "UFW ไม่ได้เปิด — ทุก port ที่มี process ฟังอยู่เปิดสู่ internet" "sudo ./scripts/harden.sh (หรือ sudo ufw --force enable หลัง allow OpenSSH)"
  fi
else
  skip "ตรวจ UFW ไม่ได้ (ต้อง sudo)"
fi
if [ "$(systemctl is-active fail2ban 2>/dev/null)" = active ]; then
  pass "fail2ban ทำงานอยู่"
else
  fail "fail2ban ไม่ทำงาน — ไม่มีอะไรกันเดารหัส SSH" "sudo systemctl enable --now fail2ban"
fi

# port ที่ฟังบนทุก interface (ไม่ใช่ 127.0.0.1) นอกจาก 22/80/443
if command -v ss >/dev/null 2>&1; then
  OPEN="$(ss -tlnH 2>/dev/null | awk '{print $4}' \
          | grep -vE '^(127\.|\[::1\]|::1)' | sed -E 's/.*:([0-9]+)$/\1/' | sort -un \
          | grep -vxE '22|80|443' | tr '\n' ' ' | sed 's/ $//' || true)"
  if [ -n "$OPEN" ]; then
    warn "มี process ฟัง port บนทุก interface: $OPEN (UFW กันอยู่ถ้าเปิด — แต่ไม่ควรพึ่งชั้นเดียว)" \
         "ดูว่าเป็นอะไร: sudo ss -tlnp | grep -E ':(${OPEN// /|})\\b'"
  else
    pass "ไม่มี port อื่นนอกจาก 22/80/443 ฟังจากภายนอก"
  fi
fi

# ══════════════════════════════════════════════════════
section "3. อัปเดตความปลอดภัย"
if dpkg -s unattended-upgrades >/dev/null 2>&1 \
   && grep -qs 'Unattended-Upgrade "1"' /etc/apt/apt.conf.d/20auto-upgrades; then
  pass "unattended-upgrades เปิดอยู่ (security patch ลงเอง)"
else
  warn "ไม่ได้ลง security patch อัตโนมัติ" \
       "sudo apt-get install -y unattended-upgrades && sudo dpkg-reconfigure -plow unattended-upgrades"
fi
if [ -f /var/run/reboot-required ]; then
  warn "ต้อง reboot เพื่อใช้ kernel / library ที่อัปเดตแล้ว ($(tr '\n' ' ' </var/run/reboot-required.pkgs 2>/dev/null | cut -c1-80))" \
       "sudo reboot ช่วงคนใช้น้อย — docs/02 หัวข้อ อัปเดต kernel"
else
  pass "ไม่มีอัปเดตที่รอ reboot"
fi
if command -v apt >/dev/null 2>&1; then
  SEC="$(apt list --upgradable 2>/dev/null | grep -c -- '-security' || true)"
  if [ "${SEC:-0}" -gt 0 ]; then
    warn "มี security update ค้าง $SEC package" "sudo apt-get update && sudo apt-get upgrade -y"
  else
    pass "ไม่มี security update ค้าง (ตาม apt cache ล่าสุด)"
  fi
fi

# ══════════════════════════════════════════════════════
section "4. ไฟล์ลับ (รหัสผ่าน / cert / key)"
perm_check() {   # perm_check <file> — กลุ่ม/คนอื่นต้องอ่านไม่ได้
  local f="$1" m
  [ -e "$f" ] || return 0
  m="$(stat -c %a "$f" 2>/dev/null || echo '?')"
  if [[ "$m" =~ ^[0-7]?[0-7]00$ ]]; then
    PERM_OK=$((PERM_OK + 1))
  else
    fail "${f#"$ROOT"/} สิทธิ์ $m — user อื่นในเครื่องอ่านได้" "chmod 600 ${f#"$ROOT"/}"
  fi
}
PERM_OK=0
perm_check "$ROOT/.env"
perm_check "$ROOT/services/traefik/acme.json"
perm_check "$ROOT/services/traefik/dynamic/auth.yml"
# alertmanager.yml อยู่ใน Git (checkout ได้ 644) — มีความลับเฉพาะเมื่อใส่ Telegram token จริงแล้ว
AM="$ROOT/services/alertmanager/alertmanager.yml"
if grep -qE "bot_token:[[:space:]]*['\"]?[0-9]{6,}:" "$AM" 2>/dev/null \
   && ! [[ "$(stat -c %a "$AM" 2>/dev/null)" =~ ^[0-7]?[0-7]00$ ]]; then
  warn "services/alertmanager/alertmanager.yml มี Telegram token แต่ user อื่นอ่านได้" "chmod 600 services/alertmanager/alertmanager.yml"
fi
for f in "$ROOT"/projects/*/.env "$HOME"/.ssh/deploy_*; do
  case "$f" in *.pub) continue ;; esac
  perm_check "$f"
done
[ "$PERM_OK" = 0 ] || pass "$PERM_OK ไฟล์ลับสิทธิ์ 600 (เจ้าของอ่านได้คนเดียว)"

if [ -f .env ]; then
  WEAK=""; UNSET=""
  while IFS= read -r key; do
    v="$(env_val "$key")"
    if [ -z "$v" ] || [ "$v" = CHANGE_ME ]; then UNSET="$UNSET $key"
    elif [ "${#v}" -lt 16 ]; then WEAK="$WEAK $key"; fi
  done < <(grep -oE '^[A-Z0-9_]*_PASSWORD=' .env | tr -d '=' | sort -u)
  [ -z "$UNSET" ] || fail "รหัสที่ยังไม่ได้ตั้ง (ว่าง / CHANGE_ME):$UNSET" "./install.sh สุ่มให้ (เฉพาะ service ที่ยังไม่มีข้อมูล) หรือใส่เองใน .env"
  [ -z "$WEAK" ]  || warn "รหัสสั้นกว่า 16 ตัว:$WEAK" "เปลี่ยนเป็นรหัสยาว (openssl rand -base64 24) — DASHBOARD_PASSWORD: แก้ .env แล้ว ./install.sh"
  [ -n "$UNSET$WEAK" ] || pass "รหัสผ่านใน .env ตั้งครบและยาว ≥ 16 ตัว"
else
  fail "ไม่มี .env" "./install.sh"
fi

if [ -d .git ]; then
  TRACKED="$(git ls-files | grep -E '(^|/)\.env$|acme\.json$|dynamic/auth\.yml$|(^|/)id_[a-z0-9]+$|deploy_[a-z0-9_]+$' || true)"
  if [ -n "$TRACKED" ]; then
    fail "ไฟล์ลับอยู่ใน Git: $(tr '\n' ' ' <<<"$TRACKED")" \
         "git rm --cached <ไฟล์> แล้ว commit — และเปลี่ยนรหัสทุกตัวในไฟล์นั้น (ถือว่าหลุดแล้ว)"
  else
    pass "ไม่มีไฟล์ลับถูก track ใน Git"
  fi
fi

# ══════════════════════════════════════════════════════
section "5. หน้าแอดมิน + HTTPS"
if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
  skip "ใช้ docker ไม่ได้ — ข้ามส่วน container"
else
  if [ -s services/traefik/dynamic/auth.yml ]; then
    pass "มี basicauth กลาง (dashboard-auth) แล้ว"
  else
    fail "ไม่มี services/traefik/dynamic/auth.yml — หน้าแอดมินที่ไม่มี login ของตัวเองเปิดโล่ง" "./install.sh"
  fi
  # หน้าที่ไม่มี login ของตัวเอง (หรือโดนเดารหัสบ่อย) — ต้องผ่าน basicauth
  for c in traefik netdata dozzle redisinsight phpmyadmin; do
    [ "$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null)" = true ] || continue
    if docker inspect -f '{{range $k, $v := .Config.Labels}}{{$k}}={{$v}}{{"\n"}}{{end}}' "$c" \
         | grep -E '^traefik\.http\.routers\.[^.]+\.middlewares=' | grep -q 'dashboard-auth'; then
      pass "$c อยู่หลัง basicauth"
    else
      fail "$c เปิดผ่าน Traefik โดยไม่มี basicauth" "ใส่ label middlewares=dashboard-auth@file กลับใน services/$c/docker-compose.yml แล้ว infra up"
    fi
  done

  # Docker publish port ข้าม UFW ได้ — นอกจาก traefik 80/443 ไม่ควรมีตัวไหน publish ออก 0.0.0.0
  PUB="$(docker ps --format '{{.Names}}|{{.Ports}}' | while IFS='|' read -r n p; do
           tr ',' '\n' <<<"$p" | grep -E '(0\.0\.0\.0|\[?::\]?):[0-9]+->' | sed -E 's/^ *//' \
             | grep -vE '^(0\.0\.0\.0|\[?::\]?):(80|443)->' | sed "s/^/$n /"
         done || true)"
  if [ -n "$PUB" ]; then
    fail "container publish port ออก internet (Docker ข้าม UFW): $(tr '\n' ';' <<<"$PUB")" \
         "ลบ ports: ใน compose แล้วให้ผ่าน Traefik / ใช้ 127.0.0.1:<port>:<port> ถ้าต้องต่อจากเครื่องนี้เท่านั้น"
  else
    pass "มีแค่ Traefik ที่ publish port (80/443)"
  fi

  # cert ทุกโดเมนที่ Traefik เสิร์ฟ — ถามผ่าน 127.0.0.1 ด้วย SNI (ไม่พึ่ง DNS)
  HOSTS="$(docker ps -q | xargs -r docker inspect -f '{{range $k, $v := .Config.Labels}}{{$v}}{{"\n"}}{{end}}' 2>/dev/null \
           | grep -oE 'Host\(`[^`]+`\)' | sed -E 's/Host\(`([^`]+)`\)/\1/' | sort -u || true)"
  CERT_BAD=""; CERT_N=0
  for h in $HOSTS; do
    end="$(timeout 8 openssl s_client -connect 127.0.0.1:443 -servername "$h" </dev/null 2>/dev/null \
           | openssl x509 -noout -enddate -issuer 2>/dev/null || true)"
    if [ -z "$end" ] || grep -q 'TRAEFIK DEFAULT CERT' <<<"$end"; then
      CERT_BAD="$CERT_BAD $h(ไม่มี cert จริง)"; continue
    fi
    days=$(( ( $(date -d "$(sed -n 's/^notAfter=//p' <<<"$end")" +%s) - $(date +%s) ) / 86400 ))
    if [ "$days" -lt 14 ]; then CERT_BAD="$CERT_BAD $h(เหลือ ${days} วัน)"; else CERT_N=$((CERT_N + 1)); fi
  done
  [ -z "$CERT_BAD" ] || warn "cert มีปัญหา:$CERT_BAD" "ตรวจ DNS (infra dns) แล้วดู docker logs traefik | grep -i acme"
  [ "$CERT_N" = 0 ] || pass "cert HTTPS ใช้ได้ $CERT_N โดเมน (เหลือ ≥ 14 วัน)"

  # ══════════════════════════════════════════════════════
  section "6. Container"
  # project ของผู้ใช้ไม่ควรเข้าถึง docker.sock / privileged (= root ของเครื่อง)
  RISKY=""; NONNP=""
  for cid in $(docker ps -q); do
    info="$(docker inspect -f '{{.Name}}|{{index .Config.Labels "com.docker.compose.project.working_dir"}}|{{.HostConfig.Privileged}}|{{range .Mounts}}{{.Source}} {{end}}|{{.HostConfig.SecurityOpt}}' "$cid")"
    IFS='|' read -r n wd priv mnts secopt <<<"$info"
    case "$wd" in */projects/*) ;; *) continue ;; esac
    [ "$priv" = true ] && RISKY="$RISKY ${n#/}(privileged)"
    [[ "$mnts" == *docker.sock* ]] && RISKY="$RISKY ${n#/}(docker.sock)"
    [[ "$secopt" == *no-new-privileges* ]] || NONNP="$NONNP ${n#/}"
  done
  if [ -n "$RISKY" ]; then
    fail "container ของ project มีสิทธิ์ระดับ root ของเครื่อง:$RISKY" "เอา privileged / docker.sock ออกจาก projects/<ชื่อ>/docker-compose.yml"
  else
    pass "container ของ project ไม่มี privileged / docker.sock"
  fi
  # project ที่สร้างก่อน v2.15 — template ยังไม่มี no-new-privileges
  if [ -n "$NONNP" ]; then
    warn "container ของ project ไม่ได้ตั้ง no-new-privileges:$NONNP" \
         "เพิ่มใต้ทุก service ใน projects/<ชื่อ>/docker-compose.yml: security_opt: [\"no-new-privileges:true\"] แล้ว infra restart <ชื่อ> — docs/31"
  elif [ -n "$(docker ps -q --filter label=com.docker.compose.project.working_dir)" ]; then
    pass "container ของ project ตั้ง no-new-privileges ครบ"
  fi
  # image เก่า = ช่องโหว่สะสม (base image ไม่ได้อัปเดต)
  OLD=""
  now=$(date +%s)
  for img in $(docker ps --format '{{.Image}}' | sort -u); do
    created="$(docker image inspect -f '{{.Created}}' "$img" 2>/dev/null | cut -c1-19)"
    [ -n "$created" ] || continue
    age=$(( (now - $(date -d "$created" +%s 2>/dev/null || echo "$now")) / 86400 ))
    [ "$age" -le 180 ] || OLD="$OLD $img(${age}d)"
  done
  if [ -n "$OLD" ]; then
    warn "image อายุเกิน 180 วัน:$OLD" "stack: infra update <stack> · project: infra refresh <ชื่อ> (build บน base image ล่าสุด — docs/31)"
  else
    pass "image ที่รันอยู่อายุไม่เกิน 180 วัน"
  fi
fi

# ══════════════════════════════════════════════════════
section "7. App (projects/*/.env)"
FOUND=0
PG_SUPER="$(env_val POSTGRES_USER)"; PG_SUPER="${PG_SUPER:-infra}"
R2_ROOT_SECRET="$(env_val R2_SECRET_ACCESS_KEY)"
for penvf in "$ROOT"/projects/*/.env; do
  [ -f "$penvf" ] || continue
  p="$(basename "$(dirname "$penvf")")"
  # ต่อ Postgres กลางด้วย superuser = แอปนี้โดนเจาะ → ทุก database + สั่งคำสั่งบนเครื่องได้ (COPY … PROGRAM)
  dbu="$(fenv "$penvf" DB_USERNAME)"; dbh="$(fenv "$penvf" DB_HOST)"; url="$(fenv "$penvf" DATABASE_URL)"
  if [ -z "$dbu" ] && [[ "$url" =~ ^[a-z]+://([^:@/]+)(:[^@]*)?@([^:/]+) ]]; then
    dbu="${BASH_REMATCH[1]}"; dbh="${BASH_REMATCH[3]}"
  fi
  if [ "$dbh" = postgres ] && [ -n "$dbu" ]; then
    FOUND=1
    if [ "$dbu" = "$PG_SUPER" ]; then
      fail "$p: ต่อ database ด้วย superuser ($PG_SUPER) — โดนเจาะแอปเดียว = ทุก database + คำสั่งบนเครื่อง" "infra db-user $p แล้ว infra restart $p — docs/31"
    else
      pass "$p: database user ของตัวเอง ($dbu)"
    fi
  fi
  # key R2 ตัวเดียวกับ backup — แอปโดนเจาะ = ลบ backup off-site ได้
  if [ -n "$R2_ROOT_SECRET" ] && [ "$R2_ROOT_SECRET" != CHANGE_ME ] \
     && grep -qxF -e "AWS_SECRET_ACCESS_KEY=$R2_ROOT_SECRET" -e "R2_SECRET_ACCESS_KEY=$R2_ROOT_SECRET" "$penvf"; then
    FOUND=1
    warn "$p: ใช้ R2 key ตัวเดียวกับ backup — แอปโดนเจาะ = ลบ backup ได้" "สร้าง R2 API token ใหม่จำกัดเฉพาะ bucket ของ $p แล้วใส่ใน infra env $p — docs/31"
  fi
  # Laravel
  if grep -qE '^APP_KEY=' "$penvf"; then
    FOUND=1
    dbg="$(fenv "$penvf" APP_DEBUG)"; envn="$(fenv "$penvf" APP_ENV)"
    case "${dbg,,}" in
      true|1) fail "$p: APP_DEBUG=true — หน้า error โชว์ .env / stack trace ให้คนนอกเห็น" "infra env $p → APP_DEBUG=false" ;;
      *) pass "$p: APP_DEBUG ปิด" ;;
    esac
    [ "$envn" = production ] || warn "$p: APP_ENV=${envn:-ว่าง} (ไม่ใช่ production)" "infra env $p → APP_ENV=production"
    [ -n "$(fenv "$penvf" APP_KEY)" ] || fail "$p: APP_KEY ว่าง — session/cookie เข้ารหัสไม่ได้" "infra artisan $p key:generate --show แล้วใส่ใน infra env $p"
  fi
  # Next.js / Node
  if grep -qE '^NODE_ENV=' "$penvf"; then
    FOUND=1
    [ "$(fenv "$penvf" NODE_ENV)" = production ] || warn "$p: NODE_ENV ไม่ใช่ production" "infra env $p → NODE_ENV=production"
  fi
  # ต่อ database ภายนอกผ่าน internet โดยไม่เข้ารหัส
  url="$(fenv "$penvf" DATABASE_URL)"
  if [[ "$url" =~ @([^:/]+) ]] && [[ ! "${BASH_REMATCH[1]}" =~ ^(postgres|mysql|redis|localhost|127\.0\.0\.1)$ ]] \
     && [[ "$url" == *sslmode=disable* || "$url" != *ssl* ]]; then
    FOUND=1
    warn "$p: DATABASE_URL ไป ${BASH_REMATCH[1]} โดยไม่บังคับ TLS" "เติม ?sslmode=require (Postgres) / ?ssl=true — docs/26 Database ภายนอก"
  fi
done
[ "$FOUND" = 1 ] || skip "ไม่มี project ที่ตรวจได้"

# ══════════════════════════════════════════════════════
section "8. Backup + งานอัตโนมัติ"
CRON="$(crontab -l -u "$OWNER" 2>/dev/null || crontab -l 2>/dev/null || true)"
if grep -q 'scripts/backup.sh' <<<"$CRON"; then pass "cron backup ตั้งไว้แล้ว"
else fail "ไม่มี cron backup — ไม่มีอะไร backup ให้ทุกคืน" "infra cron"; fi
LAST="$(ls -1t backup/archives/secrets/secrets_*.tar.gz.gpg 2>/dev/null | head -1 || true)"
if [ -z "$LAST" ]; then
  fail "ยังไม่เคยมี backup" "infra backup"
elif [ -n "$(find "$LAST" -mtime +1 2>/dev/null)" ]; then
  warn "backup ล่าสุดเก่ากว่า 2 วัน ($(basename "$LAST"))" "infra logs backup — ดูว่าทำไม cron ล้ม"
else
  pass "backup ล่าสุด: $(basename "$LAST")"
fi
B="$(env_val R2_BUCKET_BACKUP)"; R="$(env_val BACKUP_RCLONE_REMOTE)"
if command -v rclone >/dev/null 2>&1 && [ -n "$B" ] && [ "$B" != CHANGE_ME ] \
   && rclone listremotes 2>/dev/null | grep -qx "${R:-r2}:"; then
  pass "backup ส่งออกนอกเครื่อง (rclone ${R:-r2}:$B)"
else
  warn "backup อยู่แค่ในเครื่องนี้ — VPS พัง = backup หายด้วย" "ตั้ง rclone + R2_BUCKET_BACKUP — docs/12, docs/13"
fi
for job in refresh cve-scan; do
  if grep -q "scripts/$job.sh" <<<"$CRON"; then pass "cron $job ตั้งไว้แล้ว"
  else warn "ไม่มี cron $job — แพตช์ความปลอดภัย / CVE ใหม่ไม่มีใครเห็น" "infra cron — docs/31"; fi
done
if [ -n "$(env_val NOTIFY_TELEGRAM_BOT_TOKEN)" ] && [ -n "$(env_val NOTIFY_TELEGRAM_CHAT_ID)" ]; then
  pass "แจ้งเตือน Telegram ตั้งแล้ว"
else
  warn "ยังไม่ได้ตั้ง Telegram — deploy / backup ล้มจะไม่มีใครรู้" "ใส่ NOTIFY_TELEGRAM_BOT_TOKEN + NOTIFY_TELEGRAM_CHAT_ID ใน .env — docs/19"
fi

# ══════════════════════════════════════════════════════
echo ""
echo "=== สรุป: ✅ $N_PASS · ⚠️  $N_WARN · ❌ $N_FAIL · ⏭️  $N_SKIP ==="
echo "checklist ข้อที่ตรวจด้วย script ไม่ได้ (ต้องทำเอง): docs/30-security-checklist.md"
if [ "$NOTIFY" = 1 ] && [ $((N_WARN + N_FAIL)) -gt 0 ]; then
  notify "🛡️ security audit: ❌ $N_FAIL · ⚠️ $N_WARN — รายละเอียด: infra audit$(head -c 3000 <<<"$ISSUES")"
fi
[ "$N_FAIL" = 0 ]
