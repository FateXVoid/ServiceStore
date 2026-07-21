-- ServiceStore v14: reliable user list + editable services
create table if not exists public.services (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null,
  description text not null default '',
  price integer not null check (price > 0),
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.services enable row level security;
drop policy if exists "public read active services" on public.services;
create policy "public read active services" on public.services for select using (is_active or public.is_admin());
grant select on public.services to anon, authenticated;
insert into public.services(slug,name,description,price,sort_order) values
('portfolio','รับทำ Portfolio','ออกแบบ Portfolio สำหรับสมัครเรียน สมัครงาน หรือแนะนำตัว พร้อมจัดวางเนื้อหาอย่างมืออาชีพ',499,1),
('delivery','รับส่งของหรือสินค้า','บริการรับและส่งสิ่งของตามจุดที่กำหนด พร้อมติดตามรายละเอียดงานผ่านระบบ',99,2)
on conflict (slug) do nothing;

create or replace function public.admin_list_users()
returns table(id uuid,email text,nickname text,avatar_url text,credit_balance numeric,created_at timestamptz)
language sql security definer set search_path=public,auth as $$
  select u.id,u.email,coalesce(p.nickname,''),coalesce(p.avatar_url,''),coalesce(p.credit_balance,0),u.created_at
  from auth.users u left join public.profiles p on p.id=u.id
  where public.is_admin()
  order by u.created_at desc;
$$;
revoke all on function public.admin_list_users() from public;
grant execute on function public.admin_list_users() to authenticated;

create or replace function public.admin_save_service(p_id uuid,p_slug text,p_name text,p_description text,p_price integer,p_is_active boolean,p_sort_order integer)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid;
begin
 if not public.is_admin() then raise exception 'Admin only'; end if;
 if coalesce(trim(p_slug),'')='' or coalesce(trim(p_name),'')='' or p_price<1 then raise exception 'Invalid service'; end if;
 if p_id is null then
   insert into public.services(slug,name,description,price,is_active,sort_order) values(lower(trim(p_slug)),trim(p_name),coalesce(trim(p_description),''),p_price,coalesce(p_is_active,true),coalesce(p_sort_order,0)) returning id into v_id;
 else
   update public.services set slug=lower(trim(p_slug)),name=trim(p_name),description=coalesce(trim(p_description),''),price=p_price,is_active=coalesce(p_is_active,true),sort_order=coalesce(p_sort_order,0),updated_at=now() where id=p_id returning id into v_id;
 end if;
 return v_id;
end;$$;
revoke all on function public.admin_save_service(uuid,text,text,text,integer,boolean,integer) from public;
grant execute on function public.admin_save_service(uuid,text,text,text,integer,boolean,integer) to authenticated;

create or replace function public.purchase_service(p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_user uuid:=auth.uid(); v_service public.services%rowtype; v_balance numeric; v_order uuid;
begin
 if v_user is null then raise exception 'กรุณาเข้าสู่ระบบ'; end if;
 select * into v_service from public.services where slug=p_payload->>'service_id' and is_active=true;
 if v_service.id is null then raise exception 'บริการนี้ปิดขายหรือไม่พบข้อมูล'; end if;
 if coalesce(trim(p_payload->>'customer_name'),'')='' or coalesce(trim(p_payload->>'contact'),'')='' or coalesce(trim(p_payload->>'details'),'')='' then raise exception 'กรุณากรอกข้อมูลให้ครบ'; end if;
 insert into public.profiles(id,email,credit_balance) select v_user,u.email,0 from auth.users u where u.id=v_user on conflict(id) do nothing;
 select credit_balance into v_balance from public.profiles where id=v_user for update;
 if coalesce(v_balance,0)<v_service.price then raise exception 'เครดิตไม่เพียงพอ'; end if;
 update public.profiles set credit_balance=credit_balance-v_service.price where id=v_user;
 insert into public.service_orders(user_id,service_id,service_name,price,customer_name,contact,deadline,details)
 values(v_user,v_service.slug,v_service.name,v_service.price,trim(p_payload->>'customer_name'),trim(p_payload->>'contact'),nullif(p_payload->>'deadline','')::date,trim(p_payload->>'details')) returning id into v_order;
 insert into public.credit_transactions(user_id,amount,transaction_type,description) values(v_user,-v_service.price,'purchase','ซื้อบริการ: '||v_service.name||' #'||left(v_order::text,8));
 return jsonb_build_object('order_id',v_order,'price',v_service.price,'remaining_balance',v_balance-v_service.price,'status','pending');
end;$$;
revoke all on function public.purchase_service(jsonb) from public;
grant execute on function public.purchase_service(jsonb) to authenticated;
