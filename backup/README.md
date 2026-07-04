# Backup

| Script | ทำอะไร |
|--------|--------|
| `scripts/postgres-backup.sh` | `pg_dumpall` ทุก database → gzip → เก็บ 7 วัน (+sync R2 ถ้าตั้ง rclone) |
| `scripts/postgres-restore.sh <file>` | restore จากไฟล์ backup (มี confirmation gate) |
| `scripts/volumes-backup.sh` | tar Docker volumes (portainer, grafana, uptime-kuma, redis) |

ไฟล์ backup อยู่ที่ `backup/archives/` — **ไม่ commit เข้า Git** (อยู่ใน .gitignore)

## Cron แนะนำ (บนเซิร์ฟเวอร์)

```cron
0 3 * * * /opt/infra-stack/backup/scripts/postgres-backup.sh >> /var/log/infra-backup.log 2>&1
30 3 * * 0 /opt/infra-stack/backup/scripts/volumes-backup.sh >> /var/log/infra-backup.log 2>&1
```

## กฎเหล็ก

1. Backup ที่ไม่เคยลอง restore = ไม่มี backup — ซ้อม restore อย่างน้อยเดือนละครั้ง
2. เก็บ offsite เสมอ (Cloudflare R2) — เครื่องพังต้องกู้ได้
3. เช็คขนาดไฟล์ backup ว่าโตตามข้อมูลจริง ไม่ใช่ 0 byte
