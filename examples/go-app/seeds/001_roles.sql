-- ข้อมูลพื้นฐาน — รันซ้ำได้ (ON CONFLICT DO NOTHING) เพราะ deploy อาจ seed หลายรอบ
INSERT INTO roles (name) VALUES ('admin'), ('member')
ON CONFLICT (name) DO NOTHING;
