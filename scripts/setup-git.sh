#!/usr/bin/env bash
# เชื่อม project กับ GitHub → src/ เป็น git clone → auto-deploy ทำงานได้ (docs/19-cicd.md)
# ใช้: ./scripts/setup-git.sh <project> <owner/repo> [branch]      (branch default: main)
#      ./scripts/setup-git.sh <project>                            (clone เข้า src/ เองแล้ว)
# เช่น: ./scripts/setup-git.sh lunara korwlik23/lunara
#
# repo public  → clone ผ่าน https เลย ไม่ต้องมี key
# repo private → สร้าง deploy key (อ่านอย่างเดียว) ~/.ssh/deploy_<project> + host alias github.com-<project>
#                แล้วโชว์ public key ให้ไปกด Add ใน GitHub → รันคำสั่งเดิมซ้ำเพื่อ clone
# clone เองแล้ว (git clone … projects/<project>/src) → ข้ามการ clone ตรวจว่า cron fetch ได้โดยไม่ถามรหัส
# src/ เดิม (ถ้ามี) เก็บไว้ที่ src.prev/ · ไม่ deploy เอง — รัน ./scripts/deploy.sh <project> ต่อ
# รันซ้ำได้ — ขั้นที่ทำแล้วจะถูกข้าม
set -euo pipefail
cd "$(dirname "$0")/.."

USAGE="usage: setup-git.sh <project> <owner/repo> [branch]"
NAME="${1:?$USAGE}"
REPO="${2:-}"
BRANCH="${3:-main}"
DIR="projects/$NAME"
[ -f "$DIR/docker-compose.yml" ] || { echo "ERROR: $DIR ยังไม่มี — สร้างก่อน: ./scripts/create-project.sh $NAME <template>" >&2; exit 1; }

# ── 1–2. clone (ข้ามถ้า src/ เป็น git clone อยู่แล้ว) ──
clone_repo() {
  [[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "ERROR: repo ต้องเป็น owner/repo (เช่น korwlik23/lunara) — $USAGE" >&2; exit 1; }
  local url key alias dockerfile
  if GIT_TERMINAL_PROMPT=0 git ls-remote --exit-code --heads "https://github.com/$REPO.git" "$BRANCH" >/dev/null 2>&1; then
    url="https://github.com/$REPO.git"
    echo "✅ $REPO เป็น public — clone ผ่าน https (ไม่ต้องมี deploy key)"
  else
    key="$HOME/.ssh/deploy_$NAME"
    alias="github.com-$NAME"
    url="git@$alias:$REPO.git"
    mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
    [ -f "$key" ] || ssh-keygen -q -t ed25519 -N "" -C "infra-stack deploy $NAME@$(hostname -s)" -f "$key"
    if ! grep -qx "Host $alias" "$HOME/.ssh/config" 2>/dev/null; then
      printf '\nHost %s\n  HostName github.com\n  User git\n  IdentityFile %s\n  IdentitiesOnly yes\n' "$alias" "$key" >> "$HOME/.ssh/config"
      chmod 600 "$HOME/.ssh/config"
    fi
    # host key ของ GitHub จาก api.github.com/meta (ผ่าน HTTPS) — ไม่เชื่อ key ที่ได้จาก ssh ครั้งแรกแบบมั่ว ๆ
    if ! ssh-keygen -F github.com >/dev/null 2>&1; then
      curl -fsS https://api.github.com/meta | grep -oE '"ssh-(ed25519|rsa) [^"]+"|"ecdsa-sha2-nistp256 [^"]+"' \
        | tr -d '"' | sed 's/^/github.com /' >> "$HOME/.ssh/known_hosts"
    fi
    if ! git ls-remote --exit-code --heads "$url" "$BRANCH" >/dev/null 2>&1; then
      echo
      echo "🔑 $REPO เป็น private — เพิ่ม deploy key นี้ใน GitHub (ครั้งเดียว):"
      echo
      echo "   1. เปิด https://github.com/$REPO/settings/keys/new"
      echo "   2. Title: infra-stack $(hostname -s)"
      echo "   3. Key: (copy ทั้งบรรทัดด้านล่าง)"
      echo
      cat "$key.pub"
      echo
      echo "   4. ❌ ไม่ติ๊ก \"Allow write access\" (เซิร์ฟเวอร์อ่านอย่างเดียวพอ) → Add key"
      echo "      GitHub ถามรหัส/2FA → ยืนยันให้จบจนเห็น key ในรายการ (ไม่งั้น key ไม่ถูกบันทึก)"
      echo "   5. รันคำสั่งเดิมอีกครั้ง: ./scripts/setup-git.sh $NAME $REPO $BRANCH"
      echo
      echo "   (ถ้าเพิ่ม key แล้วยังขึ้นข้อความนี้: ชื่อ repo/branch '$BRANCH' ถูกไหม)"
      exit 2
    fi
    echo "✅ deploy key ใช้ได้ ($alias)"
  fi

  rm -rf "$DIR/src.new"
  git clone --quiet --branch "$BRANCH" --single-branch "$url" "$DIR/src.new"
  dockerfile="$(grep -E '^[[:space:]]*dockerfile:' "$DIR/docker-compose.yml" | head -1 | awk '{print $2}' | tr -d '"'"'" || true)"
  if [ ! -f "$DIR/src.new/${dockerfile:-Dockerfile}" ]; then
    rm -rf "$DIR/src.new"
    echo "ERROR: $REPO@$BRANCH ไม่มี ${dockerfile:-Dockerfile} ที่ root — เพิ่มใน repo ก่อน (docs/26 เฟส 0)" >&2
    exit 1
  fi
  if [ -d "$DIR/src" ]; then
    rm -rf "$DIR/src.prev"
    mv "$DIR/src" "$DIR/src.prev"
    echo "ℹ️  src/ เดิมเก็บไว้ที่ $DIR/src.prev/ (ลบได้เมื่อ deploy ผ่านแล้ว)"
  fi
  mv "$DIR/src.new" "$DIR/src"
}

if [ -d "$DIR/src/.git" ]; then
  echo "ℹ️  $DIR/src เป็น git clone อยู่แล้ว ($(git -C "$DIR/src" remote get-url origin | sed -E 's#//[^@/]+@#//***@#')) — ข้ามการ clone"
  # cron ไม่มีคนพิมพ์รหัส — clone ที่ต้องถาม username/token ทุกครั้ง auto-deploy จะ fetch ไม่ได้
  if ! GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="ssh -o BatchMode=yes" timeout 60 git -C "$DIR/src" fetch --quiet; then
    echo "ERROR: git fetch ต้องถามรหัส/ไม่มีสิทธิ์ — auto-deploy (cron) จะดึงโค้ดไม่ได้" >&2
    echo "       แก้: ลบ $DIR/src แล้วรัน ./scripts/setup-git.sh $NAME <owner/repo> (ใช้ deploy key)" >&2
    echo "       หรือ clone ด้วย fine-grained token อ่านอย่างเดียว: git clone https://<token>@github.com/<owner>/<repo>.git" >&2
    exit 1
  fi
  git -C "$DIR/src" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1 \
    || { echo "ERROR: branch ใน src/ ไม่ได้ track remote — git -C $DIR/src branch -u origin/<branch>" >&2; exit 1; }
  echo "✅ fetch ได้โดยไม่ถามรหัส — auto-deploy ใช้ได้ (branch $(git -C "$DIR/src" rev-parse --abbrev-ref '@{u}'))"
else
  clone_repo
fi

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

UPSTREAM="$(git -C "$DIR/src" rev-parse --abbrev-ref '@{u}' 2>/dev/null || echo "origin/$BRANCH")"
echo
echo "✅ $NAME ← ${UPSTREAM} ($(git -C "$DIR/src" log -1 --format='%h %s' | cut -c1-70))"
echo "ต่อไป:"
echo "  ./scripts/deploy.sh $NAME          # deploy ครั้งแรกจาก git (ให้เว็บตรงกับ ${UPSTREAM#origin/})"
echo "  ./scripts/smoke.sh $NAME"
echo "  auto-deploy: push เข้า ${UPSTREAM#origin/} → ขึ้นเองใน 2 นาที (ต้องมี cron — docs/19-cicd.md)"
