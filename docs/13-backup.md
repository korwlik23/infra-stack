# 13 — Backup

🎯 เครื่องพังทั้งเครื่อง → เช่าเครื่องใหม่ + `restore-server.sh` = กลับมาได้ครบทั้งข้อมูลและรหัสผ่าน

## สิ่งที่ backup (`./scripts/backup.sh` ทำครบทุกข้อ)

| อะไร | Script | ไฟล์ |
|------|--------|------|
| PostgreSQL ทุก database | `backup/scripts/postgres-backup.sh` | `postgres/all_<stamp>.sql.gz` |
| **ทุก** Docker named volume ในเครื่อง (รวม volume ของ project เช่น n8n) | `backup/scripts/volumes-backup.sh` | `volumes/<volume>_<stamp>.tar.gz` |
| Secrets + config เฉพาะเครื่อง — **เข้ารหัส** | `backup/scripts/secrets-backup.sh` | `secrets/secrets_<stamp>.tar.gz.gpg` |
| โค้ด + config กลาง | Git (repo นี้) | — |

ไฟล์อยู่ที่ `backup/archives/` (ไม่อยู่ใน Git) และส่งขึ้น R2 ทุกไฟล์ถ้าตั้ง rclone แล้ว

**volume ที่ไม่ backup:** `postgres_data` (ใช้ `pg_dumpall` แทน — copy ไฟล์ database ขณะรันได้ไฟล์เสีย),
ชื่อเก่า `docker_*` ที่เหลือจาก `migrate-volumes.sh`, volume ไม่มีชื่อ และ `BACKUP_EXCLUDE_VOLUMES`
ใน `.env` (default: `netdata_cache prometheus_data loki_data promtail_positions` — ประวัติ metrics/log
ที่ใหญ่และสร้างใหม่ได้ ถ้าต้องการเก็บด้วย เอาชื่อออกจากรายการ)

**secrets ที่เก็บ:** `.env`, `projects/<name>/` (ยกเว้น `src/` `data/`), `services/traefik/acme.json`
(cert เดิม — เครื่องใหม่เปิด HTTPS ได้ก่อนย้าย DNS), `services/alertmanager/alertmanager.yml`
(Telegram token), `~/.ssh/config` + `~/.ssh/deploy_*` (deploy key — docs/19) และ crontab

## 🔐 รหัสเข้ารหัส — สำคัญที่สุดในบทนี้

secrets ถูกเข้ารหัส (gpg AES256) ด้วย `BACKUP_ENCRYPTION_PASSWORD` ใน `.env` ที่ `install.sh` สุ่มให้

```bash
grep BACKUP_ENCRYPTION_PASSWORD .env     # จดค่านี้เก็บใน password manager ตอนนี้เลย
```

⚠️ รหัสนี้อยู่ในเครื่องเท่านั้น — **เครื่องพังแล้วไม่ได้จดไว้ = เปิด backup ของ `.env` / รหัสผ่าน
ทั้งหมดไม่ได้** (ข้อมูลใน database/volume ยังกู้ได้ แต่ต้องตั้งรหัสทุกตัวใหม่เอง)

## ⚙️ ตั้ง off-site (R2)

ทำตาม [12-r2.md](12-r2.md) ให้มี rclone remote ชื่อ `r2` และตั้ง `R2_BUCKET_BACKUP` ใน `.env`
ไฟล์จะไปอยู่ที่ `r2:<bucket>/<BACKUP_HOST>/{postgres,volumes,secrets}/` (`BACKUP_HOST` ว่าง = hostname
— แยกโฟลเดอร์ต่อเครื่องเมื่อมีหลาย VPS) ทุกไฟล์ถูกตรวจขนาดหลัง upload

ยังไม่ตั้ง → log จะขึ้น `⚠️ … backup อยู่แค่ในเครื่องนี้` ทุกครั้ง (เครื่องพัง = backup หายไปด้วย)

script ลบไฟล์เก่าเฉพาะในเครื่อง (`BACKUP_KEEP_DAYS`) — ฝั่ง R2 ตั้ง **Object lifecycle rule** ใน
Cloudflare Dashboard → R2 → bucket → Settings (เช่น ลบไฟล์อายุเกิน 30 วัน)

## ⚙️ ตั้ง cron

⚠️ **ต้องสร้างไฟล์ log ก่อน** — user `deploy` เขียนไฟล์ใหม่ใน `/var/log` เองไม่ได้
(เจอจริง: cron ล้มเงียบ ๆ ทุกคืนโดยไม่มีใครรู้):

```bash
sudo touch /var/log/infra-backup.log /var/log/infra-deploy.log
sudo chown deploy:deploy /var/log/infra-backup.log /var/log/infra-deploy.log
```

```bash
crontab -e
```

```cron
0 3 * * *  /opt/infra-stack/scripts/backup.sh >> /var/log/infra-backup.log 2>&1
```

`backup.sh` รันทั้ง 3 ส่วนต่อกันแม้ส่วนแรกล้ม แล้วจบด้วย `❌ backup ไม่สำเร็จ: …` ถ้ามีส่วนไหนพัง
เช็คทุกเช้าวันจันทร์: `tail -20 /var/log/infra-backup.log`

## 🔄 กู้ทั้งเครื่องลง VPS ใหม่ (เครื่องพัง / ย้ายเครื่อง)

```bash
# บนเครื่องใหม่ — เหมือนติดตั้งปกติ (README Quick Start ข้อ 0–1) จนมี Docker
git clone https://github.com/korwlik23/infra-stack.git /opt/infra-stack && cd /opt/infra-stack
sudo ./scripts/harden.sh                  # (root) ตั้ง passwd deploy + chown แล้ว login ใหม่เป็น deploy
./install.sh                              # ติด Docker → login ใหม่ → รันซ้ำจนบอกให้แก้ .env (ไม่ต้องแก้)

# ตั้ง rclone remote "r2" ด้วย R2 key ที่จดไว้ (docs/12) แล้ว:
./scripts/restore-server.sh r2:<bucket>/<host-เครื่องเดิม>
#   หรือ copy โฟลเดอร์ backup/archives จากเครื่องเดิมมาเอง แล้ว: ./scripts/restore-server.sh <โฟลเดอร์>
```

script จะถาม `BACKUP_ENCRYPTION_PASSWORD` แล้วทำให้เอง: secrets → volumes → core → database +
PostgreSQL → stack อื่นที่เครื่องเดิมเปิดไว้ (monitoring / tools / messaging / storage) จากนั้นบอก
ขั้นที่เหลือ:

1. deploy แต่ละ project (`./scripts/deploy.sh <name>` — project แบบ build บนเครื่องต้อง clone `src/` ใหม่)
2. ทดสอบเครื่องใหม่**โดยยังไม่ย้าย DNS** (cert เดิมใช้ได้เลย):
   `curl -I --resolve portainer.<BASE_DOMAIN>:443:<IP-ใหม่> https://portainer.<BASE_DOMAIN>`
3. ผ่านแล้วค่อยแก้ A record ใน Cloudflare เป็น IP ใหม่ — เครื่องเดิมเปิดไว้จนแน่ใจ
4. ย้ายภายในไม่กี่วัน: Traefik ต่ออายุ cert ได้เมื่อ DNS ชี้มาเครื่องใหม่แล้ว

script ไม่เขียนทับ volume ที่มีข้อมูลอยู่แล้ว และยืนยันก่อนเริ่มเสมอ — ใช้กับเครื่องใหม่เท่านั้น

## 🔄 Restore บางส่วน (เครื่องเดิม)

```bash
./scripts/restore.sh                      # PostgreSQL จาก backup ล่าสุด (มี confirmation)
./backup/scripts/volumes-restore.sh backup/archives/volumes grafana_data      # volume เดียว
#   volume มีข้อมูลอยู่แล้ว → ข้าม; ทับจริง: stop container ที่ใช้ก่อน แล้วเติม --overwrite
./backup/scripts/secrets-restore.sh backup/archives/secrets/secrets_<stamp>.tar.gz.gpg
```

## กฎเหล็ก

1. **Backup ที่ไม่เคยซ้อม restore = ไม่มี backup** — ซ้อม `restore-server.sh` ลง VPS ทดลองเดือนละครั้ง
2. เช็ค log + ขนาดไฟล์ว่าไม่เป็น 0 byte (`ls -lh backup/archives/*/`)
3. จด `BACKUP_ENCRYPTION_PASSWORD` และ R2 key ไว้นอกเครื่อง — สองอย่างนี้คือกุญแจกู้เครื่อง

## ⚠️ ข้อจำกัดที่ควรรู้

- volume ถูก copy **ขณะ service รันอยู่** (ไม่หยุดเว็บ) — ไฟล์ที่ถูกเขียนพอดีตอน 03:00 อาจไม่สมบูรณ์
  (เช่น SQLite ของ Grafana / Uptime Kuma) ข้อมูลหลักของ app อยู่ใน PostgreSQL ซึ่ง `pg_dumpall` สม่ำเสมอเสมอ
- `src/` ของ project ไม่อยู่ใน backup — อยู่ใน Git ของ app อยู่แล้ว (clone ใหม่ด้วย deploy key ที่ถูก restore)

## 🩹 สิ่งที่เห็นตอน restore PostgreSQL (ปกติ ไม่ใช่ error จริง)

`pg_dumpall` สร้าง role/database ทุกตัวใหม่ — ตัวที่มีอยู่แล้ว (superuser จาก `.env`, database จาก
init SQL) จะได้ `already exists` ซึ่ง script นับแยกให้:

```text
[postgres-restore] ข้าม 3 รายการ "already exists" (ปกติ)
[postgres-restore] ✅ done.
```

ถ้ามี error อื่น script จะแสดงรายการและจบด้วย exit 1 — log เต็มอยู่ข้างไฟล์ backup (`restore_<stamp>.log`)
restore ทับ database ที่มีข้อมูลอยู่แล้วจะได้ `duplicate key` — restore ลง postgres ที่ยังว่างเท่านั้น
