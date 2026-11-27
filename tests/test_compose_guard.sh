# shellcheck shell=bash
# compose ที่มาจาก repo ของผู้ใช้ — ห้ามมีสิ่งที่ให้ container คุมเครื่องได้ (scripts/lib/compose-guard.sh)

_guard_setup() {
  mk_sandbox
  # shellcheck source=scripts/lib/compose-guard.sh
  . "$SANDBOX/scripts/lib/compose-guard.sh"
  CF="$SANDBOX/docker-compose.yml"
}

_safe_compose() {
  cat <<'EOF'
services:
  api:
    image: ${APP_IMAGE}
    read_only: true
    cap_drop: [ALL]
    security_opt: [no-new-privileges:true]
    volumes:
      - ./data:/app/data
    labels:
      - "docker-rollout.pre-stop-hook=touch /tmp/drain && sleep 35"
EOF
}

test_guard_accepts_safe_compose() {
  _guard_setup
  _safe_compose > "$CF"
  compose_guard "$CF" >/dev/null
}

_assert_rejected() {
  local extra="$1" msg="$2"
  { _safe_compose; printf '%s\n' "$extra"; } > "$CF"
  assert_fail "$msg" compose_guard "$CF"
}

test_guard_rejects_docker_socket() {
  _guard_setup
  _assert_rejected "      - /var/run/docker.sock:/var/run/docker.sock" "docker.sock mount"
}

test_guard_rejects_privileged() {
  _guard_setup
  _assert_rejected "    privileged: true" "privileged"
}

test_guard_rejects_host_namespaces() {
  _guard_setup
  _assert_rejected "    network_mode: host" "network_mode host"
  _assert_rejected '    pid: "host"' "pid host"
  _assert_rejected "    ipc: host" "ipc host"
}

test_guard_rejects_dangerous_caps() {
  _guard_setup
  _assert_rejected "    cap_add: [SYS_ADMIN]" "cap_add SYS_ADMIN"
  _assert_rejected $'    cap_add:\n      - ALL' "cap_add ALL"
}

test_guard_rejects_root_bind_mount() {
  _guard_setup
  _assert_rejected "      - /:/host" "bind mount of /"
  _assert_rejected "      - /etc:/host-etc:ro" "bind mount of /etc"
}

test_guard_message_names_the_problem() {
  _guard_setup
  { _safe_compose; echo "    privileged: true"; } > "$CF"
  local out
  out="$(compose_guard "$CF" 2>&1 || true)"
  assert_contains "$out" "privileged" "message names the finding"
}

test_guard_allows_tmpfs_and_relative_mounts() {
  _guard_setup
  { _safe_compose; cat <<'YML'
    tmpfs:
      - /tmp:size=64m,mode=1777
      - /var/cache/nginx:size=32m,mode=0755
YML
  } > "$CF"
  compose_guard "$CF" >/dev/null
}

test_guard_ignores_comments() {
  _guard_setup
  { _safe_compose; echo "    # privileged: true  ← ห้ามใช้"; } > "$CF"
  compose_guard "$CF" >/dev/null
}
