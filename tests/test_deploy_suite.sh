# shellcheck shell=bash
# infra deploy <suite> — deploy สมาชิกตามลำดับใน projects/<suite>.suite หยุดเมื่อตัวใดล้ม

_suite_setup() {
  mk_sandbox
  DEPLOY_LOG="$SANDBOX/deploy.log"
  printf 'shop-api\nshop-admin\nshop-site\n' > "$SANDBOX/projects/shop.suite"
  local m
  for m in shop-api shop-admin shop-site; do
    mkdir -p "$SANDBOX/projects/$m" && touch "$SANDBOX/projects/$m/docker-compose.yml"
  done
  # deploy.sh ปลอม: จดชื่อ + argument · FAIL_ON=<ชื่อ> → ล้มที่ตัวนั้น
  cat > "$SANDBOX/scripts/deploy.sh" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$DEPLOY_LOG"
[ "\$1" != "\${FAIL_ON:-}" ]
EOF
}

test_deploys_members_in_order_with_args() {
  _suite_setup
  (cd "$SANDBOX" && bash scripts/deploy-suite.sh shop --seed >/dev/null)
  assert_eq "$(cat "$DEPLOY_LOG")" $'shop-api --seed\nshop-admin --seed\nshop-site --seed' "order + args"
}

test_stops_at_first_failure() {
  _suite_setup
  local out rc=0
  out="$(cd "$SANDBOX" && FAIL_ON=shop-admin bash scripts/deploy-suite.sh shop 2>&1)" || rc=$?
  [ "$rc" != 0 ] || { echo "    ✗ should fail"; return 1; }
  assert_eq "$(cat "$DEPLOY_LOG")" $'shop-api\nshop-admin' "shop-site not deployed"
  assert_contains "$out" "shop-site" "tells which members were not deployed"
}

test_infra_deploy_dispatches_suite() {
  _suite_setup
  (cd "$SANDBOX" && bash scripts/infra deploy shop >/dev/null 2>&1) || true
  assert_eq "$(head -1 "$DEPLOY_LOG" 2>/dev/null)" shop-api "infra deploy <suite> → deploy-suite"
}

test_infra_deploy_project_unchanged() {
  _suite_setup
  (cd "$SANDBOX" && bash scripts/infra deploy shop-admin >/dev/null 2>&1) || true
  assert_eq "$(cat "$DEPLOY_LOG" 2>/dev/null)" shop-admin "infra deploy <project> → deploy.sh"
}
