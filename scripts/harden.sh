#!/usr/bin/env bash
# ============================================================
# Server hardening — run ONCE as root on a fresh Ubuntu VPS
#   sudo ./scripts/harden.sh
# Day-1 checklist: update, timezone, base packages, deploy
# user, SSH hardening, UFW, Fail2ban
# ============================================================
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "run as root: sudo $0" >&2; exit 1; }

DEPLOY_USER="${DEPLOY_USER:-deploy}"

echo "[1/6] apt update & upgrade…"
apt-get update -y && apt-get upgrade -y

echo "[2/6] timezone Asia/Bangkok + base packages…"
timedatectl set-timezone Asia/Bangkok
apt-get install -y curl wget git unzip zip htop vim nano vnstat fail2ban ufw

echo "[3/6] creating user '$DEPLOY_USER' with sudo…"
if ! id "$DEPLOY_USER" >/dev/null 2>&1; then
  adduser --disabled-password --gecos "" "$DEPLOY_USER"
  usermod -aG sudo "$DEPLOY_USER"
  mkdir -p "/home/$DEPLOY_USER/.ssh"
  # ใช้ key เดียวกับ root ที่ provider ใส่มาให้ (ถ้ามี)
  [ -f /root/.ssh/authorized_keys ] && cp /root/.ssh/authorized_keys "/home/$DEPLOY_USER/.ssh/"
  chown -R "$DEPLOY_USER:$DEPLOY_USER" "/home/$DEPLOY_USER/.ssh"
  chmod 700 "/home/$DEPLOY_USER/.ssh"
  chmod 600 "/home/$DEPLOY_USER/.ssh/authorized_keys" 2>/dev/null || true
fi

echo "[4/6] SSH hardening (no root login, no password auth)…"
if [ ! -s "/home/$DEPLOY_USER/.ssh/authorized_keys" ]; then
  echo "⚠️  no SSH key found for $DEPLOY_USER — add one BEFORE disabling password auth!"
  echo "   skipping SSH hardening. Add key then re-run."
else
  sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
  sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
  systemctl restart ssh || systemctl restart sshd
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
