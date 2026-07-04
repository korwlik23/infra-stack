# 22 — Loki (Log Aggregation, v2.0)

🎯 ค้น log ทุก container ย้อนหลังได้จาก Grafana

🤔 **ทำไม Loki ไม่ใช่ ELK**: ELK กิน RAM 2-4GB+ — บนเครื่อง 8GB คือ 1/3 ของเครื่อง
Loki ใช้ ~100-200MB, ใช้ Grafana ที่มีอยู่แล้ว query ได้เลย

## เครื่องมือ log ตอนนี้มี 2 ชั้น

| | Dozzle | Loki |
|--|--------|------|
| ใช้ตอน | ดู log **สด** ตอน debug | **ค้นย้อนหลัง** "เมื่อวาน error อะไร" |
| เก็บ | ไม่เก็บ (stream) | เก็บลงดิสก์ |

## ⚙️ วิธีทำ

อยู่ใน monitoring stack แล้ว (Promtail อ่าน log ทุก container อัตโนมัติ)

Grafana → Explore → **Loki**:

```logql
{container="zennuaflow-app"} |= "ERROR"     # error ของ app เดียว
{container=~".+"} |= "exception"            # ทั้งเครื่อง
```

## ⚠️ ระวัง

- Retention default ไม่จำกัด — เช็คดิสก์เดือนละครั้ง ถ้าโตเร็วตั้ง retention
  (ดู [services/loki/README.md](../services/loki/README.md))
