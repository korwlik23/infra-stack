# shellcheck shell=bash
# scripts/lib/deploy-db.sh — migrate รันใน service ไหน (stub docker จดคำสั่งไว้ใน $DOCKER_LOG)

_deploydb_setup() {
  mk_sandbox
  DOCKER_LOG="$SANDBOX/docker.log"
  # คำสั่ง hash ไฟล์ seed → ตอบเหมือนมีไฟล์ seed หนึ่งไฟล์
  printf '#!/usr/bin/env bash\necho "$*" >> "%s"\ncase "$*" in *sha256sum*) echo "abc  /app/bootstrap" ;; esac\n' \
    "$DOCKER_LOG" > "$SANDBOX/bin/docker"
  chmod +x "$SANDBOX/bin/docker"
  mkdir -p "$SANDBOX/projects/p"
  cd "$SANDBOX/projects/p"
  # shellcheck source=scripts/lib/deploy-db.sh
  . "$SANDBOX/scripts/lib/deploy-db.sh"
}

test_migrate_runs_in_rollout_service_by_default() {
  _deploydb_setup
  printf 'DEPLOY_MIGRATE=1\nDEPLOY_MIGRATE_CMD=/app/migrate\nDEPLOY_SEED_CMD=none\n' > .env
  deploy_db p api no >/dev/null
  assert_contains "$(cat "$DOCKER_LOG")" "compose run --rm --no-deps -T --entrypoint sh api -c /app/migrate" "runs in api"
}

test_migrate_runs_in_deploy_migrate_service() {
  _deploydb_setup
  printf 'DEPLOY_MIGRATE=1\nDEPLOY_MIGRATE_SERVICE=api-migrate\nDEPLOY_MIGRATE_CMD=/app/migrate\nDEPLOY_SEED_CMD=/app/bootstrap\n' > .env
  deploy_db p api yes >/dev/null
  local log; log="$(cat "$DOCKER_LOG")"
  assert_contains "$log" "--entrypoint sh api-migrate -c /app/migrate" "migrate in api-migrate"
  assert_contains "$log" "--entrypoint sh api-migrate -c /app/bootstrap" "seed in api-migrate"
  [[ "$log" != *"--entrypoint sh api -c"* ]] || { echo "    ✗ something still ran in api"; return 1; }
}
