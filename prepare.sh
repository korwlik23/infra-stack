#!/usr/bin/env bash
# ============================================================
# InfraStack — ช่วง A: เตรียมเครื่องและ user (รันด้วย root ครั้งแรกบน VPS ใหม่)
#   curl -fsSL https://raw.githubusercontent.com/korwlik23/infra-stack/main/prepare.sh | bash
#   (user ที่ไม่ใช่ root แต่ sudo ได้ เช่น ubuntu บน AWS/Oracle: … | sudo bash)
# ดาวน์โหลด repo → scripts/harden.sh (user deploy + ล็อกเครื่อง) → ถามว่าจะสลับเป็น
# deploy แล้วรัน install.sh (ช่วง B) ต่อเลยไหม — ทั้งหมดใน session เดียว ไม่ต้อง logout/login
# รันซ้ำได้: ขั้นที่ทำแล้วจะถูกข้าม
# ============================================================
set -euo pipefail

REPO_URL="${INFRA_REPO_URL:-https://github.com/korwlik23/infra-stack.git}"
REPO_BRANCH="${INFRA_BRANCH:-main}"
INFRA_DIR="${INFRA_DIR:-/opt/infra-stack}"
DEPLOY_USER="${DEPLOY_USER:-deploy}"
export DEPLOY_USER

if [ "$(id -u)" -ne 0 ]; then
  echo "ต้องรันด้วย root — ใส่ sudo หน้า bash:  curl -fsSL …/prepare.sh | sudo bash" >&2
  exit 1
fi

# curl | bash → stdin คือตัวสคริปต์เอง คำถามต้องอ่านจากจอ (/dev/tty)
# ไม่มีจอ (รันอัตโนมัติ) = ไม่ถาม: deploy ไม่มีรหัส → root ยังเข้าด้วย key ได้ (harden.sh จัดการ)
TTY=""
if { : </dev/tty; } 2>/dev/null; then TTY=/dev/tty; fi

echo "=============================================="
echo "  InfraStack — ช่วง A: เตรียมเครื่องและ user"
echo "=============================================="

# ── ตรวจเครื่อง — หยุดตั้งแต่ต้นถ้าไม่ผ่าน ดีกว่าพังกลางทาง ──────────────
# shellcheck disable=SC1091
. /etc/os-release
if [ "${ID:-}" != "ubuntu" ]; then
  echo "❌ รองรับเฉพาะ Ubuntu (เครื่องนี้: ${PRETTY_NAME:-ไม่ทราบ})" >&2
  exit 1
fi
ram_gb="$(awk '/MemTotal/ {printf "%.1f", $2/1048576}' /proc/meminfo)"
disk_gb="$(df -BG --output=avail / | tail -1 | tr -dc '0-9')"
ip4="$(curl -4 -fsS -m 5 https://1.1.1.1/cdn-cgi/trace 2>/dev/null | sed -n 's/^ip=//p' || true)"
ip4="${ip4:-$(hostname -I | awk '{print $1}')}"
echo "ตรวจเครื่อง:"
echo "  ✅ $PRETTY_NAME   ✅ RAM $ram_gb GB   ✅ Disk ว่าง $disk_gb GB"
echo "  ✅ IP เครื่องนี้: $ip4"
# ต่ำกว่านี้ monitoring stack จะทำให้เครื่องช้า/ดิสก์เต็ม — เตือน ไม่บังคับ
awk -v r="$ram_gb" 'BEGIN { exit !(r < 3.5) }' && echo "  ⚠️  RAM น้อยกว่า 4 GB — แนะนำ 8 GB (monitoring stack ใช้ราว 2.5 GB)"
[ "${disk_gb:-0}" -ge 20 ] || echo "  ⚠️  Disk ว่างน้อยกว่า 20 GB — image ของทุก stack รวมราว 8 GB"
# port 80/443 ถูกใช้อยู่ (เช่น nginx/apache ที่ provider ติดมา) → Traefik start ไม่ได้
busy="$(ss -Htlnp '( sport = :80 or sport = :443 )' 2>/dev/null | grep -v docker-proxy || true)"
if [ -n "$busy" ]; then
  echo "  ⚠️  port 80/443 มีโปรแกรมอื่นใช้อยู่ — ต้องปิดก่อนติดตั้ง (Traefik ใช้สอง port นี้):"
  echo "$busy" | sed 's/^/      /'
fi
echo ""

# ── ดาวน์โหลด InfraStack ─────────────────────────────
if [ -d "$INFRA_DIR/.git" ]; then
  echo "[repo] มี $INFRA_DIR อยู่แล้ว — ใช้ของเดิม (อัปเดตทีหลังด้วย ./scripts/update.sh)"
else
  command -v git >/dev/null 2>&1 || { apt-get update -y -q && apt-get install -y -q git; }
  echo "[repo] ดาวน์โหลด InfraStack → $INFRA_DIR"
  git clone -q --branch "$REPO_BRANCH" "$REPO_URL" "$INFRA_DIR"
fi

# ── user deploy + ล็อกเครื่อง ────────────────────────
if [ -n "$TTY" ]; then
  "$INFRA_DIR/scripts/harden.sh" <"$TTY"
else
  "$INFRA_DIR/scripts/harden.sh" </dev/null
fi

echo ""
echo "=============================================="
echo "  ✅ ช่วง A เสร็จ"
echo "=============================================="
echo "ครั้งหน้าเข้าเครื่องด้วย:  ssh $DEPLOY_USER@$ip4"
echo ""

answer="n"
if [ -n "$TTY" ]; then
  read -r -p "เริ่มติดตั้ง InfraStack ต่อเลยไหม? [Y/n] " answer <"$TTY" || answer="n"
  answer="${answer:-y}"
fi
case "$answer" in
  [Yy]*)
    # su - = login ใหม่ของ deploy → group docker ที่เพิ่งเพิ่มมีผลทันที
    su - "$DEPLOY_USER" -c "cd '$INFRA_DIR' && ./install.sh" <"$TTY" || true
    echo ""
    echo "(หน้าต่างนี้ยังเป็น root — ใช้งานต่อเป็น deploy: su - $DEPLOY_USER · ติดตั้งซ้ำ/ทำต่อ: cd $INFRA_DIR && ./install.sh)"
    ;;
  *)
    echo "ทำต่อเมื่อพร้อม (ใน session นี้ได้เลย ไม่ต้อง logout):"
    echo "  su - $DEPLOY_USER"
    echo "  cd $INFRA_DIR && ./install.sh"
    ;;
esac
