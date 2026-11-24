# scripts/ — Automation

## ใช้ผ่าน `infra` (แนะนำ)

`harden.sh` ลิงก์ `scripts/infra` ไว้ที่ `/usr/local/bin/infra` และ Tab completion (`infra-completion.bash`
→ `/etc/bash_completion.d/infra`) — พิมพ์ได้จากทุกโฟลเดอร์ ไม่ต้องจำ path · ไม่ใส่ชื่อ project = เลือกจากรายการ
· เครื่องที่ติดตั้งก่อน v2.13: `git pull` แล้ว `infra completion` ครั้งเดียว (ได้ Tab)

| `infra …` | เรียก | หมายเหตุ |
|-----------|-------|----------|
| `list` | — | project ทั้งหมด: โดเมน · container ที่รัน · commit ที่ขึ้นเว็บ / รอตอบ seed / ล้ม |
| `new <ชื่อ> <template> [--mysql\|--external-db]` | `create-project.sh` | |
| `git <p> [owner/repo] [branch]` | `setup-git.sh` | |
| `deploy <p> [--seed\|--no-seed]` | `deploy.sh` | |
| `env <p>` | — | เปิด `$EDITOR` (nano) แก้ `.env` → ถามแล้ว `restart` ให้ |
| `restart <p>` | — | recreate ด้วย `.env` ปัจจุบัน ไม่ build: rollout service หลัก (ไม่ดับ) + `--force-recreate` ตัวที่เหลือ (`docker compose restart` ไม่อ่าน `.env` ใหม่) |
| `rollback <p> [tag]` | `rollback.sh` | tag default `previous` |
| `check <p> [/path…]` | `smoke.sh` | |
| `logs <p\|container\|auto-deploy\|backup\|cleanup\|audit\|refresh\|cve-scan\|install>` | — | `docker compose logs -f` / `docker logs -f` / `tail -f logs/*.log` |
| `artisan <p> <args>` | — | แบบ `artisan.sh` แต่ใช้ `ROLLOUT_SERVICE` · มี project เดียวไม่ต้องใส่ชื่อ (`infra artisan migrate:status`) |
| `shell <p>` | — | bash (หรือ sh) ใน service หลัก |
| `load <p> <tar.gz>` | `load-src.sh` | path อิงโฟลเดอร์ที่พิมพ์ |
| `status` / `secrets` | — | container + DNS + HTTPS / รหัสทั้งหมด (`secrets` แสดงรหัสบนจอ) |
| `audit [--notify]` | `audit.sh` | ตรวจความปลอดภัย อ่านอย่างเดียว · `--notify` = Telegram เมื่อมี ⚠️/❌ (docs/30) |
| `cve [--notify]` | `cve-scan.sh` | สแกน CVE ของ image ที่รันอยู่ (Trivy) เฉพาะที่มีแพตช์ · `--notify` = Telegram เฉพาะของใหม่ (docs/31) |
| `refresh [p…]` | `refresh.sh` | base image มีแพตช์ใหม่ → deploy (docs/31) |
| `db-user <p\|--all>` | `db-user.sh` | ย้าย project จาก superuser ไปใช้ database user ของตัวเอง · `--all` = ทุกตัวที่ยังใช้ superuser + restart ให้ (docs/31) |
| `up <stack> [service…]` / `stop …` | `docker compose -f docker/docker-compose.<stack>.yml` | `up` เช็ค DNS ก่อนถ้า stack มีหน้าเว็บ · `stop` ทั้ง core / database / mysql ถามก่อน |
| `update [stack\|all]` | `update.sh` | |
| `dns [stack\|host…]` | `check-dns.sh` | ไม่ใส่ = ทุก stack ที่เปิด + โดเมนของ project |
| `cron [--yes]` | — | (`install.sh` เรียกให้แล้ว) ตั้ง cron `auto-deploy.sh` (ทุก 2 นาที) + `backup.sh` (03:00) + `cleanup.sh` (04:00) + `refresh.sh` (05:00) + `cve-scan.sh --notify` (06:00) + `audit.sh --notify` (จันทร์ 08:00) ตัวที่ยังขาด |
| `backup` · `restore <postgres\|mysql\|secrets> [ไฟล์]` · `restore volumes [--overwrite] [vol…]` | `backup.sh` · `backup/scripts/*-restore.sh` | ไม่ใส่ไฟล์ = ล่าสุด |
| `restore db <p> [ไฟล์]` | `backup/scripts/project-db-restore.sh` | ย้อน DB ของ project เดียวจาก dump ก่อน migrate (docs/13) |
| `restore-server <src>` | `restore-server.sh` | |
| `psql [db] [args]` · `mysql [db]` · `redis [args]` | `docker exec` | ใช้รหัสใน container ไม่ต้องพิมพ์ |
| `reset-password n8n [p]` · `grafana` | — | n8n: `user-management:reset` (ถาม backup + พิมพ์ยืนยัน) · grafana: ตั้งกลับเป็นค่าใน `.env` |

## Script

| Script | ทำอะไร | ระวัง |
|--------|--------|-------|
| `../prepare.sh` | ช่วง A ของการติดตั้ง (root, `curl … \| bash`): clone → `harden.sh` → สลับเป็น deploy แล้วรัน `install.sh` | — |
| `harden.sh` | user deploy (รหัส sudo, SSH key, group docker) + Docker + UFW + Fail2ban + ล็อก SSH (root, รันซ้ำได้) | ปิด root login เฉพาะเมื่อ deploy มีรหัส sudo แล้ว |
| `check-dns.sh [--wait] <stack\|hostname…>` | เช็คว่า subdomain ของ stack มี DNS record ที่**ชี้มาเครื่องนี้** (อ่านจาก compose จริง) — รันก่อน `up -d`; `--wait` รอจนครบ | ไม่ครบ/ชี้เครื่องอื่น = exit 1; ข้ามได้ด้วย `SKIP_DNS_CHECK=1` |
| `update.sh [stack\|all]` | pull image ใหม่ + up -d ทีละ stack (`all` = core + monitoring + stack อื่นที่เปิดอยู่) | database / mysql ต้อง backup ก่อน (มี gate) |
| `backup.sh` | backup PostgreSQL + ทุก named volume + secrets (เข้ารหัส) → off-site R2 (cron รายวัน) | จด `BACKUP_ENCRYPTION_PASSWORD` ไว้นอกเครื่อง |
| `cleanup.sh` | cron รายวัน: ล้าง build cache ที่ไม่ได้ใช้เกิน 72h (`CLEANUP_CACHE_AGE`) และรวมไม่เกิน 4gb (`CLEANUP_CACHE_MAX`) + image `<none>` + container ที่หยุดค้าง (ไม่ใช่ของ compose) — image `:previous` รอด | ไม่ลบ volume |
| `restore.sh [file]` | restore PostgreSQL (default = ล่าสุด) | เขียนทับข้อมูล — มี confirmation |
| `restore-server.sh <r2:bucket/host \| dir>` | กู้ทั้งเครื่องลง VPS ใหม่: secrets → volumes → core → database → stack ที่มีข้อมูล | เครื่องใหม่เท่านั้น — มี confirmation (docs/13) |
| `refresh.sh [project…]` | cron รายวัน: `docker pull` base image ของ stage ที่รันจริง (อ่าน `ARG` default + `build.target`/`dockerfile` จาก compose) แล้วดูว่า `APP_IMAGE` build บน base นี้ไหม (เทียบ layer) → ไม่ใช่ = `deploy.sh` (PHP/Node/OS ได้แพตช์แม้ไม่มี commit) · ข้าม project ที่ deploy ล้ม/rollback อยู่/มี commit ค้าง | `DEPLOY_REFRESH=0` ปิดต่อ project (docs/31) |
| `cve-scan.sh [--notify]` | สแกน CVE (Trivy, `CRITICAL,HIGH`, เฉพาะที่มีแพตช์) ของทุก image ที่รันอยู่ + บอกวิธีแก้ · จำที่แจ้งแล้วใน `logs/cve-state.txt` | pin `TRIVY_IMAGE` — อ่าน release notes ก่อนอัปเกรด |
| `db-user.sh <project>` | สร้าง Postgres user ของ project + ย้ายเจ้าของ database/ตาราง + แก้ `.env` + ทดสอบ login (รันซ้ำได้) · `create-project.sh` เรียกเอง | container ใช้ user ใหม่หลัง `infra restart` |
| `audit.sh [--notify]` | ตรวจความปลอดภัย 8 หมวด (SSH, firewall, อัปเดต, ไฟล์ลับ, หน้าแอดมิน/cert, container, app, backup) — อ่านอย่างเดียว | exit 1 เมื่อมี ❌ · checklist เต็ม docs/30 |
| `create-project.sh <name> <template> [--mysql\|--external-db]` | สร้าง project จาก template (laravel/nextjs/go/n8n/ai-worker) + database (`--external-db` = database อยู่เครื่องอื่น ไม่สร้างในเครื่อง) | — |
| `setup-git.sh <project> [<owner/repo> [branch]]` | clone เข้า `src/` (repo private → deploy key) + เปิด build → auto-deploy ใช้ได้ · clone เองแล้วใส่แค่ชื่อ project |  private repo: ต้องวาง key ใน GitHub แล้วรันซ้ำ |
| `deploy.sh <project> [--seed\|--no-seed]` | **zero-downtime rolling deploy** (build-on-server หรือ pull) + migrate/seed ทุก stack (`lib/deploy-db.sh`) — ของพังไม่ได้รับ traffic | migration ต้อง expand/contract (docs/25) |
| `smoke.sh <project> [path…]` | smoke test หลัง deploy (อ่านอย่างเดียว): container/healthy, image ค้าง, health 200 ผ่าน Traefik, cert, error ใน log, migration ค้าง | exit 1 เมื่อมี ❌ (docs/28) |
| `load-src.sh <project> <tar.gz>` | แทน `src/` ด้วยโค้ดจาก `git archive` (project ที่ src ไม่ใช่ git clone) — ของเดิมเก็บที่ `src.prev/` | ยังไม่ deploy — รัน `deploy.sh` ต่อ |
| `artisan.sh <project> <args>` | รัน artisan ใน container จากที่ไหนก็ได้ (เช่น `migrate --force`) | — |
| `rollback.sh <project> <tag>` | กลับ image tag เก่า แบบ rolling (`previous` = ก่อน deploy ล่าสุด) — retag ไม่แก้ `.env` | migration ไม่ย้อนเอง (docs/25) |
| `auto-deploy.sh` | cron: poll git ทุก project → deploy เมื่อมี commit ใหม่ (ทีละตัว, ไม่ลอง commit ที่ล้มซ้ำ) · push แก้ seeder → seed เอง · project ใหม่ → พักรอคำตอบเรื่อง seed + แจ้ง Telegram | ดู docs/19-cicd.md |
| `migrate-volumes.sh` | ย้าย volume `docker_<name>` → `<name>` (อัปเกรดเครื่องเก่า ครั้งเดียว) | stop container เดิม — backup ก่อน (docker/README.md) |

ทุก script รันจาก repo root บนเซิร์ฟเวอร์ (แนะนำ clone ไว้ที่ `/opt/infra-stack`)
