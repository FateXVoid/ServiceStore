-- ServiceStore v15 safe migration: ไม่ลบข้อมูลเดิม
create extension if not exists pgcrypto;

alter table public.profiles add column if not exists nickname text;
alter table public.profiles add column if not exists avatar_url text;
alter table public.profiles add column if not exists credit_balance integer not null default 0;

create table if not exists public.services (
 id uuid primary key default gen_random_uuid(), slug text not null unique, name text not null,
 description text not null default '', price integer not null default 1 check(price>0),
 is_active boolean not null default true, sort_order integer not null default 0,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now());

create table if not exists public.withdrawal_requests (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
 amount integer not null check(amount>0), payout_method text not null default 'bank', payout_account text,
 payout_name text, status text not null default 'pending' check(status in('pending','approved','rejected')),
 admin_note text, reviewed_by uuid references auth.users(id), reviewed_at timestamptz, created_at timestamptz not null default now());

insert into public.services(slug,name,description,price,sort_order) values
('portfolio','รับทำ Portfolio','ออกแบบ Portfolio สำหรับสมัครเรียน สมัครงาน หรือแนะนำตัว',499,1),
('delivery','รับส่งของหรือสินค้า','บริการรับและส่งสิ่งของตามจุดที่กำหนด',99,2)
on conflict(slug) do nothing;

create or replace function public.admin_list_users()
returns table(id uuid,email text,nickname text,avatar_url text,credit_balance integer,created_at timestamptz)
language sql security definer set search_path=public,auth as $$
 select u.id,coalesce(p.email,u.email)::text,
 coalesce(p.nickname,u.raw_user_meta_data->>'nickname',u.raw_user_meta_data->>'display_name','')::text,
 coalesce(p.avatar_url,u.raw_user_meta_data->>'avatar_url','')::text,
 coalesce(p.credit_balance,0)::integer,coalesce(p.created_at,u.created_at)
 from auth.users u left join public.profiles p on p.id=u.id
 where public.is_admin() order by u.created_at desc;
$$;
revoke all on function public.admin_list_users() from public,anon;
grant execute on function public.admin_list_users() to authenticated;

alter table public.services enable row level security;
alter table public.withdrawal_requests enable row level security;
drop policy if exists services_read on public.services;
create policy services_read on public.services for select using(is_active or public.is_admin());
drop policy if exists withdrawals_own_read on public.withdrawal_requests;
create policy withdrawals_own_read on public.withdrawal_requests for select to authenticated using(auth.uid()=user_id or public.is_admin());
drop policy if exists withdrawals_own_insert on public.withdrawal_requests;
create policy withdrawals_own_insert on public.withdrawal_requests for insert to authenticated with check(auth.uid()=user_id and status='pending');
grant select on public.services to anon,authenticated;
grant select,insert on public.withdrawal_requests to authenticated;

create or replace function public.admin_save_service(p_id uuid,p_slug text,p_name text,p_description text,p_price integer,p_is_active boolean,p_sort_order integer)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid; begin
 if not public.is_admin() then raise exception 'Admin only'; end if;
 if coalesce(trim(p_slug),'')='' or coalesce(trim(p_name),'')='' or p_price<1 then raise exception 'Invalid service'; end if;
 if p_id is null then insert into public.services(slug,name,description,price,is_active,sort_order) values(lower(trim(p_slug)),trim(p_name),coalesce(trim(p_description),''),p_price,coalesce(p_is_active,true),coalesce(p_sort_order,0)) returning id into v_id;
 else update public.services set slug=lower(trim(p_slug)),name=trim(p_name),description=coalesce(trim(p_description),''),price=p_price,is_active=coalesce(p_is_active,true),sort_order=coalesce(p_sort_order,0),updated_at=now() where id=p_id returning id into v_id; end if;
 return v_id; end $$;
revoke all on function public.admin_save_service(uuid,text,text,text,integer,boolean,integer) from public,anon;
grant execute on function public.admin_save_service(uuid,text,text,text,integer,boolean,integer) to authenticated;

select pg_notify('pgrst','reload schema');
