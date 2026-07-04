# 13 — Backup

🎯 เครื่องพังทั้งเครื่อง → เครื่องใหม่ + restore = กลับมาได้

## สิ่งที่ backup

| อะไร | Script | ความถี่ |
|------|--------|---------|
| PostgreSQL (ทุก db) | `backup/scripts/postgres-backup.sh` | ทุกวัน 03:00 |
| Docker volumes (portainer, grafana, uptime-kuma, redis) | `backup/scripts/volumes-backup.sh` | ทุกอาทิตย์ |
| Repo นี้ (config ทั้งหมด) | Git push | ทุกครั้งที่แก้ |
| ไฟล์ media | อยู่บน R2 อยู่แล้ว | — |

## ⚙️ ตั้ง cron

```bash
crontab -e
```

```cron
0 3 * * *  /opt/infra-stack/backup/scripts/postgres-backup.sh >> /var/log/infra-backup.log 2>&1
30 3 * * 0 /opt/infra-stack/backup/scripts/volumes-backup.sh  >> /var/log/infra-backup.log 2>&1
```

Offsite: ตั้ง rclone remote `r2` ([12-r2.md](12-r2.md)) → postgres backup sync ขึ้น R2 เอง

## 🔄 Restore

```bash
./scripts/restore.sh                          # ใช้ backup ล่าสุด (มี confirmation)
./scripts/restore.sh backup/archives/postgres/all_20260704_030000.sql.gz
```

## กฎเหล็ก

1. **Backup ที่ไม่เคยซ้อม restore = ไม่มี backup** — ซ้อมเดือนละครั้ง
2. เช็ค log + ขนาดไฟล์ว่าไม่เป็น 0 byte (`ls -lh backup/archives/postgres/`)
3. Disaster drill: VPS ใหม่ → `install.sh` → restore → app ขึ้น — จับเวลาไว้
