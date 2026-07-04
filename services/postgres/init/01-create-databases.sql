-- Databases for each project — runs only on FIRST container start
-- (ถ้า volume มีข้อมูลแล้ว ไฟล์นี้จะไม่ถูกรันซ้ำ)
CREATE DATABASE zennuaflow_db;
CREATE DATABASE trex_db;
CREATE DATABASE printshub_db;
CREATE DATABASE bdo_db;
CREATE DATABASE n8n_db;
