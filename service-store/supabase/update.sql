-- ServiceStore V22.1 Bugfix migration (safe and repeatable)
begin;

-- Profile columns and avatar storage
alter table public.profiles add column if not exists nickname text;
alter table public.profiles add column if not exists avatar_url text;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('avatars','avatars',true,3145728,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=true,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists "Users upload own avatars" on storage.objects;
create policy "Users upload own avatars" on storage.objects for insert to authenticated
with check(bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists "Users update own avatars" on storage.objects;
create policy "Users update own avatars" on storage.objects for update to authenticated
using(bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text)
with check(bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists "Public read avatars" on storage.objects;
create policy "Public read avatars" on storage.objects for select using(bucket_id='avatars');

-- Ensure profiles can be edited by their owners
alter table public.profiles enable row level security;
drop policy if exists "Users update own profile" on public.profiles;
create policy "Users update own profile" on public.profiles for update to authenticated using(auth.uid()=id) with check(auth.uid()=id);
drop policy if exists "Users insert own profile" on public.profiles;
create policy "Users insert own profile" on public.profiles for insert to authenticated with check(auth.uid()=id);

-- Fix legacy order constraints and null admin notes
update public.service_orders set admin_note='' where admin_note is null;
alter table public.service_orders alter column admin_note set default '';

do $$ declare r record; begin
 for r in select con.conname from pg_constraint con join pg_class rel on rel.oid=con.conrelid join pg_namespace n on n.oid=rel.relnamespace
 where n.nspname='public' and rel.relname='service_orders' and con.contype='c' and pg_get_constraintdef(con.oid) ilike '%service_id%'
 loop execute format('alter table public.service_orders drop constraint if exists %I',r.conname); end loop;
end $$;

create or replace function public.admin_update_order_status(p_order_id uuid,p_status text,p_note text default '')
returns void language plpgsql security definer set search_path=public as $$
begin
 if not public.is_admin() then raise exception 'ไม่มีสิทธิ์แอดมิน'; end if;
 if p_status not in('pending','accepted','working','completed','cancelled') then raise exception 'สถานะไม่ถูกต้อง'; end if;
 update service_orders set status=p_status,admin_note=coalesce(p_note,'') where id=p_order_id;
 if not found then raise exception 'ไม่พบออเดอร์'; end if;
end $$;
grant execute on function public.admin_update_order_status(uuid,text,text) to authenticated;

-- Custom request compatible with all current services
create or replace function public.submit_custom_request(p_payload jsonb) returns jsonb
language plpgsql security definer set search_path=public as $$
declare v_user uuid:=auth.uid();v_price integer:=nullif(p_payload->>'proposed_price','')::integer;v_order uuid;v_service services%rowtype;
begin
 if v_user is null then raise exception 'กรุณาเข้าสู่ระบบ'; end if;
 select * into v_service from services where slug=coalesce(p_payload->>'service_id','custom') and is_active=true and (is_custom=true or slug='custom');
 if not found then raise exception 'ไม่พบบริการ Custom request ที่เปิดใช้งาน'; end if;
 if v_price is null or v_price<1 or v_price>100000 then raise exception 'ราคาเสนอต้องอยู่ระหว่าง 1–100000 บาท'; end if;
 if coalesce(btrim(p_payload->>'customer_name'),'')='' or coalesce(btrim(p_payload->>'contact'),'')='' or coalesce(btrim(p_payload->>'details'),'')='' then raise exception 'กรุณากรอกข้อมูลให้ครบ'; end if;
 insert into service_orders(user_id,service_id,service_name,price,customer_name,contact,deadline,details,status,admin_note)
 values(v_user,v_service.slug,v_service.name,v_price,btrim(p_payload->>'customer_name'),btrim(p_payload->>'contact'),nullif(p_payload->>'deadline','')::date,btrim(p_payload->>'details'),'pending','ราคาเสนอจากลูกค้า ยังไม่หักเครดิต') returning id into v_order;
 return jsonb_build_object('order_id',v_order,'proposed_price',v_price,'status','pending');
end $$;
grant execute on function public.submit_custom_request(jsonb) to authenticated;

select pg_notify('pgrst','reload schema');
commit;
