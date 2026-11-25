#!/usr/bin/env bash
# อัปเดตแพตช์ของ image ใน stack (Traefik / Grafana / Netdata / phpMyAdmin …) อัตโนมัติ — แทน Watchtower
# ใช้: infra update --auto           อัปเดตตัวที่มี image ใหม่ (cron ทุกอาทิตย์ 04:30 — infra cron)
#      infra update --auto --check   ดูอย่างเดียวว่าตัวไหนมี image ใหม่ (ไม่ pull ไม่ restart)
#
# ทำอะไร (ต่อ service ที่ "รันอยู่" ใน stack core / monitoring / tools / messaging / storage):
#   เทียบ digest ใน registry กับ image ที่ container ใช้อยู่ → ต่าง = pull + recreate เฉพาะ service นั้น
#   → รอ healthy (มี healthcheck) หรือรันนิ่ง 20 วินาที (ไม่มี) → ไม่ผ่าน = ถอยกลับ image เดิมเอง
#   แจ้ง Telegram เฉพาะเมื่อมีอะไรเปลี่ยน / ล้ม
# ได้แค่แพตช์ใน tag เดิม (phpmyadmin:5 → 5.x ล่าสุด) — เปลี่ยน major/minor ต้องแก้ tag ใน compose เอง
#   tag :latest ข้าม major ได้ → pin เลขไว้ใน compose (เช่น grafana/grafana:13.3) ก่อนเปิด
# ไม่แตะ:
#   database / mysql stack — restart = ทุกแอปต่อ DB ไม่ได้ · สั่งเองหลัง backup: infra update database|mysql
#   service ที่ไม่ได้เปิดไว้ (ไม่ start ตัวที่ไม่เคยรัน) · ชื่อใน STACK_UPDATE_SKIP (.env กลาง คั่นด้วยช่องว่าง)
#   ปิดทั้งหมด: STACK_UPDATE=0
set -uo pipefail
cd "$(dirname "$(readlink -f "$0")")/.." || exit 1
ROOT="$PWD"
# shellcheck source=scripts/lib/notify.sh
. "$ROOT/scripts/lib/notify.sh"

CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1
exec 9>.stack-update.lock
flock -n 9 || { echo "[stack-update] รันอยู่แล้ว — ข้าม"; exit 0; }

env_val() { grep -E "^$1=" "$ROOT/.env" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '\r' | sed -E 's/^"(.*)"$/\1/' || true; }
log() { echo "[stack-update] $(date '+%F %T') $*"; }
[ "$(env_val STACK_UPDATE)" != 0 ] || { log "ปิดอยู่ (STACK_UPDATE=0)"; exit 0; }
SKIP=" $(env_val STACK_UPDATE_SKIP) "

remote_digest() { docker buildx imagetools inspect "$1" 2>/dev/null | awk '/^Digest:/ {print $2; exit}'; }
local_digests() { docker image inspect -f '{{range .RepoDigests}}{{println .}}{{end}}' "$1" 2>/dev/null | sed 's/.*@//'; }

# รอให้ container ใหม่พร้อม: มี healthcheck = healthy ใน 120 วินาที · ไม่มี = ยังรันอยู่หลัง 20 วินาทีโดยไม่ restart
wait_ready() {
  local svc="$1" file="$2" cid st i
  for i in $(seq 1 24); do
    sleep 5
    cid="$(docker compose --env-file .env -f "$file" ps -q "$svc" 2>/dev/null | head -1)"
    [ -n "$cid" ] || continue
    st="$(docker inspect -f '{{.State.Status}}|{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}|{{.RestartCount}}' "$cid" 2>/dev/null)"
    case "$st" in
      running\|healthy\|*) return 0 ;;
      running\|none\|0) [ "$i" -ge 4 ] && return 0 ;;
      running\|starting\|*) ;;
      *) return 1 ;;
    esac
  done
  return 1
}

UPDATED=(); FAILED=(); PENDING=()
for s in core monitoring tools messaging storage; do
  file="docker/docker-compose.$s.yml"
  [ -f "$file" ] || continue
  while read -r svc; do
    [ -n "$svc" ] || continue
    case "$SKIP" in *" $svc "*) log "$svc: ข้าม (STACK_UPDATE_SKIP)"; continue ;; esac
    cid="$(docker compose --env-file .env -f "$file" ps -q "$svc" 2>/dev/null | head -1)"
    [ -n "$cid" ] || continue                                   # ไม่ได้เปิดไว้ — ไม่ start ให้
    ref="$(docker inspect -f '{{.Config.Image}}' "$cid")"
    old="$(docker inspect -f '{{.Image}}' "$cid")"
    rd="$(remote_digest "$ref")"
    [ -n "$rd" ] || { log "$svc: ⚠️ อ่าน digest ของ $ref จาก registry ไม่ได้ — ข้ามรอบนี้"; continue; }
    if local_digests "$old" | grep -qxF "$rd"; then continue; fi
    if [ "$CHECK" = 1 ]; then PENDING+=("$svc ($ref)"); continue; fi

    log "$svc: มี image ใหม่ของ $ref → อัปเดต…"
    if ! docker pull -q "$ref" >/dev/null 2>&1; then
      log "$svc: ⚠️ pull $ref ไม่ได้ — ข้ามรอบนี้"; continue
    fi
    new="$(docker image inspect -f '{{.Id}}' "$ref")"
    [ "$new" != "$old" ] || continue                            # digest ต่างแต่ image เดิม (multi-arch index เปลี่ยน)
    if docker compose --env-file .env -f "$file" up -d --no-deps "$svc" >/dev/null 2>&1 && wait_ready "$svc" "$file"; then
      log "$svc: ✅ อัปเดตแล้ว"; UPDATED+=("$svc")
    else
      # ถอยกลับ: ชี้ tag กลับไปที่ image เดิม (ยังอยู่ในเครื่อง — container เก่าเพิ่งใช้) แล้ว recreate
      docker tag "$old" "$ref"
      docker compose --env-file .env -f "$file" up -d --no-deps "$svc" >/dev/null 2>&1
      if wait_ready "$svc" "$file"; then
        log "$svc: ↩️ image ใหม่ไม่ผ่าน → ถอยกลับเวอร์ชันเดิมแล้ว"; FAILED+=("$svc (ถอยกลับแล้ว)")
      else
        log "$svc: ❌ image ใหม่ไม่ผ่าน และถอยกลับแล้วก็ยังไม่ขึ้น — infra logs $svc"; FAILED+=("$svc (ยังไม่ขึ้น!)")
      fi
    fi
  done < <(docker compose --env-file .env -f "$file" config --services 2>/dev/null)
done

if [ "$CHECK" = 1 ]; then
  if [ ${#PENDING[@]} -gt 0 ]; then printf 'มี image ใหม่:\n'; printf '  %s\n' "${PENDING[@]}"
  else echo "✅ ทุกตัวล่าสุดแล้ว"; fi
  exit 0
fi

[ ${#UPDATED[@]} -gt 0 ] || [ ${#FAILED[@]} -gt 0 ] || { log "✅ ทุกตัวล่าสุดแล้ว"; exit 0; }
docker image prune -f >/dev/null 2>&1 || true
msg="🔄 อัปเดตแพตช์ stack"
[ ${#UPDATED[@]} -eq 0 ] || msg="$msg"$'\n'"✅ ${UPDATED[*]}"
[ ${#FAILED[@]} -eq 0 ] || msg="$msg"$'\n'"⚠️ ${FAILED[*]} — ดู: infra logs stack-update"
notify "$msg"
[ ${#FAILED[@]} -eq 0 ]
