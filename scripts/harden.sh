#!/usr/bin/env bash
# ============================================================
# Server hardening — run as root on a fresh Ubuntu VPS (รันซ้ำได้)
#   sudo ./scripts/harden.sh
# Day-1 checklist: update, timezone, base packages, deploy
# user, SSH hardening, UFW, Fail2ban
# ============================================================
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "run as root: sudo $0" >&2; exit 1; }

DEPLOY_USER="${DEPLOY_USER:-deploy}"

# ห้าม apt เด้งหน้าจอถาม — Ubuntu 22.04+ needrestart ("Which services should be restarted?")
# และ dpkg conffile prompt (เช่น sshd_config เวอร์ชันใหม่) โผล่แม้ใส่ -y มือใหม่จะติดที่จอม่วง
# confold = เก็บไฟล์ config เดิมไว้ (ขั้น [4/6] แก้ sshd เองอยู่แล้ว)
export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a
APT_OPTS=(-y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)

echo "[1/6] apt update & upgrade…"
apt-get update -y && apt-get "${APT_OPTS[@]}" upgrade

echo "[2/6] timezone Asia/Bangkok + base packages…"
timedatectl set-timezone Asia/Bangkok
# apache2-utils = htpasswd (ไว้สร้าง basicauth เองถ้าต้องการ — install.sh ใช้ openssl แทนแล้ว)
apt-get "${APT_OPTS[@]}" install curl wget git unzip zip htop vim nano vnstat fail2ban ufw apache2-utils

echo "[3/6] creating user '$DEPLOY_USER' with sudo…"
if ! id "$DEPLOY_USER" >/dev/null 2>&1; then
  adduser --disabled-password --gecos "" "$DEPLOY_USER"
  usermod -aG sudo "$DEPLOY_USER"
fi
# ใช้ key เดียวกับ root (ถ้ามี) — ทำนอก if ด้านบน เพื่อให้รันซ้ำหลังเพิ่ม key ให้ root ทีหลังได้
# copy เฉพาะตอน deploy ยังไม่มี key — ไม่ทับ key ที่ตั้งเองไว้แล้ว
mkdir -p "/home/$DEPLOY_USER/.ssh"
if [ ! -s "/home/$DEPLOY_USER/.ssh/authorized_keys" ] && [ -s /root/.ssh/authorized_keys ]; then
  cp /root/.ssh/authorized_keys "/home/$DEPLOY_USER/.ssh/authorized_keys"
fi
chown -R "$DEPLOY_USER:$DEPLOY_USER" "/home/$DEPLOY_USER/.ssh"
chmod 700 "/home/$DEPLOY_USER/.ssh"
chmod 600 "/home/$DEPLOY_USER/.ssh/authorized_keys" 2>/dev/null || true

echo "[4/6] SSH hardening (no root login, no password auth)…"
if [ ! -s "/home/$DEPLOY_USER/.ssh/authorized_keys" ]; then
  echo "⚠️  no SSH key found for $DEPLOY_USER — add one BEFORE disabling password auth!"
  echo "   skipping SSH hardening. Add key then re-run."
else
  sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
  sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
  # Ubuntu cloud image มัก include sshd_config.d/50-cloud-init.conf ที่ตั้ง
  # PasswordAuthentication yes — sshd ใช้ค่าแรกที่เจอ จึงต้องมี drop-in ที่เรียงก่อน (00-)
  if [ -d /etc/ssh/sshd_config.d ]; then
    printf 'PermitRootLogin no\nPasswordAuthentication no\n' > /etc/ssh/sshd_config.d/00-infra-hardening.conf
  fi
  # ตรวจ config ก่อน restart — config พังแล้ว restart = ล็อกตัวเองออก
  /usr/sbin/sshd -t
  systemctl restart ssh || systemctl restart sshd
  # ค่าที่ sshd ใช้จริง — ต้องเห็น "no" ทั้งสองบรรทัด
  /usr/sbin/sshd -T | grep -Ei '^(permitrootlogin|passwordauthentication) ' || true
fi

echo "[5/6] UFW firewall (allow SSH, HTTP, HTTPS)…"
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

echo "[6/6] Fail2ban…"
systemctl enable --now fail2ban

echo ""
echo "✅ Hardening done. IMPORTANT:"
echo "  - เปิด terminal ใหม่ทดสอบ 'ssh $DEPLOY_USER@<ip>' ให้ผ่าน ก่อนปิด session นี้"
echo "  - จากนี้ deploy ทุกอย่างด้วย user '$DEPLOY_USER' ไม่ใช่ root"
