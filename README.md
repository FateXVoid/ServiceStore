# FateX Service Store — Manual Slip + Owner Admin

ระบบนี้ถอด Omise ออก เปลี่ยนเป็น PromptPay + อัปโหลดสลิป + แอดมินอนุมัติ

## ติดตั้ง
1. นำ Supabase URL และ Anon key เดิมใส่ใน `app-config.js`
2. แทนที่ `promptpay-qr.png` ด้วย QR พร้อมเพย์จริง และแก้ชื่อ/เลขพร้อมเพย์ใน `app-config.js`
3. เปิด Supabase SQL Editor แล้วรัน `supabase/admin-manual-topup.sql`
4. Deploy Edge Function:
   `supabase functions deploy admin-api`
5. อัปโหลดไฟล์เว็บทั้งหมดขึ้น GitHub/Cloudflare ใหม่
6. เข้าระบบด้วย `fatex099@gmail.com` จะเห็นเมนู Admin และเปิด `admin.html` ได้

## ความปลอดภัย
- สิทธิ์แอดมินตรวจจากตาราง `admin_users` ฝั่งเซิร์ฟเวอร์ ไม่ได้เชื่อแค่ UI
- สลิปอยู่ใน private Storage bucket และลิงก์ดูหมดอายุใน 15 นาที
- ลูกค้าเพิ่มเครดิตเองไม่ได้ การอนุมัติทำแบบ atomic ผ่าน PostgreSQL function
- อนุมัติรายการเดิมซ้ำไม่ได้

## หน้า Admin
- ภาพรวมรายรับ เครดิตรวม สมาชิก และสลิปรอตรวจ
- กราฟรายรับ 14 วัน
- อนุมัติ/ปฏิเสธสลิป
- ดูผู้ใช้และปรับเครดิต
- บันทึกรายรับ–รายจ่าย

## Windows PowerShell ขึ้น running scripts is disabled
ไม่ต้องแก้ Execution Policy ก็ได้ ให้ดับเบิลคลิก `deploy-admin.cmd` หรือใช้คำสั่งนี้:

```cmd
npx.cmd supabase functions deploy admin-api
```

ถ้ายังไม่ได้ link โปรเจกต์ ให้ดับเบิลคลิก `link-and-deploy.cmd` แล้วใส่ Project Ref ของ Supabase

## ไฟล์สำคัญ
- `index.html` หน้าร้าน + อัปโหลดสลิป
- `admin.html` หลังบ้าน Owner Control Center
- `admin.js` การทำงาน Dashboard
- `supabase/admin-manual-topup.sql` ตาราง, Storage, RLS และ RPC ปลอดภัย
- `supabase/functions/admin-api/index.ts` API หลังบ้านที่ตรวจสิทธิ์จากฐานข้อมูล
