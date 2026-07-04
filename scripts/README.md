# scripts/ — Automation

| Script | ทำอะไร | ระวัง |
|--------|--------|-------|
| `harden.sh` | Day-1 server hardening (root เท่านั้น, รันครั้งเดียว) | ทดสอบ SSH ใหม่ก่อนปิด session เดิม |
| `update.sh [stack]` | pull image ใหม่ + up -d ทีละ stack | database ต้อง backup ก่อน (มี gate) |
| `backup.sh` | backup PostgreSQL + volumes ทั้งหมด | — |
| `restore.sh [file]` | restore PostgreSQL (default = ล่าสุด) | เขียนทับข้อมูล — มี confirmation |
| `create-project.sh <name> <template>` | สร้าง project จาก template | — |

ทุก script รันจาก repo root บนเซิร์ฟเวอร์ (แนะนำ clone ไว้ที่ `/opt/infra-stack`)
