# Alertmanager

รับ alert จาก Prometheus (rules ใน `monitoring/alerts/`) แล้วส่งเข้า **Telegram**
— CPU>90%, RAM>90%, Disk>85%, core container down

## ตั้งค่า Telegram

1. คุย `@BotFather` → `/newbot` → ได้ bot token
2. ทักหา bot 1 ข้อความ แล้วเปิด `https://api.telegram.org/bot<token>/getUpdates` → เอา `chat.id`
3. **บนเซิร์ฟเวอร์**: แก้ `alertmanager.yml` ใส่ token + chat_id
   ⚠️ ห้าม commit token กลับเข้า Git (`git update-index --skip-worktree services/alertmanager/alertmanager.yml` กันพลาดได้)

## Start / Test

```bash
docker compose --env-file ../../.env up -d
# ยิง alert ทดสอบ:
docker exec alertmanager wget -qO- --post-data='[{"labels":{"alertname":"TestAlert","severity":"info"}}]' \
  --header='Content-Type: application/json' http://localhost:9093/api/v2/alerts
# → ต้องมีข้อความเข้า Telegram ภายใน ~30 วินาที
```
