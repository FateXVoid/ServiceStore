-- FateX Service Store v13: marketplace orders + atomic credit payment
create table if not exists public.service_orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  service_id text not null check (service_id in ('portfolio','delivery')),
  service_name text not null,
  price integer not null check (price > 0),
  customer_name text not null,
  contact text not null,
  deadline date,
  details text not null,
  status text not null default 'pending' check (status in ('pending','accepted','working','completed','cancelled')),
  admin_note text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.service_orders enable row level security;
drop policy if exists "users read own orders" on public.service_orders;
create policy "users read own orders" on public.service_orders for select to authenticated using (user_id = auth.uid() or public.is_admin());
drop policy if exists "admins update orders" on public.service_orders;
create policy "admins update orders" on public.service_orders for update to authenticated using (public.is_admin()) with check (public.is_admin());

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
  v_balance integer;
  v_order uuid;
begin
  if v_user is null then raise exception 'กรุณาเข้าสู่ระบบ'; end if;
  case v_service
    when 'portfolio' then v_name := 'รับทำ Portfolio'; v_price := 499;
    when 'delivery' then v_name := 'รับส่งของหรือสินค้า'; v_price := 99;
    else raise exception 'บริการนี้ยังซื้อโดยตรงไม่ได้';
  end case;
  if coalesce(trim(p_payload->>'customer_name'),'') = '' or coalesce(trim(p_payload->>'contact'),'') = '' or coalesce(trim(p_payload->>'details'),'') = '' then
    raise exception 'กรุณากรอกข้อมูลให้ครบ';
  end if;
  select credit_balance into v_balance from public.profiles where id=v_user for update;
  if v_balance is null then raise exception 'ไม่พบกระเป๋าเครดิต'; end if;
  if v_balance < v_price then raise exception 'เครดิตไม่เพียงพอ'; end if;
  update public.profiles set credit_balance=credit_balance-v_price where id=v_user;
  insert into public.service_orders(user_id,service_id,service_name,price,customer_name,contact,deadline,details)
  values(v_user,v_service,v_name,v_price,trim(p_payload->>'customer_name'),trim(p_payload->>'contact'),nullif(p_payload->>'deadline','')::date,trim(p_payload->>'details')) returning id into v_order;
  insert into public.credit_transactions(user_id,amount,transaction_type,description)
  values(v_user,-v_price,'purchase','ซื้อบริการ: '||v_name||' #'||left(v_order::text,8));
  return jsonb_build_object('order_id',v_order,'price',v_price,'remaining_balance',v_balance-v_price,'status','pending');
end;$$;
revoke all on function public.purchase_service(jsonb) from public;
grant execute on function public.purchase_service(jsonb) to authenticated;

create or replace function public.admin_update_order_status(p_order_id uuid,p_status text,p_note text default '')
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.is_admin() then raise exception 'Admin only'; end if;
  if p_status not in ('pending','accepted','working','completed','cancelled') then raise exception 'Invalid status'; end if;
  update public.service_orders set status=p_status,admin_note=coalesce(p_note,''),updated_at=now() where id=p_order_id;
  if not found then raise exception 'Order not found'; end if;
end;$$;
revoke all on function public.admin_update_order_status(uuid,text,text) from public;
grant execute on function public.admin_update_order_status(uuid,text,text) to authenticated;

grant select on public.service_orders to authenticated;
