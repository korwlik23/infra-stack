#!/usr/bin/env bash
# Restore PostgreSQL จากไฟล์ backup (pg_dumpall gzip)
# ใช้: ./postgres-restore.sh [--yes] backup/archives/postgres/all_YYYYMMDD_HHMMSS.sql.gz
#   --yes = ข้ามการพิมพ์ยืนยัน (ใช้โดย scripts/restore-server.sh ที่ยืนยันไปแล้ว)
#
# ได้ผลถูกต้องเมื่อ restore ลง postgres ที่ "ยังว่าง" (เครื่องใหม่ / volume ใหม่)
# ทับ database ที่มีข้อมูลอยู่ → ตารางซ้ำ / duplicate key → script รายงานว่าล้ม
#
# pg_dumpall สร้าง role/database ทุกตัวใหม่ — ตัวที่มีอยู่แล้ว (superuser จาก .env, db จาก
# init SQL) จะได้ "already exists" ซึ่งปกติ (docs/13) script แยก error พวกนี้ออก
# แล้วล้มเฉพาะเมื่อมี error อื่น (เดิมจบด้วย "done" เสมอแม้ข้อมูลเข้าไม่ครบ)
set -euo pipefail

YES=0
if [ "${1:-}" = "--yes" ]; then YES=1; shift; fi
FILE="${1:?usage: postgres-restore.sh [--yes] <backup-file.sql.gz>}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# อ่านค่าจาก .env ทีละ key แทน `source` — source รันไฟล์เป็น bash: รหัสผ่านที่มี
# $ ช่องว่าง & ; ทำ script พัง (set -u → unbound variable) หรือได้ค่าผิด
env_val() { grep -E "^$1=" "$ROOT/.env" 2>/dev/null | head -1 | cut -d= -f2- | sed -E 's/^"(.*)"$/\1/' || true; }
POSTGRES_USER="$(env_val POSTGRES_USER)"

[ -f "$FILE" ] || { echo "ERROR: file not found: $FILE" >&2; exit 1; }
gunzip -t "$FILE" || { echo "ERROR: ไฟล์ backup เสีย (gzip ไม่ผ่าน): $FILE" >&2; exit 1; }

if [ "$YES" -ne 1 ]; then
  echo "⚠️  This will OVERWRITE data in the running postgres container."
  echo "   (ได้ผลถูกต้องเมื่อ postgres ยังว่าง — ทับ database ที่มีข้อมูลจะได้ตารางซ้ำ)"
  read -rp "Type 'restore' to continue: " CONFIRM
  [ "$CONFIRM" = "restore" ] || { echo "aborted"; exit 1; }
fi

LOG="$(dirname "$FILE")/restore_$(date +%Y%m%d_%H%M%S).log"
echo "[postgres-restore] restoring $(basename "$FILE")… (log: $LOG)"
gunzip -c "$FILE" \
  | docker exec -i postgres psql -U "${POSTGRES_USER:-infra}" -d postgres -v ON_ERROR_STOP=0 \
      >/dev/null 2>"$LOG"

EXISTS="$(grep -c 'ERROR:.*already exists' "$LOG" || true)"
REAL="$(grep 'ERROR:' "$LOG" | grep -vc 'already exists' || true)"
[ "$EXISTS" -eq 0 ] || echo "[postgres-restore] ข้าม $EXISTS รายการ \"already exists\" (ปกติ)"
if [ "$REAL" -gt 0 ]; then
  echo "[postgres-restore] ❌ มี error $REAL บรรทัด — ข้อมูลอาจเข้าไม่ครบ:" >&2
  grep 'ERROR:' "$LOG" | grep -v 'already exists' | head -20 >&2
  exit 1
fi
echo "[postgres-restore] ✅ done."
