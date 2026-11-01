# shellcheck shell=bash
# แจ้งเตือนเข้า Telegram — ใช้กับงานที่ไม่มีคนเฝ้า (auto-deploy รอคำตอบ / deploy ล้ม)
# source แล้วเรียก: notify "<ข้อความ>"   (ต้องตั้ง ROOT = repo root ก่อน source)
#
# ตั้งใน .env กลาง (ไม่ตั้ง = เงียบ ไม่ error):
#   NOTIFY_TELEGRAM_BOT_TOKEN=   token จาก @BotFather (ใช้ bot ตัวเดียวกับ Alertmanager ได้)
#   NOTIFY_TELEGRAM_CHAT_ID=     ตัวเลขจาก https://api.telegram.org/bot<token>/getUpdates

notify() {
  local token chat
  token="$(grep -E '^NOTIFY_TELEGRAM_BOT_TOKEN=' "$ROOT/.env" 2>/dev/null | head -1 | cut -d= -f2- || true)"
  chat="$(grep -E '^NOTIFY_TELEGRAM_CHAT_ID=' "$ROOT/.env" 2>/dev/null | head -1 | cut -d= -f2- || true)"
  [ -n "$token" ] && [ -n "$chat" ] || return 0
  # token ส่งผ่าน config ทาง stdin — ไม่โผล่ใน argument (ps)
  printf 'url = "https://api.telegram.org/bot%s/sendMessage"\n' "$token" \
    | curl -fsS -m 10 -o /dev/null -K - \
        --data-urlencode "chat_id=$chat" --data-urlencode "text=[$(hostname -s)] $1" \
    || echo "[notify] ⚠️ ส่ง Telegram ไม่สำเร็จ" >&2
  return 0
}
