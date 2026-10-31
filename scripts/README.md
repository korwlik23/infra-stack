# scripts/ — Automation

| Script | ทำอะไร | ระวัง |
|--------|--------|-------|
| `../prepare.sh` | ช่วง A ของการติดตั้ง (root, `curl … \| bash`): clone → `harden.sh` → สลับเป็น deploy แล้วรัน `install.sh` | — |
| `harden.sh` | user deploy (รหัส sudo, SSH key, group docker) + Docker + UFW + Fail2ban + ล็อก SSH (root, รันซ้ำได้) | ปิด root login เฉพาะเมื่อ deploy มีรหัส sudo แล้ว |
| `infra status \| secrets` | คำสั่งสั้นหลังติดตั้ง (ลิงก์ที่ `/usr/local/bin/infra`): container + DNS + HTTPS / รหัสทั้งหมด | `secrets` แสดงรหัสบนจอ |
| `check-dns.sh [--wait] <stack\|hostname…>` | เช็คว่า subdomain ของ stack มี DNS record ที่**ชี้มาเครื่องนี้** (อ่านจาก compose จริง) — รันก่อน `up -d`; `--wait` รอจนครบ | ไม่ครบ/ชี้เครื่องอื่น = exit 1; ข้ามได้ด้วย `SKIP_DNS_CHECK=1` |
| `update.sh [stack]` | pull image ใหม่ + up -d ทีละ stack | database ต้อง backup ก่อน (มี gate) |
| `backup.sh` | backup PostgreSQL + ทุก named volume + secrets (เข้ารหัส) → off-site R2 (cron รายวัน) | จด `BACKUP_ENCRYPTION_PASSWORD` ไว้นอกเครื่อง |
| `restore.sh [file]` | restore PostgreSQL (default = ล่าสุด) | เขียนทับข้อมูล — มี confirmation |
| `restore-server.sh <r2:bucket/host \| dir>` | กู้ทั้งเครื่องลง VPS ใหม่: secrets → volumes → core → database → stack ที่มีข้อมูล | เครื่องใหม่เท่านั้น — มี confirmation (docs/13) |
| `create-project.sh <name> <template>` | สร้าง project จาก template (laravel/nextjs/n8n/ai-worker) | — |
| `deploy.sh <project>` | **zero-downtime rolling deploy** (build-on-server หรือ pull) — ของพังไม่ได้รับ traffic | migration ต้อง expand/contract (docs/25) |
| `artisan.sh <project> <args>` | รัน artisan ใน container จากที่ไหนก็ได้ (เช่น `migrate --force`) | — |
| `rollback.sh <project> <tag>` | กลับ image tag เก่า แบบ rolling (`previous` = ก่อน deploy ล่าสุด) — retag ไม่แก้ `.env` | migration ไม่ย้อนเอง (docs/25) |
| `auto-deploy.sh` | cron: poll git ทุก project → deploy เมื่อมี commit ใหม่ | ดู docs/19-cicd.md |
| `migrate-volumes.sh` | ย้าย volume `docker_<name>` → `<name>` (อัปเกรดเครื่องเก่า ครั้งเดียว) | stop container เดิม — backup ก่อน (docker/README.md) |

ทุก script รันจาก repo root บนเซิร์ฟเวอร์ (แนะนำ clone ไว้ที่ `/opt/infra-stack`)
