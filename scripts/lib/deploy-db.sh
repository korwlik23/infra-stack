# shellcheck shell=bash
# migrate + seed ตอน deploy — ใช้ได้ทุก stack (Laravel / Next.js+Prisma / Go / อื่น ๆ)
# source โดย scripts/deploy.sh (cwd = projects/<name>) แล้วเรียก deploy_db <name> <service> <seed-mode>
#
# รันด้วยโค้ดเวอร์ชันใหม่ "ก่อน" สลับ traffic — schema พร้อมก่อนโค้ดใหม่รับ request
# ถ้า migrate ล้ม: return ไม่ 0 → deploy.sh (set -e) หยุด ไม่ rollout → เว็บเก่ายังอยู่
# ⚠️ migration ต้องเป็น expand/contract — ระหว่าง rolling โค้ดเก่ายังรันกับ schema ใหม่ (docs/25)
#
# ค่าใน projects/<name>/.env (ค่า default = Laravel — project Laravel เดิมไม่ต้องแก้อะไร):
#   DEPLOY_MIGRATE=1          เปิดขั้นนี้
#   DEPLOY_MIGRATE_CMD        คำสั่ง migrate       (default: php artisan migrate --force)
#   DEPLOY_SEED_CMD           คำสั่ง seed ข้อมูลพื้นฐาน (default: php artisan db:seed --force · none = ไม่มี)
#   DEPLOY_SEED_PATHS         ไฟล์/โฟลเดอร์ seeder ไว้จับว่าเปลี่ยน (default: database/seeders)
#   DEPLOY_TOOLS_TARGET       stage ใน Dockerfile ที่มีเครื่องมือ migrate (เช่น prisma CLI)
#                             ว่าง = รันใน image ของ app เอง (Laravel / Go)
#   DEPLOY_AUTO_SEED=0        ปิด seed อัตโนมัติ (default เปิด) — ดูกติกา seed ด้านล่าง
#
# กติกา seed (เทียบ hash ไฟล์ seeder กับที่จำไว้ใน .deploy-seeders.sha256):
#   project ใหม่บนเครื่องนี้ (ยังไม่มี .deploy-seeders.sha256) → ถามก่อนเสมอ ([y/N])
#     ไม่มีคนตอบ (cron) → ไม่ seed — auto-deploy.sh พัก deploy ไว้รอคนรัน deploy.sh
#   project ที่เคย seed/ตอบแล้ว + seeder เปลี่ยน (push ใหม่) → seed เองเลย (seeder ต้องรันซ้ำได้)
#     DEPLOY_AUTO_SEED=0 → กลับไปถาม (มีคนตอบ) / ข้ามและเตือน (cron)
#   --seed = seed เลยไม่ถาม · --no-seed = ไม่ seed ไม่ถาม

_db_env() { grep -E "^$1=" .env 2>/dev/null | head -1 | cut -d= -f2- | sed -E 's/^"(.*)"$/\1/; s/^'"'"'(.*)'"'"'$/\1/' || true; }

# รันคำสั่ง shell ด้วยโค้ดเวอร์ชันใหม่ บน container ชั่วคราว (ไม่แตะตัวที่รับ traffic)
_db_run() {
  if [ -n "$_DB_TOOLS_IMAGE" ]; then
    docker run --rm --network backend --env-file .env "$_DB_TOOLS_IMAGE" sh -c "$1"
  else
    docker compose run --rm --no-deps -T --entrypoint sh "$_DB_SVC" -c "$1"
  fi
}

deploy_db() {
  local name="$1" seed_mode="$3"
  _DB_SVC="$2"
  _DB_TOOLS_IMAGE=""
  [ "$(_db_env DEPLOY_MIGRATE)" = "1" ] || return 0

  local migrate_cmd seed_cmd seed_paths tools_target auto_seed
  migrate_cmd="$(_db_env DEPLOY_MIGRATE_CMD)"; migrate_cmd="${migrate_cmd:-php artisan migrate --force}"
  seed_cmd="$(_db_env DEPLOY_SEED_CMD)";       seed_cmd="${seed_cmd:-php artisan db:seed --force}"
  seed_paths="$(_db_env DEPLOY_SEED_PATHS)";   seed_paths="${seed_paths:-database/seeders}"
  tools_target="$(_db_env DEPLOY_TOOLS_TARGET)"
  auto_seed="$(_db_env DEPLOY_AUTO_SEED)"

  # เครื่องมือ migrate ไม่อยู่ใน image ที่รันจริง (เช่น Next.js standalone ไม่มี prisma CLI)
  # → build เฉพาะ stage นั้นจาก src/ เดียวกัน (ไม่ต้อง build ทั้ง app ซ้ำ)
  if [ -n "$tools_target" ]; then
    [ -d src ] || { echo "[deploy:$name] ERROR: DEPLOY_TOOLS_TARGET ต้องมี src/ (build บนเครื่อง)" >&2; return 1; }
    local dockerfile
    dockerfile="$(grep -E '^[[:space:]]*dockerfile:' docker-compose.yml | head -1 | awk '{print $2}' | tr -d '"'"'" || true)"
    _DB_TOOLS_IMAGE="$name:tools"
    echo "[deploy:$name] building tools stage '$tools_target'…"
    docker build -q --target "$tools_target" -f "src/${dockerfile:-Dockerfile}" -t "$_DB_TOOLS_IMAGE" src >/dev/null
  fi

  echo "[deploy:$name] migrate: $migrate_cmd"
  _db_run "$migrate_cmd" || return 1

  # ── seed — project ใหม่ถามก่อน · project เดิมที่ seeder เปลี่ยน (push ใหม่) seed เอง ──
  # seed = "เติม" ข้อมูลพื้นฐาน (role / แพ็กเกจ / ค่าตั้งต้น) ลง DB เดิม ไม่ล้างตาราง → seeder ต้องรันซ้ำได้
  # (firstOrCreate / updateOrCreate / upsert) · จำ hash ไฟล์ seeder ที่ seed/ตอบแล้วใน .deploy-seeders.sha256
  if [ "$seed_cmd" != "none" ]; then
    local state=.deploy-seeders.sha256 current changed run_seed=no ask=no answer
    # shellcheck disable=SC2016 # $p ขยายใน container ไม่ใช่ที่นี่
    current="$(_db_run "for p in $seed_paths; do [ -e \"\$p\" ] && find \"\$p\" -type f; done | sort | xargs -r sha256sum" 2>/dev/null || true)"
    if [ -n "$current" ]; then
      changed="$(printf '%s\n' "$current" | grep -vxF -f "$state" 2>/dev/null | awk '{print $2}' || true)"
      [ -f "$state" ] || changed="$(printf '%s\n' "$current" | awk '{print $2}')"
      if [ "$seed_mode" = yes ]; then
        run_seed=yes
      elif [ "$seed_mode" = ask ] && [ -n "$changed" ]; then
        if [ ! -f "$state" ]; then
          echo "[deploy:$name] project ใหม่บนเครื่องนี้ — ยังไม่เคย seed:"
          ask=yes
        elif [ "$auto_seed" = "0" ]; then
          echo "[deploy:$name] seeder ใหม่/เปลี่ยน (DEPLOY_AUTO_SEED=0):"
          ask=yes
        else
          echo "[deploy:$name] seeder ใหม่/เปลี่ยน → seed ให้เลย (project เดิม — DEPLOY_AUTO_SEED=0 = ถามก่อน):"
          run_seed=yes
        fi
        printf '%s\n' "$changed" | sed 's/^/    /'
        if [ "$ask" = yes ] && [ -t 0 ]; then
          read -r -p "[deploy:$name] รัน seed ด้วยไหม? (เติมข้อมูล ไม่ล้าง DB เดิม) [y/N] " answer || answer=""
          case "$answer" in
            [Yy]*) run_seed=yes ;;
            *) printf '%s\n' "$current" > "$state"
               echo "[deploy:$name] ข้าม seed — ครั้งหน้า seeder เปลี่ยนจะ seed เอง (รันเอง: ./scripts/deploy.sh $name --seed)" ;;
          esac
        elif [ "$ask" = yes ]; then
          # ไม่มีคนตอบ — ไม่ seed เอง และไม่จำ hash เพื่อให้ deploy มือครั้งหน้าถามอีก
          echo "[deploy:$name] ⚠️ ไม่มีคนตอบ — ยังไม่ seed: รัน ./scripts/deploy.sh $name (ถาม) หรือ --seed"
        fi
      fi
    fi
    if [ "$run_seed" = yes ]; then
      echo "[deploy:$name] seed: $seed_cmd (ไม่ล้างข้อมูลเดิม)"
      _db_run "$seed_cmd" || return 1
      [ -n "$current" ] && printf '%s\n' "$current" > "$state"
    fi
  fi

  [ -z "$_DB_TOOLS_IMAGE" ] || docker image rm -f "$_DB_TOOLS_IMAGE" >/dev/null 2>&1 || true
}
