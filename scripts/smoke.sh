#!/usr/bin/env bash
# Smoke test project ที่ deploy แล้ว — อ่านอย่างเดียว ไม่แก้ DB/ไฟล์/container
# ใช้หลัง deploy หรือให้ AI ตรวจว่าเว็บยังดีอยู่ (ดู docs/28-testing-on-vps.md)
#
# ใช้: ./scripts/smoke.sh <project> [path...]
# เช่น: ./scripts/smoke.sh lunara
#       ./scripts/smoke.sh lunara /login /pricing     (เช็ค path เพิ่ม ต้องได้ < 500)
#
# ตรวจ: container รัน/healthy · image ไม่ค้างเวอร์ชันเก่า · health endpoint 200 ผ่าน Traefik
#       · หน้าแรก < 500 · cert ใช้ได้ · error ใน log 15 นาทีล่าสุด · migration ค้าง (Laravel)
# exit 0 = ผ่านหมด (อาจมี WARN) · exit 1 = มี FAIL
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

NAME="${1:?usage: smoke.sh <project> [path...]}"
shift
DIR="projects/$NAME"
[ -f "$DIR/docker-compose.yml" ] || { echo "ERROR: $DIR not found" >&2; exit 1; }
cd "$DIR" || exit 1

FAILS=0
ok()   { echo "  ✅ $*"; }
warn() { echo "  ⚠️  $*"; }
fail() { echo "  ❌ $*"; FAILS=$((FAILS + 1)); }
envget() { grep -E "^$1=" .env 2>/dev/null | head -1 | cut -d= -f2- || true; }

DOMAIN="$(envget APP_DOMAIN)"
HEALTH="$(envget HEALTHCHECK_PATH)"
APP_SVC="$(envget ROLLOUT_SERVICE)"
APP_SVC="${APP_SVC:-$NAME-app}"

echo "── [smoke:$NAME] containers"
SERVICES="$(docker compose config --services 2>/dev/null)"
for svc in $SERVICES; do
  cids="$(docker compose ps -q "$svc" 2>/dev/null)"
  if [ -z "$cids" ]; then fail "$svc: ไม่มี container รันอยู่"; continue; fi
  for cid in $cids; do
    state="$(docker inspect -f '{{.State.Status}}' "$cid")"
    health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$cid")"
    restarts="$(docker inspect -f '{{.RestartCount}}' "$cid")"
    ref="$(docker inspect -f '{{.Config.Image}}' "$cid")"
    stale=""
    [ "$(docker inspect -f '{{.Image}}' "$cid")" = "$(docker image inspect -f '{{.Id}}' "$ref" 2>/dev/null)" ] || stale=" (รัน image เก่า — deploy ใหม่)"
    if [ "$state" != running ] || [ "$health" = unhealthy ]; then
      fail "$svc: $state${health:+/$health}"
    elif [ -n "$stale" ]; then
      fail "$svc: $state${health:+/$health}$stale"
    elif [ "$restarts" -gt 0 ] && docker inspect -f '{{join .Config.Cmd " "}}' "$cid" | grep -q -- '--max-time'; then
      ok "$svc: $state — restart $restarts ครั้งตามรอบ --max-time (ปกติ)"
    elif [ "$restarts" -gt 0 ]; then
      warn "$svc: $state${health:+/$health} — restart แล้ว $restarts ครั้ง"
    else
      ok "$svc: $state${health:+/$health}"
    fi
  done
done

# ยิงผ่าน Traefik บนเครื่องนี้ (--resolve) — ไม่ขึ้นกับ DNS ภายนอก ใช้ได้ก่อนย้าย DNS
if [ -n "$DOMAIN" ]; then
  echo "── [smoke:$NAME] http via Traefik (https://$DOMAIN)"
  RESOLVE=(--resolve "$DOMAIN:443:127.0.0.1")
  INSECURE=()
  if curl -sS -o /dev/null "${RESOLVE[@]}" --max-time 15 "https://$DOMAIN/" 2>/dev/null; then
    end="$(echo | openssl s_client -connect 127.0.0.1:443 -servername "$DOMAIN" 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)"
    ok "cert ใช้ได้${end:+ (หมดอายุ $end)}"
  else
    warn "cert ยังไม่ valid (DNS ยังไม่ชี้มาเครื่องนี้ / Let's Encrypt ยังไม่ออก) — เช็ค http ต่อแบบ -k"
    INSECURE=(-k)
  fi
  check_path() {   # check_path <path> <expect: 200|lt500>
    local code
    code="$(curl -sS -o /dev/null -w '%{http_code}' "${RESOLVE[@]}" "${INSECURE[@]}" --max-time 20 "https://$DOMAIN$1" 2>/dev/null || echo 000)"
    if [ "$2" = 200 ] && [ "$code" = 200 ]; then ok "GET $1 → $code"
    elif [ "$2" = lt500 ] && [ "$code" != 000 ] && [ "$code" -lt 500 ]; then ok "GET $1 → $code"
    else fail "GET $1 → $code"; fi
  }
  [ -n "$HEALTH" ] && check_path "$HEALTH" 200
  check_path / lt500
  for p in "$@"; do check_path "$p" lt500; done
else
  warn "ไม่มี APP_DOMAIN ใน .env — ข้ามการเช็ค http"
fi

echo "── [smoke:$NAME] logs (15 นาทีล่าสุด)"
for svc in $SERVICES; do
  errs="$(docker compose logs --no-color --since 15m "$svc" 2>/dev/null \
    | grep -E '(production|local)\.(ERROR|CRITICAL|ALERT|EMERGENCY)|PHP (Fatal|Parse) error|Unhandled|uncaught|"level":"error"|\[error\]' || true)"
  if [ -n "$errs" ]; then
    warn "$svc: $(printf '%s\n' "$errs" | wc -l) บรรทัด error — ล่าสุด:"
    printf '%s\n' "$errs" | tail -3 | cut -c1-300 | sed 's/^/       /'
  else
    ok "$svc: ไม่มี error"
  fi
done

if docker compose exec -T "$APP_SVC" test -f artisan 2>/dev/null; then
  echo "── [smoke:$NAME] laravel"
  pending="$(docker compose exec -T "$APP_SVC" php artisan migrate:status 2>/dev/null | grep -c 'Pending' || true)"
  if [ "${pending:-0}" -gt 0 ]; then fail "migration ค้าง $pending ตัว (./scripts/artisan.sh $NAME migrate:status)"
  else ok "migration ครบ"; fi
fi

echo
if [ "$FAILS" -gt 0 ]; then
  echo "❌ [smoke:$NAME] FAIL $FAILS รายการ — $(date '+%F %T')"
  exit 1
fi
echo "✅ [smoke:$NAME] ผ่าน — $(date '+%F %T')"
