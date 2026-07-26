-- Databases for each project — runs only on FIRST container start
-- (ถ้า volume มีข้อมูลแล้ว ไฟล์นี้จะไม่ถูกรันซ้ำ)
CREATE DATABASE app_db;
CREATE DATABASE n8n_db;
