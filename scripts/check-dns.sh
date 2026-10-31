#!/usr/bin/env bash
# เช็คว่าทุก subdomain ของ stack มี DNS record แล้ว — รันก่อน start stack ที่มีหน้าเว็บ
# ไม่มี record → Traefik ขอ cert ล้มซ้ำจน Let's Encrypt แบนราว 1 ชั่วโมง (docs/04)
# ใช้: ./scripts/check-dns.sh <stack> [stack…]   เช่น  core  monitoring  tools
#      stack = docker/docker-compose.<stack>.yml
# รายชื่อ subdomain อ่านจาก Host(`…`) ใน compose ของแต่ละ service — ไม่มีรายการซ้ำให้ลืมแก้
# ข้ามได้ (เช่นใช้ wildcard record ที่ยังไม่ propagate): SKIP_DNS_CHECK=1
set -euo pipefail
cd "$(dirname "$0")/.."

[ $# -gt 0 ] || { echo "usage: $0 <core|monitoring|tools|messaging|storage> [stack…]" >&2; exit 1; }

if [ "${SKIP_DNS_CHECK:-0}" = "1" ]; then
  echo "⚠️  SKIP_DNS_CHECK=1 — ข้ามการเช็ค DNS (ถ้า record ยังไม่มี cert จะล้ม)"
  exit 0
fi

[ -f .env ] || { echo "ERROR: ไม่มี .env — รัน ./install.sh ก่อน" >&2; exit 1; }
DOMAIN="$(grep -E '^BASE_DOMAIN=' .env | head -1 | cut -d= -f2- | tr -d ' \r' || true)"
[ -n "$DOMAIN" ] || { echo "ERROR: BASE_DOMAIN ใน .env ว่าง" >&2; exit 1; }

# IP ของเครื่องนี้ — ใช้เช็คว่า record ชี้มาที่นี่จริง ไม่ใช่แค่ "มีชื่อ"
# (เจอจริง 2026-10: BASE_DOMAIN ซ้ำกับเครื่องเก่า → portainer.* resolve ได้แต่ชี้ไปเครื่องเก่า แล้วผ่าน)
# hostname -I อาจเป็น IP ภายใน (NAT) → ถาม public IP จาก Cloudflare trace ด้วย; หาไม่ได้ = ข้ามการเทียบ
SELF_IPS=" $(hostname -I 2>/dev/null || true) "
PUBLIC_IP="$(curl -4 -fsS -m 5 https://1.1.1.1/cdn-cgi/trace 2>/dev/null | sed -n 's/^ip=//p' || true)"
[ -z "$PUBLIC_IP" ] || SELF_IPS="$SELF_IPS$PUBLIC_IP "

ip2int() { local IFS=.; set -- $1; echo $(( ($1 << 24) + ($2 << 16) + ($3 << 8) + $4 )); }
# Proxied (เมฆส้ม) → DNS ตอบเป็น IP ของ Cloudflare เทียบกับเครื่องไม่ได้ — https://www.cloudflare.com/ips-v4
is_cloudflare_ip() {
  local ip n cidr net bits
  ip="$(ip2int "$1")"
  for cidr in 173.245.48.0/20 103.21.244.0/22 103.22.200.0/22 103.31.4.0/22 141.101.64.0/18 \
              108.162.192.0/18 190.93.240.0/20 188.114.96.0/20 197.234.240.0/22 198.41.128.0/17 \
              162.158.0.0/15 104.16.0.0/13 104.24.0.0/14 172.64.0.0/13 131.0.72.0/22; do
    net="$(ip2int "${cidr%/*}")"; bits="${cidr#*/}"
    n=$(( (0xFFFFFFFF << (32 - bits)) & 0xFFFFFFFF ))
    [ $(( ip & n )) -eq $(( net & n )) ] && return 0
  done
  return 1
}

missing=""
count=0
elsewhere=""
proxied=0
for stack in "$@"; do
  file="docker/docker-compose.$stack.yml"
  [ -f "$file" ] || { echo "ERROR: ไม่มี stack '$stack' ($file)" >&2; exit 1; }
  # include: - ../services/<name>/docker-compose.yml → services/<name>/docker-compose.yml
  for svc in $(sed -n 's|^ *- *\.\./\(services/[^ ]*\.yml\) *$|\1|p' "$file"); do
    # ข้ามบรรทัด comment (เช่น beszel-agent ที่ปิดไว้)
    for sub in $(grep -v '^ *#' "$svc" | grep -o 'Host(`[a-z0-9-]*\.\${BASE_DOMAIN}`)' \
                   | sed 's/^Host(`\([a-z0-9-]*\)\..*/\1/' || true); do
      host="$sub.$DOMAIN"
      ips="$(getent ahostsv4 "$host" 2>/dev/null | awk '{print $1}' | sort -u | tr '\n' ' ' || true)"
      ip="${ips%% *}"
      if [ -z "$ip" ]; then
        echo "  ❌ $host"
        missing="$missing $sub"
        count=$((count + 1))
      elif [ -z "$PUBLIC_IP" ] || [[ "$SELF_IPS" == *" $ip "* ]]; then
        echo "  ✅ $host"
      elif is_cloudflare_ip "$ip"; then
        echo "  ✅ $host (Proxied ผ่าน Cloudflare — ตรวจว่าชี้มาเครื่องนี้ไม่ได้)"
        proxied=$((proxied + 1))
      else
        echo "  ❌ $host → $ip (เครื่องอื่น)"
        elsewhere="$elsewhere $sub=$ip"
        count=$((count + 1))
      fi
    done
  done
done

SERVER_IP="${PUBLIC_IP:-$(hostname -I 2>/dev/null | awk '{print $1}')}"
if [ "$count" -gt 0 ]; then
  echo "" >&2
  echo "ERROR: DNS ยังไม่พร้อม $count ตัว — ยังไม่ start เพื่อกัน Let's Encrypt แบน" >&2
  if [ -n "$missing" ]; then
    echo "  ไปที่ Cloudflare → DNS → Add record ทีละตัว (ช่อง Name ใส่ชื่อเต็มได้ Cloudflare ตัดโดเมนหลักให้เอง):" >&2
    for sub in $missing; do
      echo "    Type: A   Name: $sub.$DOMAIN   IPv4: $SERVER_IP" >&2
    done
    echo "  BASE_DOMAIN เป็นชื่อย่อย (เช่น sg.example.com — เครื่องเสริม)? ตั้ง Proxy เป็น DNS only (เมฆเทา)" >&2
    echo "  หรือสร้าง record เดียว Name: *.$DOMAIN แบบ DNS only ก็ครบทุกตัว — docs/11-cloudflare.md" >&2
  fi
  if [ -n "$elsewhere" ]; then
    echo "  ชื่อเหล่านี้ชี้ไปเครื่องอื่น (เช่นเครื่องเก่าที่ใช้ BASE_DOMAIN เดียวกัน):" >&2
    for pair in $elsewhere; do
      echo "    ${pair%%=*}.$DOMAIN → ตอนนี้ ${pair#*=}" >&2
    done
    echo "  ย้ายมาเครื่องนี้: Cloudflare → DNS → Edit record → IPv4: $SERVER_IP" >&2
    echo "  เครื่องเก่ายังใช้อยู่? ห้ามแย่งชื่อ — ตั้ง BASE_DOMAIN เป็นชื่อย่อยแทน (docs/11-cloudflare.md)" >&2
  fi
  echo "  แก้แล้วรอ 1–5 นาที แล้วรันคำสั่งเดิมอีกครั้ง" >&2
  echo "  ถ้าเพิ่งย้าย nameserver ไป Cloudflare อาจต้องรอหลายชั่วโมง — docs/11-cloudflare.md" >&2
  exit 1
fi
if [ "$proxied" -gt 0 ]; then
  echo "⚠️  $proxied ชื่อเป็น Proxied (เมฆส้ม) — ตรวจใน Cloudflare ว่า IPv4 ของ record เป็น $SERVER_IP"
  echo "   (ถ้ายังเป็น IP เครื่องเก่า cert ของเครื่องนี้จะออกไม่ได้)"
fi
echo "✅ DNS ครบสำหรับ: $*"
