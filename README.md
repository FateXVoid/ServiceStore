# FateX Service Store — Simple Admin Backend

เวอร์ชันนี้เปลี่ยนระบบหลังบ้านให้เรียบง่ายขึ้น โดย **ไม่ใช้ `admin-api` Edge Function** แล้ว
หน้า `admin.html` ติดต่อ Supabase Database โดยตรงผ่าน RLS และ RPC ที่ตรวจสิทธิ์แอดมินในฐานข้อมูล

## ความสามารถหลังบ้าน
- ภาพรวมรายรับ เครดิตรวม จำนวนสมาชิก และสลิปรอตรวจ
- กราฟรายรับ 14 วันล่าสุด
- ดูสลิป อนุมัติ หรือปฏิเสธรายการเติมเงิน
- ดูรายชื่อลูกค้าและปรับเครดิต
- บันทึกรายรับ–รายจ่าย
- ตรวจสิทธิ์เจ้าของร้านจาก `admin_users`

## วิธีติดตั้ง
1. ตรวจ `app-config.js` ให้มี Supabase URL และ Publishable key ถูกต้อง
2. เข้า Supabase → SQL Editor
3. เปิดไฟล์ `supabase/admin-simple.sql` คัดลอกทั้งหมดแล้วกด Run **ครั้งเดียว**
4. เอาไฟล์โปรเจกต์นี้ขึ้น GitHub แล้วรอ Cloudflare Deploy
5. เข้าหน้าร้านด้วย `fatex099@gmail.com`
6. เปิด `admin.html?v=10`

## สิ่งที่ไม่ต้องทำแล้ว
- ไม่ต้อง Deploy `admin-api`
- ไม่ต้องใช้ Supabase CLI สำหรับระบบหลังบ้าน
- ไม่ต้องตั้งค่า CORS ของ Admin Edge Function
- ไม่ต้องตั้ง Secret/Service Role key บนเว็บไซต์

## ความปลอดภัย
- หน้าเว็บใช้เฉพาะ Publishable key ซึ่งวางใน Frontend ได้
- RLS จำกัดข้อมูลทั่วไปตามผู้ใช้
- RPC ทุกตัวตรวจ `auth.uid()` กับตาราง `admin_users` ฝั่งฐานข้อมูล
- ลูกค้าทั่วไปเรียกคำสั่งอนุมัติสลิปหรือปรับเครดิตไม่ได้
- สลิปเป็น private bucket และออก signed URL ชั่วคราวให้แอดมิน

> ระบบ `spend-credits` ของหน้าร้านยังคงเป็นคนละส่วน และสามารถใช้ Edge Function เดิมต่อได้

## Account Center v12
Run `supabase/account-center-v12.sql` once in Supabase SQL Editor. This adds profile editing, avatars, full user history, bank/TrueMoney top-ups, and withdrawal requests. The admin dashboard remains compatible with top-up requests.


## v13 Marketplace upgrade
Run `supabase/marketplace-v13.sql` once in Supabase SQL Editor. This adds real service orders, atomic credit deduction, customer order history, admin order workflow, and admin credit controls.
