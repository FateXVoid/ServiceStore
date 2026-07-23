-- ServiceStore v18 safe migration: no user/order deletion
create extension if not exists pgcrypto;

alter table if exists public.profiles add column if not exists nickname text;
alter table if exists public.profiles add column if not exists avatar_url text;
alter table if exists public.profiles add column if not exists credit_balance integer not null default 0;

alter table if exists public.services add column if not exists slug text;
alter table if exists public.services add column if not exists is_active boolean default true;
alter table if exists public.services add column if not exists sort_order integer default 0;
alter table if exists public.services add column if not exists updated_at timestamptz default now();
update public.services set is_active=coalesce(is_active,active,true) where is_active is null;

alter table if exists public.service_orders add column if not exists admin_note text;
alter table if exists public.service_orders add column if not exists updated_at timestamptz default now();

alter table if exists public.topup_requests add column if not exists admin_note text;
alter table if exists public.withdrawal_requests add column if not exists admin_note text;

create or replace function public.admin_update_order_status(p_order_id uuid,p_status text,p_note text default '')
returns void language plpgsql security definer set search_path=public as $$
begin
 if not public.is_admin() then raise exception 'Admin only'; end if;
 if p_status not in ('pending','accepted','working','completed','cancelled') then raise exception 'Invalid status'; end if;
 if p_status='cancelled' and coalesce(trim(p_note),'')='' then raise exception 'Rejection reason is required'; end if;
 update public.service_orders set status=p_status,admin_note=nullif(trim(p_note),''),updated_at=now() where id=p_order_id;
 if not found then raise exception 'Order not found'; end if;
end $$;
grant execute on function public.admin_update_order_status(uuid,text,text) to authenticated;

create or replace function public.admin_save_service(p_id uuid,p_slug text,p_name text,p_description text,p_price integer,p_is_active boolean,p_sort_order integer)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid; begin
 if not public.is_admin() then raise exception 'Admin only'; end if;
 if coalesce(trim(p_name),'')='' or p_price<1 then raise exception 'Invalid service'; end if;
 if p_id is null then
   insert into public.services(slug,name,description,price,is_active,sort_order,updated_at) values(nullif(lower(trim(p_slug)),''),trim(p_name),coalesce(trim(p_description),''),p_price,coalesce(p_is_active,true),coalesce(p_sort_order,0),now()) returning id into v_id;
 else
   update public.services set slug=nullif(lower(trim(p_slug)),''),name=trim(p_name),description=coalesce(trim(p_description),''),price=p_price,is_active=coalesce(p_is_active,true),sort_order=coalesce(p_sort_order,0),updated_at=now() where id=p_id returning id into v_id;
 end if; return v_id;
end $$;
grant execute on function public.admin_save_service(uuid,text,text,text,integer,boolean,integer) to authenticated;

select pg_notify('pgrst','reload schema');
