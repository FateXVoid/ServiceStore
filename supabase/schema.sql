-- Run this file in Supabase SQL Editor
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  credit_balance integer not null default 0 check (credit_balance >= 0),
  created_at timestamptz not null default now()
);

create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  amount integer not null check (amount between 20 and 5000),
  method text not null check (method in ('promptpay','truemoney')),
  gateway_charge_id text unique,
  gateway_source_id text,
  status text not null default 'pending' check (status in ('pending','paid','failed','expired')),
  credited_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.credit_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  payment_id uuid references public.payments(id),
  amount integer not null,
  transaction_type text not null check (transaction_type in ('topup','purchase','refund','adjustment')),
  reference text,
  created_at timestamptz not null default now()
);

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into public.profiles(id,email) values(new.id,new.email)
  on conflict(id) do nothing;
  return new;
end; $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute function public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.payments enable row level security;
alter table public.credit_transactions enable row level security;

create policy "read own profile" on public.profiles for select using (auth.uid()=id);
create policy "read own payments" on public.payments for select using (auth.uid()=user_id);
create policy "read own transactions" on public.credit_transactions for select using (auth.uid()=user_id);

create or replace function public.credit_paid_payment(p_payment_id uuid, p_gateway_charge_id text)
returns void language plpgsql security definer set search_path=public as $$
declare p public.payments;
begin
  select * into p from public.payments where id=p_payment_id for update;
  if p.id is null then raise exception 'payment_not_found'; end if;
  if p.status='paid' or p.credited_at is not null then return; end if;
  if p.gateway_charge_id is distinct from p_gateway_charge_id then raise exception 'charge_mismatch'; end if;

  update public.payments set status='paid', credited_at=now() where id=p.id;
  update public.profiles set credit_balance=credit_balance+p.amount where id=p.user_id;
  insert into public.credit_transactions(user_id,payment_id,amount,transaction_type,reference)
  values(p.user_id,p.id,p.amount,'topup',p_gateway_charge_id);
end; $$;

create or replace function public.spend_service_credits(p_user_id uuid,p_service_id text,p_cost integer)
returns integer language plpgsql security definer set search_path=public as $$
declare bal integer;
begin
  select credit_balance into bal from public.profiles where id=p_user_id for update;
  if bal is null then raise exception 'profile_not_found'; end if;
  if p_cost <= 0 then raise exception 'invalid_cost'; end if;
  if bal < p_cost then raise exception 'insufficient_credits'; end if;
  update public.profiles set credit_balance=credit_balance-p_cost where id=p_user_id returning credit_balance into bal;
  insert into public.credit_transactions(user_id,amount,transaction_type,reference)
  values(p_user_id,-p_cost,'purchase',p_service_id);
  return bal;
end; $$;

revoke all on function public.credit_paid_payment(uuid,text) from public, anon, authenticated;
revoke all on function public.spend_service_credits(uuid,text,integer) from public, anon, authenticated;
