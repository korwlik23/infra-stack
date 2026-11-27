# shellcheck shell=bash
# clone repo ของ project เข้า projects/<name>/src — ใช้โดย scripts/setup-git.sh และ scripts/create-project.sh
#
# git_resolve_url <name> <owner/repo> <branch> <retry-cmd>
#   ตั้ง GIT_URL: repo public → https · private → deploy key (อ่านอย่างเดียว) ~/.ssh/deploy_<name>
#   + host alias github.com-<name> · key ยังไม่ได้เพิ่มใน GitHub → โชว์วิธีเพิ่มแล้ว exit 2
#   (<retry-cmd> = คำสั่งที่ให้ผู้ใช้รันซ้ำหลังเพิ่ม key)
# git_clone_to <url> <branch> <dest>   clone แบบ branch เดียว (dest ต้องยังไม่มี)
# enable_local_build <dir> <name>      เปิด "# build: ./src" ใน compose + APP_IMAGE=<name>:latest ถ้ายังเป็น placeholder
#
# INFRA_REPO_BASE_URL (default https://github.com) — mirror / GitHub Enterprise / test (file://…)

git_resolve_url() {
  local name="$1" repo="$2" branch="$3" retry="$4" base key alias
  base="${INFRA_REPO_BASE_URL:-https://github.com}"
  [[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] \
    || { echo "ERROR: repo ต้องเป็น owner/repo (เช่น korwlik23/lunara) — ได้ '$repo'" >&2; exit 1; }
  if GIT_TERMINAL_PROMPT=0 git ls-remote --exit-code --heads "$base/$repo.git" "$branch" >/dev/null 2>&1; then
    GIT_URL="$base/$repo.git"
    echo "✅ $repo เป็น public — clone ผ่าน https (ไม่ต้องมี deploy key)"
    return 0
  fi
  if [ "$base" != https://github.com ]; then
    echo "ERROR: clone $base/$repo.git (branch $branch) ไม่ได้" >&2; exit 1
  fi

  key="$HOME/.ssh/deploy_$name"
  alias="github.com-$name"
  GIT_URL="git@$alias:$repo.git"
  mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
  [ -f "$key" ] || ssh-keygen -q -t ed25519 -N "" -C "infra-stack deploy $name@$(hostname -s)" -f "$key"
  if ! grep -qx "Host $alias" "$HOME/.ssh/config" 2>/dev/null; then
    printf '\nHost %s\n  HostName github.com\n  User git\n  IdentityFile %s\n  IdentitiesOnly yes\n' "$alias" "$key" >> "$HOME/.ssh/config"
    chmod 600 "$HOME/.ssh/config"
  fi
  # host key ของ GitHub จาก api.github.com/meta (ผ่าน HTTPS) — ไม่เชื่อ key ที่ได้จาก ssh ครั้งแรกแบบมั่ว ๆ
  if ! ssh-keygen -F github.com >/dev/null 2>&1; then
    curl -fsS https://api.github.com/meta | grep -oE '"ssh-(ed25519|rsa) [^"]+"|"ecdsa-sha2-nistp256 [^"]+"' \
      | tr -d '"' | sed 's/^/github.com /' >> "$HOME/.ssh/known_hosts"
  fi
  if ! git ls-remote --exit-code --heads "$GIT_URL" "$branch" >/dev/null 2>&1; then
    echo
    echo "🔑 $repo เป็น private — เพิ่ม deploy key นี้ใน GitHub (ครั้งเดียว):"
    echo
    echo "   1. เปิด https://github.com/$repo/settings/keys/new"
    echo "   2. Title: infra-stack $(hostname -s)"
    echo "   3. Key: (copy ทั้งบรรทัดด้านล่าง)"
    echo
    cat "$key.pub"
    echo
    echo "   4. ❌ ไม่ติ๊ก \"Allow write access\" (เซิร์ฟเวอร์อ่านอย่างเดียวพอ) → Add key"
    echo "      GitHub ถามรหัส/2FA → ยืนยันให้จบจนเห็น key ในรายการ (ไม่งั้น key ไม่ถูกบันทึก)"
    echo "   5. รันคำสั่งเดิมอีกครั้ง: $retry"
    echo
    echo "   (ถ้าเพิ่ม key แล้วยังขึ้นข้อความนี้: ชื่อ repo/branch '$branch' ถูกไหม)"
    exit 2
  fi
  echo "✅ deploy key ใช้ได้ ($alias)"
}

git_clone_to() {
  local url="$1" branch="$2" dest="$3"
  rm -rf "$dest"
  git clone --quiet --branch "$branch" --single-branch "$url" "$dest"
}

enable_local_build() {
  local dir="$1" name="$2"
  if ! grep -qE '^[[:space:]]*build:' "$dir/docker-compose.yml"; then
    sed -i -E '0,/^([[:space:]]*)# build: \.\/src/s//\1build: .\/src/' "$dir/docker-compose.yml"
    grep -qE '^[[:space:]]*build:' "$dir/docker-compose.yml" \
      && echo "✅ เปิด build: ./src ใน docker-compose.yml" \
      || echo "⚠️  ไม่เจอบรรทัด '# build: ./src' — เพิ่ม build: ./src ใต้ service ของ app เอง"
  fi
  # APP_IMAGE ยังเป็น placeholder ghcr.io/<github-user>/… → build ล้ม "invalid reference format"
  if grep -qE '^APP_IMAGE=.*[<>]' "$dir/.env"; then
    sed -i "s|^APP_IMAGE=.*|APP_IMAGE=$name:latest|" "$dir/.env"
    echo "✅ APP_IMAGE=$name:latest (build บนเครื่อง ไม่ใช้ registry)"
  fi
}
