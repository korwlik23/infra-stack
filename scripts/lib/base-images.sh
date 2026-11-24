# shellcheck shell=bash
# base image ของ image ที่ project build บนเครื่อง — ใช้โดย refresh.sh (base มีแพตช์ใหม่ไหม)

# base image ภายนอกของ stage ที่รันจริง (stage สุดท้าย หรือ <target>) — พิมพ์บรรทัดเดียว / ไม่พิมพ์ถ้าหาไม่ได้
# ตามชื่อ stage ย้อนจนเจอ image ภายนอก: FROM php:8.3-fpm AS base … FROM base AS app → php:8.3-fpm
# แทนค่า ARG ที่มี default: ARG PHP_VERSION=8.3 + FROM php:${PHP_VERSION}-fpm → php:8.3-fpm
# stage build อย่างเดียว (node สำหรับ asset, composer) ไม่อยู่ใน image ที่รัน → ไม่นับ
# หาไม่ได้: scratch · ARG ที่ไม่มี default (รู้ค่าไม่ได้โดยไม่ build) — ใส่ใน compose build.args ไม่ถูกอ่าน
dockerfile_runtime_base() {   # <Dockerfile> [target]
  [ -f "$1" ] || return 0
  tr -d '\r' < "$1" | awk -v target="$(printf '%s' "${2:-}" | tr '[:upper:]' '[:lower:]')" '
    function subst(s,   tok, name) {
      while (match(s, /\$\{?[A-Za-z_][A-Za-z0-9_]*\}?/)) {
        tok = substr(s, RSTART, RLENGTH); name = tok; gsub(/[${}]/, "", name)
        if (!(name in arg)) return s
        s = substr(s, 1, RSTART - 1) arg[name] substr(s, RSTART + RLENGTH)
      }
      return s
    }
    toupper($1) == "ARG" {
      eq = index($2, "=")
      if (eq > 0) { v = substr($2, eq + 1); gsub(/^"|"$/, "", v); arg[substr($2, 1, eq - 1)] = subst(v) }
    }
    toupper($1) == "FROM" {
      i = 2; while ($i ~ /^--/) i++
      img = subst($i); key = tolower(img)
      base = (key in root) ? root[key] : img            # FROM <stage> → base ของ stage นั้น
      if (toupper($(i + 1)) == "AS") root[tolower($(i + 2))] = base
      last = base
      if (target != "" && tolower($(i + 2)) == target) { found = base }
    }
    END {
      b = (target != "" && found != "") ? found : last
      if (b != "" && b !~ /\$/ && tolower(b) != "scratch") print b
    }'
}

# "<Dockerfile เต็ม>|<target>" ที่ project ใช้ build — ลำดับ:
#   DEPLOY_DOCKERFILE ใน .env ของ project (relative กับ projects/<name>)
#   build.context / dockerfile / target จาก docker compose config (service แรกที่มี build)
#   src/Dockerfile
project_build_info() {   # <dir ของ project>
  local dir="$1" f ctx df tg
  f="$(grep -E '^DEPLOY_DOCKERFILE=' "$dir/.env" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '\r"' || true)"
  if [ -n "$f" ]; then printf '%s/%s|' "$dir" "$f"; return; fi
  f="$(cd "$dir" && docker compose config 2>/dev/null | awk '
    function out() { print ctx "|" (df == "" ? "Dockerfile" : df) "|" tg; done = 1 }
    /^    build:/ { inb = 1; next }
    inb && /^      context:/ { ctx = $2 }
    inb && /^      dockerfile:/ { df = $2 }
    inb && /^      target:/ { tg = $2 }
    inb && !/^      / { if (ctx != "") { out(); exit } inb = 0 }
    END { if (!done && inb && ctx != "") out() }' || true)"
  if [ -n "$f" ]; then
    ctx="${f%%|*}"; f="${f#*|}"; df="${f%%|*}"; tg="${f#*|}"
    case "$df" in /*) ;; *) df="$ctx/$df" ;; esac
    printf '%s|%s' "$df" "$tg"
    return
  fi
  printf '%s/src/Dockerfile|' "$dir"
}

# image <app> build บน <base> เวอร์ชันนี้ไหม — layer ของ app ขึ้นต้นด้วย layer ทั้งหมดของ base
# ไม่ต้องจดอะไรไว้: base ใน registry ออกแพตช์ใหม่ = layer เปลี่ยน = ไม่ใช่ prefix แล้ว
image_built_on() {   # <app image> <base image>
  local app base
  app="$(docker image inspect -f '{{range .RootFS.Layers}}{{println .}}{{end}}' "$1" 2>/dev/null)" || return 1
  base="$(docker image inspect -f '{{range .RootFS.Layers}}{{println .}}{{end}}' "$2" 2>/dev/null)" || return 1
  [ -n "$base" ] && [[ "$app" == "$base"* ]]
}
