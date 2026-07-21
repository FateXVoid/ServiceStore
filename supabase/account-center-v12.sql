-- FateX Account Center v12
-- Run once in Supabase SQL Editor after admin-simple.sql

alter table public.profiles add column if not exists nickname text;
alter table public.profiles add column if not exists avatar_url text;
alter table public.profiles add column if not exists email text;
alter table public.profiles add column if not exists created_at timestamptz not null default now();

alter table public.topup_requests add column if not exists payment_method text not null default 'bank';
do $$ begin
  alter table public.topup_requests add constraint topup_payment_method_check check (payment_method in ('bank','truemoney'));
exception when duplicate_object then null; end $$;

create table if not exists public.withdrawal_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  amount integer not null check (amount between 50 and 50000),
  payout_method text not null check (payout_method in ('bank','truemoney')),
  payout_account text not null,
  payout_name text not null,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  admin_note text,
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.withdrawal_requests enable row level security;

drop policy if exists profiles_select_own on public.profiles;
create policy profiles_select_own on public.profiles for select to authenticated using (auth.uid() = id or public.is_admin());
drop policy if exists profiles_insert_own on public.profiles;
create policy profiles_insert_own on public.profiles for insert to authenticated with check (auth.uid() = id);
drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles for update to authenticated using (auth.uid() = id) with check (auth.uid() = id);

drop policy if exists withdrawals_select_own on public.withdrawal_requests;
create policy withdrawals_select_own on public.withdrawal_requests for select to authenticated using (auth.uid() = user_id or public.is_admin());
drop policy if exists withdrawals_insert_own on public.withdrawal_requests;
create policy withdrawals_insert_own on public.withdrawal_requests for insert to authenticated with check (auth.uid() = user_id and status = 'pending');

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('avatars','avatars',true,3145728,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=true,file_size_limit=3145728,allowed_mime_types=array['image/jpeg','image/png','image/webp'];

drop policy if exists avatar_upload_own on storage.objects;
create policy avatar_upload_own on storage.objects for insert to authenticated
with check (bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists avatar_update_own on storage.objects;
create policy avatar_update_own on storage.objects for update to authenticated
using (bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text)
with check (bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists avatar_read_public on storage.objects;
create policy avatar_read_public on storage.objects for select to public using (bucket_id='avatars');

-- Keep profile email in sync for current users
update public.profiles p set email=u.email from auth.users u where p.id=u.id and p.email is null;

create or replace function public.handle_new_user_profile()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into public.profiles(id,email,credit_balance,nickname)
  values(new.id,new.email,0,coalesce(new.raw_user_meta_data->>'display_name',split_part(new.email,'@',1)))
  on conflict(id) do update set email=excluded.email;
  return new;
end; $$;

drop trigger if exists on_auth_user_created_profile on auth.users;
create trigger on_auth_user_created_profile after insert on auth.users
for each row execute procedure public.handle_new_user_profile();

create or replace function public.admin_approve_withdrawal_simple(p_request_id uuid, p_note text default '')
returns integer language plpgsql security definer set search_path=public as $$
declare r public.withdrawal_requests%rowtype; new_balance integer;
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  select * into r from public.withdrawal_requests where id=p_request_id for update;
  if not found then raise exception 'not_found'; end if;
  if r.status <> 'pending' then raise exception 'already_reviewed'; end if;
  update public.profiles set credit_balance=credit_balance-r.amount
  where id=r.user_id and credit_balance>=r.amount returning credit_balance into new_balance;
  if not found then raise exception 'insufficient_credit'; end if;
  insert into public.credit_transactions(user_id,amount,transaction_type,description)
  values(r.user_id,-r.amount,'withdrawal',coalesce(nullif(p_note,''),'Withdrawal approved'));
  update public.withdrawal_requests set status='approved',admin_note=coalesce(p_note,''),reviewed_by=auth.uid(),reviewed_at=now() where id=p_request_id;
  insert into public.admin_ledger(amount,note,created_by) values(-r.amount,'Approved withdrawal '||r.id,auth.uid());
  return new_balance;
end; $$;

create or replace function public.admin_reject_withdrawal_simple(p_request_id uuid, p_note text default '')
returns boolean language plpgsql security definer set search_path=public as $$
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  update public.withdrawal_requests set status='rejected',admin_note=coalesce(p_note,''),reviewed_by=auth.uid(),reviewed_at=now()
  where id=p_request_id and status='pending';
  if not found then raise exception 'already_reviewed_or_not_found'; end if;
  return true;
end; $$;

revoke all on function public.admin_approve_withdrawal_simple(uuid,text) from public,anon;
revoke all on function public.admin_reject_withdrawal_simple(uuid,text) from public,anon;
grant execute on function public.admin_approve_withdrawal_simple(uuid,text) to authenticated;
grant execute on function public.admin_reject_withdrawal_simple(uuid,text) to authenticated;
