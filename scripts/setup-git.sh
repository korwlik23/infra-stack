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
[ -f "$DIR/docker-compose.yml" ] || { echo "ERROR: $DIR ยังไม่มี — สร้างก่อน: infra new $NAME <template>" >&2; exit 1; }

# shellcheck source=scripts/lib/git-clone.sh
. scripts/lib/git-clone.sh

# ── 1–2. clone (ข้ามถ้า src/ เป็น git clone อยู่แล้ว) ──
clone_repo() {
  local dockerfile
  [ -n "$REPO" ] || { echo "ERROR: ต้องระบุ owner/repo — $USAGE" >&2; exit 1; }
  git_resolve_url "$NAME" "$REPO" "$BRANCH" "infra git $NAME $REPO $BRANCH"
  git_clone_to "$GIT_URL" "$BRANCH" "$DIR/src.new"
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
    echo "       แก้: ลบ $DIR/src แล้วรัน infra git $NAME <owner/repo> (ใช้ deploy key)" >&2
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
enable_local_build "$DIR" "$NAME"

UPSTREAM="$(git -C "$DIR/src" rev-parse --abbrev-ref '@{u}' 2>/dev/null || echo "origin/$BRANCH")"
echo
echo "✅ $NAME ← ${UPSTREAM} ($(git -C "$DIR/src" log -1 --format='%h %s' | cut -c1-70))"
echo "ต่อไป:"
echo "  infra deploy $NAME          # deploy ครั้งแรกจาก git (ให้เว็บตรงกับ ${UPSTREAM#origin/})"
echo "  infra check $NAME"
echo "  auto-deploy: push เข้า ${UPSTREAM#origin/} → ขึ้นเองใน 2 นาที (ต้องมี cron — docs/19-cicd.md)"
