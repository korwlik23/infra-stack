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

missing=""
count=0
for stack in "$@"; do
  file="docker/docker-compose.$stack.yml"
  [ -f "$file" ] || { echo "ERROR: ไม่มี stack '$stack' ($file)" >&2; exit 1; }
  # include: - ../services/<name>/docker-compose.yml → services/<name>/docker-compose.yml
  for svc in $(sed -n 's|^ *- *\.\./\(services/[^ ]*\.yml\) *$|\1|p' "$file"); do
    # ข้ามบรรทัด comment (เช่น beszel-agent ที่ปิดไว้)
    for sub in $(grep -v '^ *#' "$svc" | grep -o 'Host(`[a-z0-9-]*\.\${BASE_DOMAIN}`)' \
                   | sed 's/^Host(`\([a-z0-9-]*\)\..*/\1/' || true); do
      host="$sub.$DOMAIN"
      if getent hosts "$host" >/dev/null 2>&1; then
        echo "  ✅ $host"
      else
        echo "  ❌ $host"
        missing="$missing $sub"
        count=$((count + 1))
      fi
    done
  done
done

if [ "$count" -gt 0 ]; then
  echo "" >&2
  echo "ERROR: ยังไม่มี DNS record $count ตัว — ยังไม่ start เพื่อกัน Let's Encrypt แบน" >&2
  echo "  ไปที่ Cloudflare → DNS → Add record ทีละตัว (ช่อง Name ใส่ชื่อเต็มได้ Cloudflare ตัดโดเมนหลักให้เอง):" >&2
  for sub in $missing; do
    echo "    Type: A   Name: $sub.$DOMAIN   IPv4: <IP ของ VPS>" >&2
  done
  echo "  BASE_DOMAIN เป็นชื่อย่อย (เช่น sg.example.com — เครื่องเสริม)? ตั้ง Proxy เป็น DNS only (เมฆเทา)" >&2
  echo "  หรือสร้าง record เดียว Name: *.$DOMAIN แบบ DNS only ก็ครบทุกตัว — docs/11-cloudflare.md" >&2
  echo "  (IP ของ VPS ดูได้จากหน้า provider — เครื่องนี้เห็นตัวเองเป็น: $(hostname -I 2>/dev/null | awk '{print $1}'))" >&2
  echo "  สร้างแล้วรอ 1–5 นาที แล้วรันคำสั่งเดิมอีกครั้ง" >&2
  echo "  ถ้าเพิ่งย้าย nameserver ไป Cloudflare อาจต้องรอหลายชั่วโมง — docs/11-cloudflare.md" >&2
  exit 1
fi
echo "✅ DNS ครบสำหรับ: $*"
