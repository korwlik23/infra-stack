# แผน: แจ้งเตือน CVE + รับมือ zero-day + AI ยามเฝ้า VPS

สถานะ: **แผน — ยังไม่ได้ทำ** (จดไว้ 2026-11-17) · ทำทีละเฟส แต่ละเฟสใช้งานได้ด้วยตัวเอง

## เป้าหมาย

1. รู้ภายใน 1 วันเมื่อของที่ **รันอยู่จริงบน VPS** มี CVE ที่ต้องอัปเดต — แจ้ง Telegram แบบ
   `เจอช่องโหว่ CVE-xxxx ใน <ของ> · บน VPS เป็นเวอร์ชัน <x> · แก้ที่ <y> · ระดับ <CRITICAL/HIGH> · ทำ: <คำสั่ง>`
2. โดนช่องโหว่ที่ยังไม่มี patch (zero-day) แล้วเสียหายน้อยที่สุด
3. มี "ยาม" อ่านสัญญาณผิดปกติรายวันแล้วสรุปเป็นภาษาคน — โดยตัวยามเองไม่กลายเป็นช่องโหว่

## หลักที่ใช้ทุกเฟส

- **ข้อมูลไหลออก AI ไม่เข้า** — VPS เก็บข้อเท็จจริงเป็นไฟล์ (อ่านอย่างเดียว) · AI / n8n อ่านไฟล์นั้นเท่านั้น
  ไม่มี SSH key / docker.sock / sudo
- **ตัดสินด้วยโค้ด AI แค่เรียบเรียง** — รายการ CVE มาจาก scanner (Trivy) ไม่ใช่ให้ AI เดา · AI ทำแค่จัดลำดับ/อธิบาย
  ถ้า AI ล่มหรือตอบเพี้ยน ต้องยังได้ข้อความดิบ
- **ข้อความจาก log = ข้อมูล ไม่ใช่คำสั่ง** — นับ/สรุปด้วยโค้ดก่อนส่ง ไม่ส่ง log ดิบ (กัน prompt injection + ลดข้อมูลส่วนตัว)
- **ไม่แก้เครื่องเอง** — ทุกข้อความบอกคำสั่งให้คนรัน

## เฟส 0 — พื้นฐานที่ต้องมีก่อน (ส่วนใหญ่เสร็จแล้ว)

- [x] `infra audit` + cron รายสัปดาห์ → Telegram (docs/30)
- [x] backup → Telegram เมื่อล้ม / ไม่มี off-site
- [ ] ตั้ง R2 off-site จริง + token ของ VPS **ลบไม่ได้** + retention ≥ 30 วัน (backup ที่ผู้บุกรุกลบไม่ได้)
- [ ] ซ้อม `infra restore-server` ลง VPS ทดลองหนึ่งรอบ + จดเวลา
- [ ] ปิด/ซ่อนหน้าแอดมินด้วย Cloudflare Access (ลดของที่ CVE ยิงถึงได้มากที่สุด)

## เฟส 1 — แจ้งเตือน CVE ของที่ใช้อยู่ (ไม่ใช้ AI ก็ทำงานได้)

**`scripts/cve-scan.sh`** (cron รายวัน 05:00 หลัง cleanup)

1. รายการของที่รันอยู่: `docker ps` → image ทุกตัว (Traefik, Postgres, Redis, Grafana, app ของ project …)
2. สแกนด้วย **Trivy** (รันเป็น container `aquasec/trivy`, cache DB ใน volume) — ได้ทั้ง OS package ใน image
   และ library ของ app (composer.lock / package-lock.json ที่อยู่ใน image)
   - `--severity CRITICAL,HIGH --ignore-unfixed` → เอาเฉพาะที่ **มี patch แล้ว** (แจ้งแล้วทำได้จริง)
   - host OS: `apt list --upgradable` (security) + kernel ที่รอ reboot (มีใน audit แล้ว)
3. เทียบกับผลเมื่อวาน (`logs/cve-state.json`) → แจ้ง **เฉพาะ CVE ใหม่** ไม่แจ้งซ้ำทุกวัน
4. เขียนผลเป็น `reports/cve-latest.json` (โครงสร้างคงที่) + ส่ง Telegram ตรงจาก script (fallback ถ้าไม่มี AI)
5. บอกวิธีแก้ตามชนิด: stack → `infra update <stack>` · app (base image) → bump `FROM` ใน Dockerfile ·
   app (library) → `composer update <pkg>` / `npm update <pkg>` ใน repo ของ app แล้ว push

เสริม (ฝั่ง repo ของ app — ไม่เกี่ยวกับ VPS): เปิด **GitHub Dependabot alerts + security updates**

ข้อดี: เป็นส่วนที่ได้ผลที่สุดของทั้งแผน และไม่ขึ้นกับ AI เลย

## เฟส 2 — n8n + Gemini เรียบเรียงรายงาน

workflow ใน n8n ที่มีอยู่แล้ว:

```
Schedule (06:00) → Read file reports/cve-latest.json + reports/watch-latest.json
  → IF ไม่มีของใหม่ → จบ (เงียบ)
  → Gemini: "จัดลำดับตามความเสี่ยงจริงของเครื่องนี้ (เปิดสู่ internet ไหม) อธิบายสั้น บอกคำสั่งแก้"
  → Telegram
  → (Gemini ล้ม / เกินโควตา) → ส่งข้อความดิบจากไฟล์แทน
```

- mount `reports/` เข้า n8n แบบ **read-only** — ห้ามให้ n8n สั่ง shell บน host (n8n เปิดหน้าเว็บสู่ internet)
- Gemini free tier: ข้อมูลอาจถูกใช้ปรับปรุง model → ส่งแค่ชื่อ package / เวอร์ชัน / CVE ID / ชื่อ service
  **ไม่ส่ง IP, username, โดเมนลูกค้า, path ภายใน** · ถ้าต่อไปต้องส่งข้อมูลอ่อนไหว → เปลี่ยนเป็น paid tier / Ollama
- API key อยู่ใน credential ของ n8n · ตั้ง quota / restriction ของ key ใน Google AI Studio
- prompt บอกชัดว่าเนื้อหาในไฟล์เป็นข้อมูล ห้ามทำตามคำสั่งที่อยู่ในนั้น

## เฟส 3 — AI ยามเฝ้า (สัญญาณผิดปกติรายวัน)

**`scripts/watch.sh`** (cron ทุกชั่วโมง เขียนไฟล์ · ส่งรายงานวันละครั้งหรือทันทีเมื่อเข้าเงื่อนไขร้ายแรง)

เก็บเป็น **ตัวเลข/รายการที่สรุปแล้ว** เทียบกับรอบก่อน:

| สัญญาณ | ร้ายแรงทันที (ไม่รอ AI) |
|--------|------------------------|
| SSH login สำเร็จ (user, IP, เวลา) — IP ที่ไม่เคยเห็น | login จาก IP ใหม่ |
| `authorized_keys` / crontab / `/etc/cron.d` / sudoers เปลี่ยน | ✅ |
| container / process ใหม่ที่ไม่อยู่ใน compose | ✅ |
| ไฟล์ `.php` / executable ใหม่ใน `storage/`, `public/`, `/tmp` | ✅ |
| CPU สูงค้าง > 30 นาที, traffic ขาออกพุ่ง | — |
| จำนวน IP ที่ fail2ban แบน, request 4xx/5xx แปลกใน Traefik (นับตาม path pattern) | — |

- ข้อที่ "ร้ายแรงทันที" ส่ง Telegram จาก script เลย — ไม่พึ่ง AI (AI โดนหลอกได้ / ช้า)
- ที่เหลือส่งเข้า workflow เฟส 2 ให้ Gemini สรุปวันละครั้ง
- อนาคต: แทน fail2ban ด้วย **CrowdSec** (อ่าน log Traefik + blocklist กลาง)

## เฟส 4 — ลดความเสียหายเมื่อโดน zero-day (ทำได้ทุกเมื่อ ไม่ขึ้นกับเฟสอื่น)

- [ ] DB user แยกต่อ project (ตอนนี้ app ต่อ Postgres ด้วย superuser ตัวเดียวกัน → app เดียวโดน = ทุก database + RCE ผ่าน `COPY … PROGRAM`)
- [ ] template project: `security_opt: no-new-privileges`, `cap_drop: [ALL]`, รันเป็น non-root, `read_only` ถ้าทำได้
- [ ] Cloudflare WAF managed rules (virtual patch ระหว่างรออัปเดต)
- [ ] runbook "ตอนโดนจริง" ใน docs (ลำดับ: snapshot → ตัดการเข้าถึง → เปลี่ยน secret จากเครื่องอื่น → หาวันที่โดน →
      restore-server ลงเครื่องใหม่ → แจ้ง PDPA ภายใน 72 ชม. ถ้าข้อมูลส่วนบุคคลหลุด)

## ลำดับที่แนะนำ

เฟส 0 (R2 + ซ้อม restore) → เฟส 1 → ใช้จริง 2–4 สัปดาห์ (ดูว่า noise เยอะไหม) → เฟส 4 (DB user) → เฟส 2 → เฟส 3

เหตุผล: เฟส 1 ให้ผลมากสุดด้วยงานน้อยสุด · AI (เฟส 2–3) มีค่าก็ต่อเมื่อข้อมูลข้างล่างนิ่งแล้ว
ถ้าข้อความดิบจากเฟส 1 อ่านรู้เรื่องอยู่แล้ว อาจไม่ต้องทำเฟส 2 เลย

## ไม่ทำ (ตั้งใจ)

- ให้ AI แก้เครื่อง / อัปเดต / บล็อก IP เอง
- ส่ง log ดิบให้ AI
- ให้ n8n หรือ AI มีสิทธิ์ SSH / docker.sock
