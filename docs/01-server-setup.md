# 01 — Server Setup

🎯 เครื่อง Ubuntu ใหม่พร้อมใช้: อัปเดตแล้ว, timezone ถูก, มีเครื่องมือพื้นฐาน

## ⚙️ วิธีทำ

```bash
apt update && apt upgrade -y
timedatectl set-timezone Asia/Bangkok
apt install -y curl wget git unzip zip htop vim nano vnstat
```

(ทั้งหมดนี้อยู่ใน `scripts/harden.sh` แล้ว — ข้อนี้อธิบายว่ามันทำอะไร)

## 🧪 ตรวจสอบเครื่อง

```bash
lscpu                  # CPU
free -h                # RAM
df -h                  # Disk
ip a                   # Network
vnstat                 # Bandwidth (เริ่มเก็บสถิติหลังติดตั้ง)
```

เทียบกับสเปกที่ซื้อ (เช่น Contabo: 4 vCPU / 8GB / 75GB NVMe) ให้ตรง

## ⚠️ ระวัง

- อย่าเพิ่งติดตั้งอะไรอื่นก่อนทำ [02-security.md](02-security.md)
- Contabo แบบรายเดือน: ถ้าจะเปลี่ยนเป็นรายปี/อัปเกรด เช็คเงื่อนไข Live Migration
  จาก Customer Control Panel — ข้อมูลไม่หายถ้าเลือก migrate (ไม่ใช่ reinstall)
