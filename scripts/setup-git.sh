#!/usr/bin/env bash
# เชื่อม project กับ GitHub → src/ เป็น git clone → auto-deploy ทำงานได้ (docs/19-cicd.md)
# ใช้: ./scripts/setup-git.sh <project> <owner/repo> [branch]      (branch default: main)
# เช่น: ./scripts/setup-git.sh lunara korwlik23/lunara
#
# repo public  → clone ผ่าน https เลย ไม่ต้องมี key
# repo private → สร้าง deploy key (อ่านอย่างเดียว) ~/.ssh/deploy_<project> + host alias github.com-<project>
#                แล้วโชว์ public key ให้ไปกด Add ใน GitHub → รันคำสั่งเดิมซ้ำเพื่อ clone
# src/ เดิม (ถ้ามี) เก็บไว้ที่ src.prev/ · ไม่ deploy เอง — รัน ./scripts/deploy.sh <project> ต่อ
# รันซ้ำได้ — ขั้นที่ทำแล้วจะถูกข้าม
set -euo pipefail
cd "$(dirname "$0")/.."

USAGE="usage: setup-git.sh <project> <owner/repo> [branch]"
NAME="${1:?$USAGE}"
REPO="${2:?$USAGE}"
BRANCH="${3:-main}"
DIR="projects/$NAME"
[[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "ERROR: repo ต้องเป็น owner/repo (เช่น korwlik23/lunara)" >&2; exit 1; }
[ -f "$DIR/docker-compose.yml" ] || { echo "ERROR: $DIR ยังไม่มี — สร้างก่อน: ./scripts/create-project.sh $NAME <template>" >&2; exit 1; }

if [ -d "$DIR/src/.git" ]; then
  echo "ℹ️  $DIR/src เป็น git clone อยู่แล้ว: $(git -C "$DIR/src" remote get-url origin) ($(git -C "$DIR/src" rev-parse --abbrev-ref HEAD))"
  exit 0
fi

# ── 1. หาวิธีเข้าถึง repo ──
if GIT_TERMINAL_PROMPT=0 git ls-remote --exit-code --heads "https://github.com/$REPO.git" "$BRANCH" >/dev/null 2>&1; then
  URL="https://github.com/$REPO.git"
  echo "✅ $REPO เป็น public — clone ผ่าน https (ไม่ต้องมี deploy key)"
else
  KEY="$HOME/.ssh/deploy_$NAME"
  ALIAS="github.com-$NAME"
  URL="git@$ALIAS:$REPO.git"
  mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
  [ -f "$KEY" ] || ssh-keygen -q -t ed25519 -N "" -C "infra-stack deploy $NAME@$(hostname -s)" -f "$KEY"
  if ! grep -qx "Host $ALIAS" "$HOME/.ssh/config" 2>/dev/null; then
    printf '\nHost %s\n  HostName github.com\n  User git\n  IdentityFile %s\n  IdentitiesOnly yes\n' "$ALIAS" "$KEY" >> "$HOME/.ssh/config"
    chmod 600 "$HOME/.ssh/config"
  fi
  # host key ของ GitHub จาก api.github.com/meta (ผ่าน HTTPS) — ไม่เชื่อ key ที่ได้จาก ssh ครั้งแรกแบบมั่ว ๆ
  if ! ssh-keygen -F github.com >/dev/null 2>&1; then
    curl -fsS https://api.github.com/meta | grep -oE '"ssh-(ed25519|rsa) [^"]+"|"ecdsa-sha2-nistp256 [^"]+"' \
      | tr -d '"' | sed 's/^/github.com /' >> "$HOME/.ssh/known_hosts"
  fi
  if ! git ls-remote --exit-code --heads "$URL" "$BRANCH" >/dev/null 2>&1; then
    echo
    echo "🔑 $REPO เป็น private — เพิ่ม deploy key นี้ใน GitHub (ครั้งเดียว):"
    echo
    echo "   1. เปิด https://github.com/$REPO/settings/keys/new"
    echo "   2. Title: infra-stack $(hostname -s)"
    echo "   3. Key: (copy ทั้งบรรทัดด้านล่าง)"
    echo
    cat "$KEY.pub"
    echo
    echo "   4. ❌ ไม่ติ๊ก \"Allow write access\" (เซิร์ฟเวอร์อ่านอย่างเดียวพอ) → Add key"
    echo "   5. รันคำสั่งเดิมอีกครั้ง: ./scripts/setup-git.sh $NAME $REPO $BRANCH"
    echo
    echo "   (ถ้าเพิ่ม key แล้วยังขึ้นข้อความนี้: ชื่อ repo/branch '$BRANCH' ถูกไหม)"
    exit 2
  fi
  echo "✅ deploy key ใช้ได้ ($ALIAS)"
fi

# ── 2. clone → ตรวจ Dockerfile → สลับเข้า src/ ──
rm -rf "$DIR/src.new"
git clone --quiet --branch "$BRANCH" --single-branch "$URL" "$DIR/src.new"
DOCKERFILE="$(grep -E '^[[:space:]]*dockerfile:' "$DIR/docker-compose.yml" | head -1 | awk '{print $2}' | tr -d '"'"'" || true)"
if [ ! -f "$DIR/src.new/${DOCKERFILE:-Dockerfile}" ]; then
  rm -rf "$DIR/src.new"
  echo "ERROR: $REPO@$BRANCH ไม่มี ${DOCKERFILE:-Dockerfile} ที่ root — เพิ่มใน repo ก่อน (docs/26 เฟส 0)" >&2
  exit 1
fi
if [ -d "$DIR/src" ]; then
  rm -rf "$DIR/src.prev"
  mv "$DIR/src" "$DIR/src.prev"
  echo "ℹ️  src/ เดิมเก็บไว้ที่ $DIR/src.prev/ (ลบได้เมื่อ deploy ผ่านแล้ว)"
fi
mv "$DIR/src.new" "$DIR/src"

# ── 3. เปิดโหมด build บนเครื่อง (template มี "# build: ./src" เตรียมไว้) ──
if ! grep -qE '^[[:space:]]*build:' "$DIR/docker-compose.yml"; then
  sed -i -E '0,/^([[:space:]]*)# build: \.\/src/s//\1build: .\/src/' "$DIR/docker-compose.yml"
  grep -qE '^[[:space:]]*build:' "$DIR/docker-compose.yml" \
    && echo "✅ เปิด build: ./src ใน docker-compose.yml" \
    || echo "⚠️  ไม่เจอบรรทัด '# build: ./src' — เพิ่ม build: ./src ใต้ service ของ app เอง"
fi
# APP_IMAGE ยังเป็น placeholder ghcr.io/<github-user>/… → build ล้ม "invalid reference format"
if grep -qE '^APP_IMAGE=.*[<>]' "$DIR/.env"; then
  sed -i "s|^APP_IMAGE=.*|APP_IMAGE=$NAME:latest|" "$DIR/.env"
  echo "✅ APP_IMAGE=$NAME:latest (build บนเครื่อง ไม่ใช้ registry)"
fi

echo
echo "✅ $NAME ← $REPO@$BRANCH ($(git -C "$DIR/src" log -1 --format='%h %s' | cut -c1-70))"
echo "ต่อไป:"
echo "  ./scripts/deploy.sh $NAME          # deploy ครั้งแรกจาก git (ให้เว็บตรงกับ $BRANCH)"
echo "  ./scripts/smoke.sh $NAME"
echo "  auto-deploy: push เข้า $BRANCH → ขึ้นเองใน 2 นาที (ต้องมี cron — docs/19-cicd.md)"
