# Watchtower

อัปเดต Docker image อัตโนมัติ (ทุกวัน 04:00) — **opt-in เท่านั้น**

Container ไหนอยากให้อัปเดตอัตโนมัติ ให้ติด label:

```yaml
labels:
  - "com.centurylinklabs.watchtower.enable=true"
```

⚠️ **อย่า** ติด label นี้กับ PostgreSQL / Redis / app ที่มี migration —
พวกนั้นควรอัปเดตด้วยมือผ่าน `scripts/update.sh` หลังอ่าน release notes
