-- FateX Simple Admin Backend
-- รันไฟล์นี้ครั้งเดียวใน Supabase > SQL Editor
-- ระบบหลังบ้านจะคุยกับ Supabase Database โดยตรง ไม่ใช้ admin-api Edge Function

create extension if not exists pgcrypto;

create table if not exists public.admin_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.topup_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  amount integer not null check (amount between 20 and 5000),
  transfer_reference text not null,
  slip_path text not null,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  admin_note text,
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.admin_ledger (
  id uuid primary key default gen_random_uuid(),
  amount integer not null check (amount <> 0),
  note text not null default '',
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

insert into public.admin_users(user_id)
select id from auth.users where lower(email) = lower('fatex099@gmail.com')
on conflict do nothing;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.admin_users where user_id = auth.uid()
  );
$$;

revoke all on function public.is_admin() from public, anon;
grant execute on function public.is_admin() to authenticated;

alter table public.admin_users enable row level security;
alter table public.topup_requests enable row level security;
alter table public.admin_ledger enable row level security;
alter table public.profiles enable row level security;

-- ลูกค้าเห็นและสร้างได้เฉพาะรายการของตัวเอง
drop policy if exists topups_select_own on public.topup_requests;
create policy topups_select_own on public.topup_requests
for select to authenticated
using (auth.uid() = user_id);

drop policy if exists topups_insert_own on public.topup_requests;
create policy topups_insert_own on public.topup_requests
for insert to authenticated
with check (auth.uid() = user_id and status = 'pending');

-- แอดมินอ่านข้อมูลที่หน้า Dashboard ต้องใช้ได้โดยตรง
drop policy if exists admin_read_topups on public.topup_requests;
create policy admin_read_topups on public.topup_requests
for select to authenticated
using (public.is_admin());

drop policy if exists admin_read_profiles on public.profiles;
create policy admin_read_profiles on public.profiles
for select to authenticated
using (public.is_admin());

drop policy if exists admin_read_ledger on public.admin_ledger;
create policy admin_read_ledger on public.admin_ledger
for select to authenticated
using (public.is_admin());

insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values (
  'payment-slips', 'payment-slips', false, 5242880,
  array['image/jpeg','image/png','image/webp']
)
on conflict(id) do update set
  public = false,
  file_size_limit = 5242880,
  allowed_mime_types = array['image/jpeg','image/png','image/webp'];

drop policy if exists slip_upload_own_folder on storage.objects;
create policy slip_upload_own_folder on storage.objects
for insert to authenticated
with check (
  bucket_id = 'payment-slips'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists slip_read_own_folder on storage.objects;
create policy slip_read_own_folder on storage.objects
for select to authenticated
using (
  bucket_id = 'payment-slips'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists admin_read_payment_slips on storage.objects;
create policy admin_read_payment_slips on storage.objects
for select to authenticated
using (bucket_id = 'payment-slips' and public.is_admin());

create or replace function public.admin_approve_topup_simple(
  p_request_id uuid,
  p_note text default ''
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  r public.topup_requests%rowtype;
  new_balance integer;
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;

  select * into r
  from public.topup_requests
  where id = p_request_id
  for update;

  if not found then raise exception 'not_found'; end if;
  if r.status <> 'pending' then raise exception 'already_reviewed'; end if;

  insert into public.profiles(id, credit_balance)
  values (r.user_id, 0)
  on conflict(id) do nothing;

  update public.profiles
  set credit_balance = credit_balance + r.amount
  where id = r.user_id
  returning credit_balance into new_balance;

  insert into public.credit_transactions(user_id, amount, transaction_type, description)
  values (r.user_id, r.amount, 'topup', 'Manual slip approved');

  update public.topup_requests
  set status = 'approved',
      admin_note = coalesce(p_note, ''),
      reviewed_by = auth.uid(),
      reviewed_at = now()
  where id = p_request_id;

  insert into public.admin_ledger(amount, note, created_by)
  values (r.amount, 'Approved top-up ' || r.id, auth.uid());

  return new_balance;
end;
$$;

create or replace function public.admin_reject_topup_simple(
  p_request_id uuid,
  p_note text default ''
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;

  update public.topup_requests
  set status = 'rejected',
      admin_note = coalesce(p_note, ''),
      reviewed_by = auth.uid(),
      reviewed_at = now()
  where id = p_request_id and status = 'pending';

  if not found then raise exception 'already_reviewed_or_not_found'; end if;
  return true;
end;
$$;

create or replace function public.admin_adjust_credit_simple(
  p_user_id uuid,
  p_amount integer,
  p_note text default ''
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  new_balance integer;
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  if p_amount = 0 or abs(p_amount) > 100000 then raise exception 'invalid_amount'; end if;

  insert into public.profiles(id, credit_balance)
  values (p_user_id, 0)
  on conflict(id) do nothing;

  update public.profiles
  set credit_balance = greatest(0, credit_balance + p_amount)
  where id = p_user_id
  returning credit_balance into new_balance;

  insert into public.credit_transactions(user_id, amount, transaction_type, description)
  values (p_user_id, p_amount, 'admin_adjustment', coalesce(nullif(p_note, ''), 'Admin adjustment'));

  return new_balance;
end;
$$;

create or replace function public.admin_add_ledger_simple(
  p_amount integer,
  p_note text default ''
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  new_id uuid;
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  if p_amount = 0 or abs(p_amount) > 10000000 then raise exception 'invalid_amount'; end if;

  insert into public.admin_ledger(amount, note, created_by)
  values (p_amount, coalesce(p_note, ''), auth.uid())
  returning id into new_id;

  return new_id;
end;
$$;

revoke all on function public.admin_approve_topup_simple(uuid,text) from public, anon;
revoke all on function public.admin_reject_topup_simple(uuid,text) from public, anon;
revoke all on function public.admin_adjust_credit_simple(uuid,integer,text) from public, anon;
revoke all on function public.admin_add_ledger_simple(integer,text) from public, anon;

grant execute on function public.admin_approve_topup_simple(uuid,text) to authenticated;
grant execute on function public.admin_reject_topup_simple(uuid,text) to authenticated;
grant execute on function public.admin_adjust_credit_simple(uuid,integer,text) to authenticated;
grant execute on function public.admin_add_ledger_simple(integer,text) to authenticated;
