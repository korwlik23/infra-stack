# Backup

| Script | ทำอะไร |
|--------|--------|
| `scripts/postgres-backup.sh` | `pg_dumpall` ทุก database → gzip → off-site |
| `scripts/volumes-backup.sh [volume…]` | tar **ทุก** named volume ในเครื่อง (ข้าม `postgres_data`, `docker_*`, `BACKUP_EXCLUDE_VOLUMES`) → off-site |
| `scripts/secrets-backup.sh` | `.env`, projects, `acme.json`, alertmanager token, deploy keys, crontab → **เข้ารหัส gpg** → off-site |
| `scripts/offsite.sh <kind> <file>` | ส่งไฟล์ขึ้น `r2:<bucket>/<host>/<kind>/` + ตรวจขนาด (ใช้โดย 3 ตัวบน) |
| `scripts/postgres-restore.sh [--yes] <file>` | restore PostgreSQL — แยก "already exists" ที่ปกติออก ล้มเมื่อมี error จริง |
| `scripts/volumes-restore.sh [--yes] [--overwrite] <dir> [volume…]` | restore volume จากไฟล์ล่าสุดของแต่ละตัว (ไม่ทับของที่มีข้อมูล) |
| `scripts/secrets-restore.sh [--yes] <file.gpg>` | ถอดรหัส + วาง secrets กลับ (`.env` เดิมเก็บเป็น `.env.before-restore-*`) |

รันทั้งชุด: `./scripts/backup.sh` · กู้ทั้งเครื่องลง VPS ใหม่: `./scripts/restore-server.sh <source>`
— ขั้นตอนเต็มใน [docs/13-backup.md](../docs/13-backup.md)

ไฟล์ backup อยู่ที่ `backup/archives/` — **ไม่ commit เข้า Git** (อยู่ใน .gitignore)

## Cron แนะนำ (บนเซิร์ฟเวอร์)

```cron
0 3 * * * /opt/infra-stack/scripts/backup.sh >> /var/log/infra-backup.log 2>&1
```

## กฎเหล็ก

1. Backup ที่ไม่เคยลอง restore = ไม่มี backup — ซ้อม `restore-server.sh` อย่างน้อยเดือนละครั้ง
2. เก็บ offsite เสมอ (Cloudflare R2) — เครื่องพังต้องกู้ได้
3. จด `BACKUP_ENCRYPTION_PASSWORD` ไว้นอกเครื่อง — ไม่มีรหัสนี้เปิด backup ของ secrets ไม่ได้
4. เช็คขนาดไฟล์ backup ว่าโตตามข้อมูลจริง ไม่ใช่ 0 byte
