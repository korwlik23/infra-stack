# shellcheck shell=bash
# ตรวจ docker-compose.yml ที่มาจาก repo ของผู้ใช้ (infra new <ชื่อ> <starter|owner/repo>) ก่อนใช้งาน
# compose_guard <file> → exit 1 + บอกบรรทัดที่เจอ ถ้ามีสิ่งที่ให้ container คุมเครื่องได้:
#   docker.sock · privileged · network_mode/pid/ipc: host · cap_add ALL/SYS_ADMIN/…
#   bind mount ของ / หรือโฟลเดอร์ระบบ (/etc /root /proc /sys /dev /boot /run /var/run /var/lib/docker /home)
# ⚠️ เป็นด่านกรองแบบอ่านข้อความ ไม่ใช่ sandbox — ใช้กับ repo ที่ไว้ใจเท่านั้น (docs/32)

compose_guard() {
  local file="$1" found
  [ -f "$file" ] || { echo "ERROR: ไม่มี $file" >&2; return 1; }
  # ตัด comment ทิ้งก่อน (บรรทัด # … และ # ท้ายบรรทัด) แล้วค้นด้วย grep -n ให้เห็นเลขบรรทัด
  found="$(sed -E 's/(^|[[:space:]])#.*$//' "$file" | grep -nE \
    -e 'docker\.sock' \
    -e '^[[:space:]]*privileged:[[:space:]]*"?(true|yes)"?' \
    -e '^[[:space:]]*(network_mode|pid|ipc|userns_mode|uts|cgroup):[[:space:]]*"?host"?' \
    -e '^[[:space:]]*cap_add:.*(ALL|SYS_ADMIN|SYS_PTRACE|SYS_MODULE|NET_ADMIN|DAC_READ_SEARCH|SYS_RAWIO)' \
    -e '^[[:space:]]*-[[:space:]]*"?(ALL|SYS_ADMIN|SYS_PTRACE|SYS_MODULE|NET_ADMIN|DAC_READ_SEARCH|SYS_RAWIO)"?[[:space:]]*$' \
    -e '^[[:space:]]*-[[:space:]]*"?/(etc|root|proc|sys|dev|boot|run|var/run|var/lib/docker|home)?(/[^:]*)?:' \
    -e '^[[:space:]]*source:[[:space:]]*"?/(etc|root|proc|sys|dev|boot|run|var/run|var/lib/docker|home)?(/[^"]*)?"?[[:space:]]*$' \
    || true)"
  [ -z "$found" ] && return 0
  echo "❌ $file มีค่าที่ให้ container คุมเครื่องได้ — ไม่ใช้ template นี้:" >&2
  printf '%s\n' "$found" | sed 's/^/   บรรทัด /' >&2
  echo "   (privileged / docker.sock / host namespace / cap_add อันตราย / bind mount โฟลเดอร์ระบบ)" >&2
  echo "   ถ้าจำเป็นจริง: สร้าง project ด้วย template ในตัวแล้วแก้ compose เอง (ผ่าน infra audit)" >&2
  return 1
}
