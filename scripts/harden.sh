#!/usr/bin/env bash
# ============================================================
# ช่วง A: เตรียมเครื่อง + user deploy — run as root on a fresh Ubuntu VPS (รันซ้ำได้)
#   ปกติ prepare.sh เรียกให้ — รันเองได้:  sudo ./scripts/harden.sh
# ทำ user ให้เสร็จก่อน (รหัส sudo, SSH key, group docker) แล้วค่อย update,
# packages, SSH hardening, UFW, Fail2ban — ติดตั้งต่อด้วย `su - deploy` ได้ทันที
# ไม่ต้อง logout/login
# ============================================================
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "run as root: sudo $0" >&2; exit 1; }

DEPLOY_USER="${DEPLOY_USER:-deploy}"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
AUTH_KEYS="/home/$DEPLOY_USER/.ssh/authorized_keys"
# ถามได้เฉพาะเมื่อมีคนนั่งอยู่หน้าจอ (prepare.sh ส่ง /dev/tty มาให้ตอน curl | bash)
INTERACTIVE=0
[ -t 0 ] && INTERACTIVE=1

# ห้าม apt เด้งหน้าจอถาม — Ubuntu 22.04+ needrestart ("Which services should be restarted?")
# และ dpkg conffile prompt (เช่น sshd_config เวอร์ชันใหม่) โผล่แม้ใส่ -y มือใหม่จะติดที่จอม่วง
# confold = เก็บไฟล์ config เดิมไว้ (ขั้น SSH แก้ sshd เองอยู่แล้ว)
export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a
APT_OPTS=(-y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)

deploy_has_password() { [ "$(passwd -S "$DEPLOY_USER" 2>/dev/null | awk '{print $2}')" = "P" ]; }

# ── คำถามทั้งหมดอยู่ต้นสคริปต์ — ตอบเสร็จแล้วปล่อยทำงานจนจบได้ ──────────
echo "[user] สร้าง user '$DEPLOY_USER' + sudo…"
if ! id "$DEPLOY_USER" >/dev/null 2>&1; then
  adduser --disabled-password --gecos "" "$DEPLOY_USER" >/dev/null
fi
usermod -aG sudo "$DEPLOY_USER"

# deploy ถูกสร้างแบบไม่มีรหัส → sudo ไม่ได้ ถ้าปิด root login ไปด้วยจะไม่มี user ไหนได้สิทธิ์ root
# ผ่าน SSH เลย (เจอจริง 2026-10: ปิด terminal root ก่อน passwd deploy → ต้องแก้ผ่าน VNC console)
if ! deploy_has_password && [ "$INTERACTIVE" = 1 ]; then
  echo ""
  echo "  ตั้งรหัสผ่านของ user '$DEPLOY_USER' — ใช้ตอนสั่ง sudo (ไม่ได้ใช้ login)"
  echo "  จดไว้ในชื่อ \"sudo ของ $DEPLOY_USER\" · พิมพ์แล้วไม่เห็นตัวอักษร เป็นเรื่องปกติ"
  for _ in 1 2 3; do passwd "$DEPLOY_USER" && break; done
fi

# ใช้ key เดียวกับ root (ถ้ามี) — copy เฉพาะตอน deploy ยังไม่มี key ไม่ทับ key ที่ตั้งเองไว้แล้ว
mkdir -p "/home/$DEPLOY_USER/.ssh"
if [ ! -s "$AUTH_KEYS" ] && [ -s /root/.ssh/authorized_keys ]; then
  cp /root/.ssh/authorized_keys "$AUTH_KEYS"
fi
# login เข้า VPS ด้วยรหัสผ่าน root (ไม่มี key ที่ไหนเลย) → ขอ public key จากคอมผู้ติดตั้ง
# ไม่มี key = ห้ามปิด password login (ล็อกตัวเองออก) จึงถามก่อนถึงขั้น SSH
if [ ! -s "$AUTH_KEYS" ] && [ "$INTERACTIVE" = 1 ]; then
  echo ""
  echo "  SSH key สำหรับเข้าเครื่องครั้งหน้า — ยังไม่พบ key ของคุณบนเครื่องนี้"
  echo "  เปิดหน้าต่างใหม่บนคอมคุณแล้วพิมพ์:"
  echo "    Windows (PowerShell):  type \$env:USERPROFILE\\.ssh\\id_ed25519.pub"
  echo "    Mac / Linux:           cat ~/.ssh/id_ed25519.pub"
  echo "  (ขึ้นว่าไม่พบไฟล์? พิมพ์ ssh-keygen -t ed25519 กด Enter จนจบ แล้วพิมพ์คำสั่งข้างบนอีกครั้ง)"
  echo "  copy บรรทัดที่ขึ้นต้นด้วย ssh-ed25519 มาวาง (Enter เปล่า = ข้าม — เครื่องจะยัง login ด้วยรหัสผ่านได้)"
  for _ in 1 2 3; do
    read -r -p "  > " key_line || key_line=""
    [ -n "$key_line" ] || break
    tmp_key="$(mktemp)"
    printf '%s\n' "$key_line" > "$tmp_key"
    if ssh-keygen -l -f "$tmp_key" >/dev/null 2>&1; then
      cat "$tmp_key" >> "$AUTH_KEYS"
      rm -f "$tmp_key"
      echo "  ✅ key ถูกต้อง: $(ssh-keygen -l -f "$AUTH_KEYS" | tail -1)"
      break
    fi
    rm -f "$tmp_key"
    echo "  ❌ ไม่ใช่ public key — ต้องเป็นบรรทัดเดียวที่ขึ้นต้นด้วย ssh-ed25519 หรือ ssh-rsa ลองอีกครั้ง"
  done
fi
chown -R "$DEPLOY_USER:$DEPLOY_USER" "/home/$DEPLOY_USER/.ssh"
chmod 700 "/home/$DEPLOY_USER/.ssh"
chmod 600 "$AUTH_KEYS" 2>/dev/null || true

# group docker สร้างไว้ก่อนติด Docker — `su - deploy` เป็น login ใหม่ สิทธิ์จึงมีผลทันที
# (เดิม install.sh เพิ่ม group ระหว่าง login อยู่ → ต้อง logout/login แล้วรันซ้ำ)
groupadd -f docker
usermod -aG docker "$DEPLOY_USER"

# repo ที่ clone ด้วย root → โอนให้ deploy (ทำเฉพาะตอนยังเป็นของ root — รันซ้ำหลังติดตั้งแล้วไม่แตะ data)
if [ "$(stat -c %U "$REPO_DIR")" = "root" ]; then
  chown -R "$DEPLOY_USER:$DEPLOY_USER" "$REPO_DIR"
fi
# คำสั่งสั้นหลังติดตั้ง: infra status / infra secrets
ln -sf "$REPO_DIR/scripts/infra" /usr/local/bin/infra

# ── งานที่ไม่ต้องถามอะไร ───────────────────────────────
# ข้อความยาวของ apt / Docker installer ลงไฟล์ log — จอแสดงแค่ทีละขั้น; ล้มเมื่อไหร่โชว์ท้าย log ให้เลย
LOG=/var/log/infra-prepare.log
run() {
  if ! "$@" >>"$LOG" 2>&1; then
    echo "❌ ล้มที่: $*" >&2
    tail -20 "$LOG" | sed 's/^/   /' >&2
    echo "   log เต็ม: $LOG — แก้แล้วรันคำสั่งเดิมซ้ำได้ (ขั้นที่เสร็จแล้วจะถูกข้าม)" >&2
    exit 1
  fi
}
echo "      (รายละเอียดอยู่ใน $LOG)"

echo "[1/5] อัปเดตระบบ + timezone + packages… (2–5 นาที)"
run apt-get update -y -q
run apt-get "${APT_OPTS[@]}" -q upgrade
run timedatectl set-timezone Asia/Bangkok
# apache2-utils = htpasswd (ไว้สร้าง basicauth เองถ้าต้องการ — install.sh ใช้ openssl แทนแล้ว)
# gnupg = เข้ารหัส backup ของ secrets (backup/scripts/secrets-backup.sh)
run apt-get "${APT_OPTS[@]}" -q install curl wget git unzip zip htop vim nano vnstat fail2ban ufw apache2-utils gnupg

echo "[2/5] Docker…"
# ติดในช่วง A (root) — install.sh ของ deploy จะได้ไม่ต้องหยุดถามรหัส sudo กลางทาง
if ! command -v docker >/dev/null 2>&1; then
  run sh -c 'curl -fsSL https://get.docker.com | sh'
fi
run systemctl enable --now docker
echo "      $(docker --version)"

echo "[3/5] firewall (SSH, HTTP, HTTPS)…"
run ufw default deny incoming
run ufw default allow outgoing
run ufw allow OpenSSH
run ufw allow 80/tcp
run ufw allow 443/tcp
run ufw --force enable

echo "[4/5] Fail2ban…"
run systemctl enable --now fail2ban

echo "[5/5] ล็อก SSH (ปิด root login + login ด้วยรหัสผ่าน)…"
if [ ! -s "$AUTH_KEYS" ]; then
  echo "⚠️  $DEPLOY_USER ยังไม่มี SSH key — ข้ามการล็อก SSH (กันล็อกตัวเองออก)"
  echo "   เพิ่ม key ให้ root หรือ $DEPLOY_USER แล้วรัน sudo $0 อีกครั้ง"
else
  # ปิด root login เฉพาะเมื่อ deploy sudo ได้แล้ว — ไม่งั้นเหลือ root เข้าด้วย key ไว้ก่อน
  if deploy_has_password; then
    ROOT_LOGIN=no
  else
    ROOT_LOGIN=prohibit-password
  fi
  sed -i "s/^#\?PermitRootLogin.*/PermitRootLogin $ROOT_LOGIN/" /etc/ssh/sshd_config
  sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
  # Ubuntu cloud image มัก include sshd_config.d/50-cloud-init.conf ที่ตั้ง
  # PasswordAuthentication yes — sshd ใช้ค่าแรกที่เจอ จึงต้องมี drop-in ที่เรียงก่อน (00-)
  if [ -d /etc/ssh/sshd_config.d ]; then
    printf 'PermitRootLogin %s\nPasswordAuthentication no\n' "$ROOT_LOGIN" > /etc/ssh/sshd_config.d/00-infra-hardening.conf
  fi
  # ตรวจ config ก่อน restart — config พังแล้ว restart = ล็อกตัวเองออก
  /usr/sbin/sshd -t
  # restart ไม่ตัด session ที่เปิดอยู่ — มีผลกับการ login ครั้งหน้า
  systemctl restart ssh || systemctl restart sshd
  # ค่าที่ sshd ใช้จริง — ต้องเห็น "no" ทั้งสองบรรทัด (permitrootlogin เป็น without-password
  # ถ้า deploy ยังไม่มีรหัส sudo)
  /usr/sbin/sshd -T | grep -Ei '^(permitrootlogin|passwordauthentication) ' || true
fi

echo ""
echo "✅ ช่วง A เสร็จ — '$DEPLOY_USER' มี sudo, SSH key และสิทธิ์ Docker ครบ"
if [ -s "$AUTH_KEYS" ] && ! deploy_has_password; then
  echo "⚠️  '$DEPLOY_USER' ยังไม่มีรหัส sudo → ยังไม่ปิด root login (root เข้าได้ด้วย key เท่านั้น)"
  echo "   ตั้งรหัสแล้วรันซ้ำเพื่อปิด root:  passwd $DEPLOY_USER && $0"
elif [ -s "$AUTH_KEYS" ]; then
  echo "🔒 root login ถูกปิดแล้ว (หน้าต่างนี้ไม่หลุด) — ครั้งหน้าเข้าด้วย: ssh $DEPLOY_USER@<IP เครื่องนี้>"
fi
