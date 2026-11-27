# shellcheck shell=bash
# clone repo ของ project (scripts/lib/git-clone.sh ผ่าน setup-git.sh)
# repo ปลอมเป็น bare repo ในเครื่อง — INFRA_REPO_BASE_URL ชี้ไปที่โฟลเดอร์ของมัน

# mk_fake_repo <owner/repo> [deploy-template-dir] → bare repo ที่ $REPOS/<owner>/<repo>.git
# มี Dockerfile เสมอ · ถ้าให้ dir มา คัดลอกเข้า deploy/infra-stack/
mk_fake_repo() {
  local repo="$1" tpl="${2:-}" work
  REPOS="${REPOS:-$SANDBOX/repos}"
  work="$(mktemp -d)"
  git -C "$work" init -q -b main
  printf 'FROM alpine\n' > "$work/Dockerfile"
  if [ -n "$tpl" ]; then
    mkdir -p "$work/deploy/infra-stack"
    cp -r "$tpl/." "$work/deploy/infra-stack/"
  fi
  git -C "$work" add -A
  git -C "$work" -c user.email=t@t -c user.name=t commit -q -m init
  mkdir -p "$REPOS/${repo%/*}"
  git clone -q --bare "$work" "$REPOS/$repo.git"
  rm -rf "$work"
  export INFRA_REPO_BASE_URL="file://$REPOS"
}

test_setup_git_clones_from_base_url() {
  mk_sandbox
  (cd "$SANDBOX" && bash scripts/create-project.sh blog go >/dev/null 2>&1)
  mk_fake_repo acme/blog
  (cd "$SANDBOX" && bash scripts/setup-git.sh blog acme/blog >/dev/null)
  [ -f "$SANDBOX/projects/blog/src/Dockerfile" ] || { echo "    ✗ src/Dockerfile missing"; return 1; }
  assert_eq "$(git -C "$SANDBOX/projects/blog/src" rev-parse --abbrev-ref '@{u}')" origin/main "tracks origin/main"
  command grep -qE '^[[:space:]]*build: \./src' "$SANDBOX/projects/blog/docker-compose.yml" \
    || { echo "    ✗ build: ./src not enabled"; return 1; }
}

test_setup_git_still_requires_project() {
  mk_sandbox
  local out
  out="$(cd "$SANDBOX" && bash scripts/setup-git.sh nope acme/x 2>&1 || true)"
  assert_contains "$out" "infra new nope" "tells user to create the project first"
}

test_setup_git_rejects_repo_without_dockerfile() {
  mk_sandbox
  (cd "$SANDBOX" && bash scripts/create-project.sh blog go >/dev/null 2>&1)
  mk_fake_repo acme/blog
  # ลบ Dockerfile ออกจาก repo
  local work; work="$(mktemp -d)"
  git clone -q "$REPOS/acme/blog.git" "$work"
  git -C "$work" rm -q Dockerfile && printf 'x\n' > "$work/README" && git -C "$work" add README
  git -C "$work" -c user.email=t@t -c user.name=t commit -q -m nodocker && git -C "$work" push -q origin main
  rm -rf "$work"
  local out
  out="$(cd "$SANDBOX" && bash scripts/setup-git.sh blog acme/blog 2>&1)" && { echo "    ✗ should fail"; return 1; }
  assert_contains "$out" "ไม่มี Dockerfile" "fails because of the missing Dockerfile"
  [ ! -d "$SANDBOX/projects/blog/src" ] || { echo "    ✗ src/ must not be created"; return 1; }
}
