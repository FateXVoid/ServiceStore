-- ServiceStore V22 Control Center migration
-- Safe migration: ไม่ลบผู้ใช้ เครดิต ออเดอร์ สลิป หรือประวัติเดิม
begin;

create extension if not exists pgcrypto;

-- บริการแก้ไขได้จากแอดมิน
alter table public.services add column if not exists icon text not null default '✨';
alter table public.services add column if not exists badge text not null default '';
alter table public.services add column if not exists price_label text not null default '/ งาน';
alter table public.services add column if not exists requires_distance boolean not null default false;
alter table public.services add column if not exists is_custom boolean not null default false;
alter table public.services add column if not exists updated_at timestamptz not null default now();
update public.services set requires_distance=true,price_label='/ เที่ยว',icon='📦' where slug='delivery';
update public.services set is_custom=true,price_label='ตามรายละเอียด',icon='🛠️' where slug='custom';
update public.services set icon=case slug when 'portfolio' then '💼' when 'presentation' then '📊' when 'poster' then '🎨' when 'document' then '📝' else icon end;

-- แก้ Custom Request ที่ติด CHECK เก่าของ service_id
DO $$ declare r record; begin
  for r in select con.conname from pg_constraint con join pg_class rel on rel.oid=con.conrelid join pg_namespace n on n.oid=rel.relnamespace
    where n.nspname='public' and rel.relname='service_orders' and con.contype='c' and pg_get_constraintdef(con.oid) ilike '%service_id%'
  loop execute format('alter table public.service_orders drop constraint if exists %I',r.conname); end loop;
end $$;

-- ประกาศเว็บไซต์
create table if not exists public.announcements(
 id uuid primary key default gen_random_uuid(), title text not null, summary text not null default '', content text not null default '', icon text not null default '📣',
 is_published boolean not null default true, is_pinned boolean not null default false, source text not null default 'manual', published_at timestamptz not null default now(), created_at timestamptz not null default now(), created_by uuid references auth.users(id) on delete set null
);
alter table public.announcements enable row level security;
drop policy if exists "Public read published announcements" on public.announcements;
create policy "Public read published announcements" on public.announcements for select using (is_published=true or public.is_admin());
drop policy if exists "Admins manage announcements" on public.announcements;
create policy "Admins manage announcements" on public.announcements for all to authenticated using (public.is_admin()) with check (public.is_admin());
grant select on public.announcements to anon,authenticated;
grant insert,update,delete on public.announcements to authenticated;

insert into public.announcements(title,summary,content,icon,is_published,is_pinned,source)
select 'ระบบเว็บไซต์ V22 พร้อมใช้งาน','เพิ่มศูนย์จัดการบริการ ประกาศ ตรวจสลิป และแก้ระบบ Custom request','แอดมินสามารถแก้บริการและส่งประกาศจากหลังบ้านได้แล้ว พร้อมปรับระบบคำสั่งซื้อและกระเป๋าเครดิต','🚀',true,true,'automatic'
where not exists(select 1 from public.announcements where title='ระบบเว็บไซต์ V22 พร้อมใช้งาน');

-- สลิป: รับประกันคอลัมน์และ Storage bucket
alter table public.topup_requests add column if not exists payment_method text not null default 'bank';
alter table public.topup_requests add column if not exists slip_path text;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('payment-slips','payment-slips',false,5242880,array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists "Users upload own payment slips" on storage.objects;
create policy "Users upload own payment slips" on storage.objects for insert to authenticated with check(bucket_id='payment-slips' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists "Users read own payment slips" on storage.objects;
create policy "Users read own payment slips" on storage.objects for select to authenticated using(bucket_id='payment-slips' and ((storage.foldername(name))[1]=auth.uid()::text or public.is_admin()));

-- เติมขั้นต่ำ 10 บาท และรองรับชนิดธุรกรรมทั้งหมดที่ระบบใช้
alter table public.topup_requests drop constraint if exists topup_requests_amount_range_check;
alter table public.topup_requests add constraint topup_requests_amount_range_check check(amount between 10 and 5000) not valid;
alter table public.credit_transactions drop constraint if exists credit_transactions_transaction_type_check;
alter table public.credit_transactions add constraint credit_transactions_transaction_type_check check(transaction_type in ('topup','purchase','admin_adjustment','adjustment','refund','bonus','withdraw','manual')) not valid;

-- บันทึกบริการจากหน้าแอดมิน
create or replace function public.admin_save_service(p_id uuid,p_slug text,p_name text,p_description text,p_price integer,p_is_active boolean,p_sort_order integer,p_icon text default '✨',p_badge text default '',p_price_label text default '/ งาน',p_requires_distance boolean default false,p_is_custom boolean default false)
returns uuid language plpgsql security definer set search_path=public as $$ declare v_id uuid; begin
 if not public.is_admin() then raise exception 'ไม่มีสิทธิ์แอดมิน'; end if;
 if p_slug !~ '^[a-z0-9-]+$' or btrim(p_name)='' or p_price<0 then raise exception 'ข้อมูลบริการไม่ถูกต้อง'; end if;
 if p_id is null then insert into services(slug,name,description,price,is_active,sort_order,icon,badge,price_label,requires_distance,is_custom,updated_at) values(p_slug,p_name,p_description,p_price,p_is_active,p_sort_order,p_icon,p_badge,p_price_label,p_requires_distance,p_is_custom,now()) returning id into v_id;
 else update services set slug=p_slug,name=p_name,description=p_description,price=p_price,is_active=p_is_active,sort_order=p_sort_order,icon=p_icon,badge=p_badge,price_label=p_price_label,requires_distance=p_requires_distance,is_custom=p_is_custom,updated_at=now() where id=p_id returning id into v_id; end if;
 return v_id; end $$;
grant execute on function public.admin_save_service(uuid,text,text,text,integer,boolean,integer,text,text,text,boolean,boolean) to authenticated;

-- ซื้อบริการแบบอ่านราคาจากตาราง ไม่ต้องแก้โค้ดทุกครั้งที่เพิ่มบริการ
create or replace function public.purchase_service(p_payload jsonb) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_user uuid:=auth.uid(); v_service services%rowtype; v_price integer; v_balance integer; v_order uuid; begin
 if v_user is null then raise exception 'กรุณาเข้าสู่ระบบ'; end if;
 select * into v_service from services where slug=p_payload->>'service_id' and is_active=true;
 if not found or v_service.is_custom then raise exception 'บริการนี้ยังซื้อโดยตรงไม่ได้'; end if;
 v_price:=v_service.price;
 if v_service.requires_distance then v_price:=nullif(p_payload->>'quoted_price','')::integer; if v_price not in(30,50,70,100) then raise exception 'กรุณาเลือกระยะทางรับส่งใหม่'; end if; end if;
 if coalesce(btrim(p_payload->>'customer_name'),'')='' or coalesce(btrim(p_payload->>'contact'),'')='' or coalesce(btrim(p_payload->>'details'),'')='' then raise exception 'กรุณากรอกข้อมูลให้ครบ'; end if;
 select credit_balance into v_balance from profiles where id=v_user for update; if coalesce(v_balance,0)<v_price then raise exception 'เครดิตไม่เพียงพอ'; end if;
 update profiles set credit_balance=credit_balance-v_price where id=v_user;
 insert into service_orders(user_id,service_id,service_name,price,customer_name,contact,deadline,details,status) values(v_user,v_service.slug,v_service.name,v_price,btrim(p_payload->>'customer_name'),btrim(p_payload->>'contact'),nullif(p_payload->>'deadline','')::date,btrim(p_payload->>'details'),'pending') returning id into v_order;
 insert into credit_transactions(user_id,amount,transaction_type,description) values(v_user,-v_price,'purchase','ซื้อบริการ: '||v_service.name||' #'||left(v_order::text,8));
 return jsonb_build_object('order_id',v_order,'price',v_price,'remaining_balance',v_balance-v_price,'status','pending'); end $$;
grant execute on function public.purchase_service(jsonb) to authenticated;

create or replace function public.submit_custom_request(p_payload jsonb) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_user uuid:=auth.uid();v_price integer:=nullif(p_payload->>'proposed_price','')::integer;v_order uuid;v_service services%rowtype;begin
 if v_user is null then raise exception 'กรุณาเข้าสู่ระบบ'; end if;
 select * into v_service from services where slug=coalesce(p_payload->>'service_id','custom') and is_active=true and is_custom=true; if not found then raise exception 'ไม่พบบริการ Custom request ที่เปิดใช้งาน'; end if;
 if v_price is null or v_price<1 or v_price>100000 then raise exception 'ราคาเสนอต้องอยู่ระหว่าง 1–100000 บาท'; end if;
 if coalesce(btrim(p_payload->>'customer_name'),'')='' or coalesce(btrim(p_payload->>'contact'),'')='' or coalesce(btrim(p_payload->>'details'),'')='' then raise exception 'กรุณากรอกข้อมูลให้ครบ'; end if;
 insert into service_orders(user_id,service_id,service_name,price,customer_name,contact,deadline,details,status,admin_note) values(v_user,v_service.slug,v_service.name,v_price,btrim(p_payload->>'customer_name'),btrim(p_payload->>'contact'),nullif(p_payload->>'deadline','')::date,btrim(p_payload->>'details'),'pending','ราคาเสนอจากลูกค้า ยังไม่หักเครดิต') returning id into v_order;
 return jsonb_build_object('order_id',v_order,'proposed_price',v_price,'status','pending');end $$;
grant execute on function public.submit_custom_request(jsonb) to authenticated;

select pg_notify('pgrst','reload schema');
commit;
