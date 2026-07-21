# ServiceStore v15

1. สำรองฐานข้อมูล Supabase ก่อน
2. รัน `supabase/servicestore-v15-safe-migration.sql` ใน SQL Editor เพียงไฟล์เดียว
3. นำไฟล์ทั้งหมดขึ้น GitHub แล้วรอ Cloudflare deploy
4. เปิด `admin.html?v=15` และกด Ctrl+Shift+R

Migration นี้ไม่ใช้ DROP TABLE, TRUNCATE หรือ DELETE ข้อมูลผู้ใช้
