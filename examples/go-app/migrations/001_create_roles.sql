-- expand/contract: เพิ่มได้อย่างเดียวใน release เดียว (docs/25)
CREATE TABLE IF NOT EXISTS roles (
  id   serial PRIMARY KEY,
  name text NOT NULL UNIQUE
);
