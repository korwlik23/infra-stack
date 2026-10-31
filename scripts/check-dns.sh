#!/usr/bin/env bash
# เช็คว่าทุก subdomain ของ stack มี DNS record ที่ชี้มาเครื่องนี้แล้ว — ก่อนเปิด Traefik / stack ที่มีหน้าเว็บ
# ไม่มี record หรือชี้ไปเครื่องอื่น → Traefik ขอ cert ล้มซ้ำจน Let's Encrypt แบนราว 1 ชั่วโมง (docs/04)
# ใช้: ./scripts/check-dns.sh [--wait] <stack|hostname> […]
#        stack    = docker/docker-compose.<stack>.yml (core, monitoring, tools, messaging, storage)
#                   รายชื่อ subdomain อ่านจาก Host(`…`) ใน compose ของแต่ละ service — ไม่มีรายการซ้ำให้ลืมแก้
#        hostname = ชื่อเต็มที่มีจุด เช่น n8n.example.com (เว็บของ project — APP_DOMAIN)
#        --wait   = ไม่หยุดเมื่อยังไม่ครบ: เช็คทุก 30 วินาทีจนครบ (install.sh ใช้ระหว่างรอผู้ใช้สร้าง record)
# ข้ามได้ (เช่นใช้ wildcard record ที่ยังไม่ propagate): SKIP_DNS_CHECK=1
set -euo pipefail
cd "$(dirname "$0")/.."

WAIT=0
LIST=0
case "${1:-}" in
  --wait) WAIT=1; shift ;;
  --list) LIST=1; shift ;;   # พิมพ์แค่รายชื่อ host (install.sh / infra ใช้เช็ค cert)
esac
[ $# -gt 0 ] || { echo "usage: $0 [--wait|--list] <core|monitoring|tools|messaging|storage|hostname> […]" >&2; exit 1; }

if [ "$LIST" = 0 ] && [ "${SKIP_DNS_CHECK:-0}" = "1" ]; then
  echo "⚠️  SKIP_DNS_CHECK=1 — ข้ามการเช็ค DNS (ถ้า record ยังไม่มี cert จะล้ม)"
  exit 0
fi

[ -f .env ] || { echo "ERROR: ไม่มี .env — รัน ./install.sh ก่อน" >&2; exit 1; }
DOMAIN="$(grep -E '^BASE_DOMAIN=' .env | head -1 | cut -d= -f2- | tr -d ' \r' || true)"
[ -n "$DOMAIN" ] || { echo "ERROR: BASE_DOMAIN ใน .env ว่าง" >&2; exit 1; }

# ── รายชื่อที่ต้องเช็ค ─────────────────────────────────
HOSTS=()
for arg in "$@"; do
  case "$arg" in
    *.*) HOSTS+=("$arg"); continue ;;
  esac
  file="docker/docker-compose.$arg.yml"
  [ -f "$file" ] || { echo "ERROR: ไม่มี stack '$arg' ($file)" >&2; exit 1; }
  # include: - ../services/<name>/docker-compose.yml → services/<name>/docker-compose.yml
  for svc in $(sed -n 's|^ *- *\.\./\(services/[^ ]*\.yml\) *$|\1|p' "$file"); do
    # ข้ามบรรทัด comment (เช่น beszel-agent ที่ปิดไว้)
    for sub in $(grep -v '^ *#' "$svc" | grep -o 'Host(`[a-z0-9-]*\.\${BASE_DOMAIN}`)' \
                   | sed 's/^Host(`\([a-z0-9-]*\)\..*/\1/' || true); do
      HOSTS+=("$sub.$DOMAIN")
    done
  done
done
if [ "$LIST" = 1 ]; then printf '%s\n' "${HOSTS[@]}"; exit 0; fi

# ── IP ของเครื่องนี้ — เช็คว่า record ชี้มาที่นี่จริง ไม่ใช่แค่ "มีชื่อ" ─────
# (เจอจริง 2026-10: BASE_DOMAIN ซ้ำกับเครื่องเก่า → portainer.* resolve ได้แต่ชี้ไปเครื่องเก่า แล้วผ่าน)
# hostname -I อาจเป็น IP ภายใน (NAT) → ถาม public IP จาก Cloudflare trace ด้วย; หาไม่ได้ = ข้ามการเทียบ
SELF_IPS=" $(hostname -I 2>/dev/null || true) "
PUBLIC_IP="$(curl -4 -fsS -m 5 https://1.1.1.1/cdn-cgi/trace 2>/dev/null | sed -n 's/^ip=//p' || true)"
[ -z "$PUBLIC_IP" ] || SELF_IPS="$SELF_IPS$PUBLIC_IP "
SERVER_IP="${PUBLIC_IP:-$(hostname -I 2>/dev/null | awk '{print $1}')}"

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

# ถาม 1.1.1.1 ตรง (DNS-over-HTTPS) ไม่ผ่าน resolver ของเครื่อง — systemd-resolved จำคำตอบ
# "ไม่มีชื่อนี้" ไว้ได้นานถึง 30 นาที รอ record ใหม่แล้วจะไม่เห็นสักที; ต่อไม่ได้ค่อยใช้ getent
resolve_a() {
  local out
  if out="$(curl -fsS -m 5 -H 'accept: application/dns-json' \
              "https://1.1.1.1/dns-query?name=$1&type=A" 2>/dev/null)"; then
    # ไม่มี record = grep ไม่เจอ → ต้องไม่ล้ม (set -e) แค่คืนค่าว่าง
    printf '%s' "$out" | grep -oE '"data":"[0-9]+(\.[0-9]+){3}"' | head -1 | cut -d'"' -f4 || true
  else
    getent ahostsv4 "$1" 2>/dev/null | awk 'NR==1 {print $1}' || true
  fi
}

# ── เช็คหนึ่งรอบ → ตาราง + นับ ─────────────────────────
# STATE[i] = ok | proxied | missing | elsewhere:<ip>
STATE=()
check_round() {
  local i ip
  ready=0; proxied=0; missing=0; elsewhere=0
  for i in "${!HOSTS[@]}"; do
    ip="$(resolve_a "${HOSTS[$i]}")"
    if [ -z "$ip" ]; then
      STATE[$i]=missing; missing=$((missing + 1))
    elif [ -z "$PUBLIC_IP" ] || [[ "$SELF_IPS" == *" $ip "* ]]; then
      STATE[$i]=ok; ready=$((ready + 1))
    elif is_cloudflare_ip "$ip"; then
      STATE[$i]=proxied; proxied=$((proxied + 1)); ready=$((ready + 1))
    else
      STATE[$i]="elsewhere:$ip"; elsewhere=$((elsewhere + 1))
    fi
  done
}

print_table() {
  local i w=4 h
  for h in "${HOSTS[@]}"; do [ ${#h} -le $w ] || w=${#h}; done
  printf '  %-4s  %-*s  %-15s  %s\n' "Type" "$w" "Name" "IPv4" "สถานะ"
  for i in "${!HOSTS[@]}"; do
    case "${STATE[$i]}" in
      ok)          s="✅ ชี้มาที่นี่แล้ว" ;;
      proxied)     s="✅ Proxied (เมฆส้ม) — ตรวจใน Cloudflare ว่า IP เป็นเครื่องนี้" ;;
      missing)     s="⏳ ยังไม่มี → Add record" ;;
      elsewhere:*) s="❌ ชี้ไป ${STATE[$i]#elsewhere:} (เครื่องอื่น) → Edit แก้ IP" ;;
    esac
    printf '  %-4s  %-*s  %-15s  %s\n' "A" "$w" "${HOSTS[$i]}" "$SERVER_IP" "$s"
  done
}

print_help() {
  echo "  Cloudflare → โดเมนของคุณ → DNS → Records → Add record (หรือ Edit แถวที่ชี้ผิด)"
  echo "  ช่อง Name ใส่ชื่อเต็มตามตารางได้ Cloudflare ตัดโดเมนหลักให้เอง"
  echo "  ทางลัด: record เดียว  A  *.$DOMAIN  →  $SERVER_IP  ครบทุกชื่อของ BASE_DOMAIN"
  echo "  BASE_DOMAIN เป็นชื่อย่อย (เช่น sg.example.com)? ตั้ง Proxy เป็น DNS only (เมฆเทา) — docs/11-cloudflare.md"
  if [ "$elsewhere" -gt 0 ]; then
    echo "  ชื่อที่ชี้ไปเครื่องอื่น: เครื่องเก่ายังใช้อยู่ห้ามแย่งชื่อ — ตั้ง BASE_DOMAIN เป็นชื่อย่อยแทน (docs/11)"
  fi
}

total=${#HOSTS[@]}
check_round

if [ "$WAIT" = 0 ]; then
  print_table
  if [ $((missing + elsewhere)) -gt 0 ]; then
    echo "" >&2
    echo "ERROR: DNS ยังไม่พร้อม $((missing + elsewhere)) ตัว — ยังไม่ start เพื่อกัน Let's Encrypt แบน" >&2
    print_help >&2
    echo "  แก้แล้วรอ 1–5 นาที แล้วรันคำสั่งเดิมอีกครั้ง" >&2
    echo "  ถ้าเพิ่งย้าย nameserver ไป Cloudflare อาจต้องรอหลายชั่วโมง — docs/11-cloudflare.md" >&2
    exit 1
  fi
  echo "✅ DNS ครบ $total/$total"
  exit 0
fi

# ── --wait: แสดงตารางใหม่เมื่อสถานะเปลี่ยน เช็คซ้ำจนครบ ─────────────
last=""
while :; do
  now="${STATE[*]}"
  if [ "$now" != "$last" ]; then
    echo ""
    print_table
    [ $((missing + elsewhere)) -eq 0 ] || print_help
    last="$now"
  fi
  if [ $((missing + elsewhere)) -eq 0 ]; then
    echo "✅ DNS ครบ $total/$total"
    exit 0
  fi
  printf '\r  เช็คทุก 30 วินาที … (%d/%d พร้อม)  ' "$ready" "$total"
  sleep 30
  check_round
done
