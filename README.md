# FateX Service Store — Automatic Credit Top-up

ระบบนี้เพิ่มเครดิตจากฐานข้อมูลเฉพาะหลัง Omise ส่ง `charge.complete` และเซิร์ฟเวอร์ดึง Charge กลับไปตรวจสอบว่า `paid=true`, `status=successful`, สกุลเงินและจำนวนเงินตรงกัน

## ไฟล์สำคัญ
- `index.html` หน้าเว็บและระบบล็อกอิน/เติมเครดิต
- `app-config.js` ใส่ Supabase URL และ Anon Key
- `supabase/schema.sql` ตาราง, RLS และฟังก์ชันเครดิต
- `supabase/functions/create-payment/index.ts` สร้าง PromptPay/TrueMoney payment
- `supabase/functions/payment-webhook/index.ts` ตรวจเงินจริงและเพิ่มเครดิต
- `supabase/functions/spend-credits/index.ts` ตัดเครดิตฝั่งเซิร์ฟเวอร์

## ขั้นตอนติดตั้ง
1. สร้าง Supabase project และรัน `supabase/schema.sql` ใน SQL Editor
2. แก้ `app-config.js` เป็น Project URL และ Anon Key
3. ติดตั้ง Supabase CLI แล้ว login/link project
4. ตั้ง secrets:
   `supabase secrets set OMISE_PUBLIC_KEY=pkey_test_xxx OMISE_SECRET_KEY=skey_test_xxx`
5. Deploy functions:
   `supabase functions deploy create-payment`
   `supabase functions deploy spend-credits`
   `supabase functions deploy payment-webhook --no-verify-jwt`
6. ตั้ง Webhook ใน Omise Dashboard เป็น:
   `https://YOUR_PROJECT_REF.supabase.co/functions/v1/payment-webhook`
7. เริ่มด้วย Test keys และทดสอบก่อนใช้ Live keys
8. อัปโหลดไฟล์หน้าเว็บไป Cloudflare Pages หรือ GitHub Pages

## ความปลอดภัย
- ห้ามใส่ Omise Secret Key หรือ Supabase Service Role Key ใน `index.html` หรือ `app-config.js`
- Webhook ตรวจ Charge จาก Omise ซ้ำ ไม่เชื่อ payload อย่างเดียว
- การเพิ่มและตัดเครดิตทำใน transaction/row lock ฝั่ง PostgreSQL
- `gateway_charge_id` เป็น unique และ `credited_at` ป้องกันเติมซ้ำ
- บัญชีร้านค้าและ KYC ควรเป็นของผู้ปกครอง/ครู/ผู้ดูแลที่ได้รับอนุญาต

หมายเหตุ: TrueMoney ต้องเปิด capability ให้บัญชีร้านค้าก่อน และรูปแบบ source ที่บัญชีได้รับอนุมัติอาจต่างตามผลิตภัณฑ์ Omise ที่เปิดใช้งาน
