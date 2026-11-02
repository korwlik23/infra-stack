#!/usr/bin/env bash
# แทน projects/<name>/src/ ด้วยโค้ดจาก tarball (สำหรับ project ที่ src/ ไม่ใช่ git clone)
# ของเดิมเก็บไว้ที่ src.prev/ — ยังไม่ build/deploy (รัน deploy.sh ต่อเอง)
#
# ใช้: ./scripts/load-src.sh <project> <file.tar.gz>
# ทำ tarball บนเครื่อง dev:  git archive --format=tar.gz -o app.tar.gz HEAD   (เฉพาะไฟล์ที่ commit แล้ว)
# แล้ว: scp app.tar.gz deploy@<vps>:/tmp/ → ./scripts/load-src.sh <project> /tmp/app.tar.gz
#       → ./scripts/deploy.sh <project>
# ย้อนโค้ด: mv src src.bad && mv src.prev src (หรือ ./scripts/rollback.sh <project> previous สำหรับ image)
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="${1:?usage: load-src.sh <project> <file.tar.gz>}"
TAR="${2:?usage: load-src.sh <project> <file.tar.gz>}"
DIR="projects/$NAME"
[ -f "$DIR/docker-compose.yml" ] || { echo "ERROR: $DIR not found" >&2; exit 1; }
[ -f "$TAR" ] || { echo "ERROR: $TAR not found" >&2; exit 1; }
if [ -d "$DIR/src/.git" ]; then
  echo "ERROR: $DIR/src เป็น git clone — ใช้ infra deploy $NAME (git pull) แทน" >&2
  exit 1
fi

rm -rf "$DIR/src.new"
mkdir "$DIR/src.new"
tar -xzf "$TAR" -C "$DIR/src.new"
# กัน tarball ผิดตัว: ต้องมี Dockerfile ที่ compose ใช้ build
DOCKERFILE="$(grep -E '^[[:space:]]*dockerfile:' "$DIR/docker-compose.yml" | head -1 | awk '{print $2}' | tr -d '"'"'" || true)"
if [ ! -f "$DIR/src.new/${DOCKERFILE:-Dockerfile}" ]; then
  rm -rf "$DIR/src.new"
  echo "ERROR: tarball ไม่มี ${DOCKERFILE:-Dockerfile} ที่ root — ทำจาก root ของ repo หรือยัง?" >&2
  exit 1
fi

rm -rf "$DIR/src.prev"
[ -d "$DIR/src" ] && mv "$DIR/src" "$DIR/src.prev"
mv "$DIR/src.new" "$DIR/src"
echo "✅ [load-src:$NAME] src/ ← $(basename "$TAR") (ของเดิมอยู่ที่ src.prev/)"
echo "   ต่อไป: infra deploy $NAME && infra check $NAME"
