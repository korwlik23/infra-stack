# Loki + Promtail

Log aggregation — เก็บ log ทุก container ค้นย้อนหลังได้ผ่าน Grafana (Explore → Loki)

🤔 **ทำไม Loki ไม่ใช่ ELK**: ELK (Elasticsearch) กิน RAM 2–4GB+ — ไม่เหมาะเครื่อง 8GB
Loki ใช้ ~100-200MB, ต่อ Grafana ที่มีอยู่แล้วได้เลย และ query ด้วย LogQL คล้าย PromQL
(Dozzle ยังอยู่ — ใช้ดู log สด, Loki ใช้ค้นย้อนหลัง)

## Start

อยู่ใน monitoring stack แล้ว — datasource Loki ถูก provision ใน Grafana อัตโนมัติ

## ใช้งาน

Grafana → Explore → datasource **Loki** → query:

```logql
{container="zennuaflow-app"}                    # log ของ container เดียว
{container=~".+"} |= "error"                    # หา error ทุก container
{container="traefik"} | json                    # parse log JSON
```

## ⚠️ ระวัง

- Retention ค่า default ของ image = ไม่จำกัด — ดิสก์โตเรื่อย ๆ
  ถ้าดิสก์ตึงให้ mount config เองแล้วตั้ง `limits_config.retention_period`
- volume `loki_data` ควรอยู่ในรายการ volumes-backup ถ้า log สำคัญต่อ audit
