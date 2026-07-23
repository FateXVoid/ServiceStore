-- ServiceStore V.21 safe migration
-- ไม่ลบผู้ใช้ เครดิต ออเดอร์ หรือประวัติเดิม

begin;

-- แก้ HTTP 400 ตอนอัปเดตโปรไฟล์ โดยรับประกันว่าคอลัมน์ที่หน้าเว็บใช้มีอยู่
alter table if exists public.profiles add column if not exists nickname text;
alter table if exists public.profiles add column if not exists avatar_url text;

-- เพิ่มบริการที่เหมาะกับนักเรียน ม.ปลาย และปรับบริการรับส่ง
insert into public.services (slug,name,description,price,is_active,sort_order)
values
  ('delivery','รับส่งของภายในตัวเมือง','รับของจากจุดหนึ่งไปส่งอีกจุดภายในตัวเมือง ราคา 30–100 บาทตามระยะทาง',30,true,20),
  ('presentation','ออกแบบสไลด์นำเสนอ','จัดสไลด์รายงาน โครงงาน หรือพรีเซนต์หน้าชั้นจากเนื้อหาที่ลูกค้าเตรียมไว้',149,true,30),
  ('poster','ออกแบบโปสเตอร์และโพสต์','ออกแบบโปสเตอร์กิจกรรมโรงเรียน ป้ายประชาสัมพันธ์ และภาพโพสต์โซเชียล',99,true,40),
  ('document','จัดรูปแบบรายงานและเอกสาร','จัดหน้าปก สารบัญ เลขหน้า ฟอนต์ และระยะขอบจากเนื้อหาที่ลูกค้าเตรียมไว้',79,true,50),
  ('custom','บริการสั่งทำพิเศษ','ส่งรายละเอียดพร้อมราคาเสนอเพื่อให้แอดมินตรวจและติดต่อกลับก่อนเริ่มงาน',1,true,90)
on conflict (slug) do update set
  name=excluded.name,
  description=excluded.description,
  price=excluded.price,
  is_active=excluded.is_active,
  sort_order=excluded.sort_order;

-- ซื้อบริการราคาคงที่ และรองรับค่ารับส่ง 30/50/70/100 ตามระยะทาง
create or replace function public.purchase_service(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_service text := p_payload->>'service_id';
  v_name text;
  v_price integer;
  v_requested_price integer := nullif(p_payload->>'quoted_price','')::integer;
  v_balance integer;
  v_order uuid;
begin
  if v_user is null then raise exception 'กรุณาเข้าสู่ระบบ'; end if;

  case v_service
    when 'portfolio' then v_name := 'รับทำ Portfolio'; v_price := 499;
    when 'presentation' then v_name := 'ออกแบบสไลด์นำเสนอ'; v_price := 149;
    when 'poster' then v_name := 'ออกแบบโปสเตอร์และโพสต์'; v_price := 99;
    when 'document' then v_name := 'จัดรูปแบบรายงานและเอกสาร'; v_price := 79;
    when 'delivery' then
      v_name := 'รับส่งของภายในตัวเมือง';
      if v_requested_price not in (30,50,70,100) then raise exception 'กรุณาเลือกระยะทางรับส่งใหม่'; end if;
      v_price := v_requested_price;
    else raise exception 'บริการนี้ยังซื้อโดยตรงไม่ได้';
  end case;

  if coalesce(trim(p_payload->>'customer_name'),'') = ''
     or coalesce(trim(p_payload->>'contact'),'') = ''
     or coalesce(trim(p_payload->>'details'),'') = '' then
    raise exception 'กรุณากรอกข้อมูลให้ครบ';
  end if;

  select credit_balance into v_balance from public.profiles where id=v_user for update;
  if v_balance is null then raise exception 'ไม่พบกระเป๋าเครดิต'; end if;
  if v_balance < v_price then raise exception 'เครดิตไม่เพียงพอ'; end if;

  update public.profiles set credit_balance=credit_balance-v_price where id=v_user;
  insert into public.service_orders(user_id,service_id,service_name,price,customer_name,contact,deadline,details)
  values(v_user,v_service,v_name,v_price,trim(p_payload->>'customer_name'),trim(p_payload->>'contact'),nullif(p_payload->>'deadline','')::date,trim(p_payload->>'details'))
  returning id into v_order;

  insert into public.credit_transactions(user_id,amount,transaction_type,description)
  values(v_user,-v_price,'purchase','ซื้อบริการ: '||v_name||' #'||left(v_order::text,8));

  return jsonb_build_object('order_id',v_order,'price',v_price,'remaining_balance',v_balance-v_price,'status','pending');
end;$$;
revoke all on function public.purchase_service(jsonb) from public;
grant execute on function public.purchase_service(jsonb) to authenticated;

-- Custom request: บันทึกราคาเสนอ แต่ยังไม่หักเครดิต
create or replace function public.submit_custom_request(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_price integer := nullif(p_payload->>'proposed_price','')::integer;
  v_order uuid;
begin
  if v_user is null then raise exception 'กรุณาเข้าสู่ระบบ'; end if;
  if v_price is null or v_price < 1 or v_price > 100000 then raise exception 'ราคาเสนอต้องอยู่ระหว่าง 1–100000 บาท'; end if;
  if coalesce(trim(p_payload->>'customer_name'),'') = ''
     or coalesce(trim(p_payload->>'contact'),'') = ''
     or coalesce(trim(p_payload->>'details'),'') = '' then
    raise exception 'กรุณากรอกข้อมูลให้ครบ';
  end if;

  insert into public.service_orders(user_id,service_id,service_name,price,customer_name,contact,deadline,details,status,admin_note)
  values(v_user,'custom','บริการสั่งทำพิเศษ',v_price,trim(p_payload->>'customer_name'),trim(p_payload->>'contact'),nullif(p_payload->>'deadline','')::date,trim(p_payload->>'details'),'pending','ราคาเสนอจากลูกค้า ยังไม่หักเครดิต')
  returning id into v_order;

  return jsonb_build_object('order_id',v_order,'proposed_price',v_price,'status','pending');
end;$$;
revoke all on function public.submit_custom_request(jsonb) from public;
grant execute on function public.submit_custom_request(jsonb) to authenticated;

select pg_notify('pgrst','reload schema');
commit;
