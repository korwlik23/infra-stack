# 02 — Security

🎯 ปิดทางเข้า server ให้เหลือเท่าที่จำเป็น ก่อนลงอย่างอื่นทั้งหมด

## ⚙️ วิธีทำ

```bash
sudo ./scripts/harden.sh
```

สิ่งที่ script ทำ:

1. สร้าง user `deploy` + sudo (เลิกใช้ root)
2. copy SSH key จาก root → deploy
3. ปิด Root Login + Password Login (เหลือ SSH key เท่านั้น)
4. UFW: deny ทุกอย่างขาเข้า ยกเว้น SSH / 80 / 443
5. Fail2ban กัน brute force

## ⚠️ ระวัง (สำคัญที่สุดในเล่มนี้)

- **ก่อนปิด session เดิม** เปิด terminal ใหม่ทดสอบ `ssh deploy@<ip>` ให้เข้าได้ก่อน
  ไม่งั้นล็อกตัวเองออกจากเครื่อง
- ห้าม commit private key / `.env` เข้า Git เด็ดขาด — ดู `.gitignore`
- Database ports (5432, 6379) ไม่เปิดใน UFW — app ต่อผ่าน Docker network เท่านั้น

## 🧪 ทดสอบ

```bash
sudo ufw status verbose          # เห็น 22, 80, 443 allow เท่านั้น
sudo fail2ban-client status sshd # มี jail ทำงาน
ssh root@<ip>                    # ต้องถูกปฏิเสธ
```

## 🔄 Rollback

ถ้าล็อกตัวเองออก: ใช้ VNC console ของ provider (Contabo CCP มีให้)
แก้ `/etc/ssh/sshd_config` กลับแล้ว `systemctl restart ssh`
