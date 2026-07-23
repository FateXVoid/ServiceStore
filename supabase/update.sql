-- ServiceStore V21.1 Top-up Hotfix
-- Safe update: ไม่ลบผู้ใช้ เครดิต สลิป หรือประวัติรายการเดิม

begin;

-- เพิ่มช่องทางชำระเงินที่หน้าเว็บ V21 ใช้งาน
alter table public.topup_requests
  add column if not exists payment_method text;

update public.topup_requests
set payment_method = 'bank'
where payment_method is null or btrim(payment_method) = '';

alter table public.topup_requests
  alter column payment_method set default 'bank',
  alter column payment_method set not null;

-- เปลี่ยนยอดเติมขั้นต่ำจาก 20 บาทเป็น 10 บาท
-- ลบเฉพาะ CHECK constraint ของคอลัมน์ amount เพื่อรองรับชื่อ constraint เดิมที่ต่างกัน
DO $$
DECLARE
  constraint_name text;
BEGIN
  FOR constraint_name IN
    SELECT con.conname
    FROM pg_constraint con
    JOIN pg_class rel ON rel.oid = con.conrelid
    JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
    WHERE nsp.nspname = 'public'
      AND rel.relname = 'topup_requests'
      AND con.contype = 'c'
      AND pg_get_constraintdef(con.oid) ILIKE '%amount%'
  LOOP
    EXECUTE format('alter table public.topup_requests drop constraint if exists %I', constraint_name);
  END LOOP;
END $$;

alter table public.topup_requests
  add constraint topup_requests_amount_range_check
  check (amount between 10 and 5000);

alter table public.topup_requests
  add constraint topup_requests_payment_method_check
  check (payment_method in ('bank', 'truemoney')) not valid;

alter table public.topup_requests
  validate constraint topup_requests_payment_method_check;

select pg_notify('pgrst', 'reload schema');

commit;
