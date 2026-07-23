-- ServiceStore V23 Live Control migration (safe, rerunnable)
begin;

alter table public.services add column if not exists price_min integer;
alter table public.services add column if not exists price_max integer;
alter table public.services add column if not exists price_mode text not null default 'fixed';
update public.services set price_min=coalesce(price_min,price,0), price_max=coalesce(price_max,price_min,price,0);
alter table public.services drop constraint if exists services_price_mode_check;
alter table public.services add constraint services_price_mode_check check(price_mode in ('fixed','range','quote')) not valid;
update public.services set price_mode='quote' where is_custom=true or slug='custom';
update public.services set price_mode='range',price_min=30,price_max=100,price=30 where slug='delivery';

-- รวมรายการซ้ำเข้ารหัสมาตรฐาน แล้วลบแถวซ้ำที่แก้ไขไม่ได้
update public.services set slug='portfolio' where slug in ('รับทำ-portfolio','รับทำportfolio') and not exists(select 1 from public.services s2 where s2.slug='portfolio');
delete from public.services a using public.services b where a.slug=b.slug and a.id::text>b.id::text;
delete from public.services d where d.slug in ('รับทำ-portfolio','รับทำportfolio','รับส่งสินค้า') and exists(select 1 from public.services s2 where s2.slug=case when d.slug like '%portfolio%' then 'portfolio' else 'delivery' end);
create unique index if not exists services_slug_unique on public.services(slug);

create table if not exists public.contact_messages(
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade, sender_name text not null, reply_contact text not null, message text not null, status text not null default 'pending', admin_reply text not null default '', admin_note text not null default '', answered_at timestamptz, created_at timestamptz not null default now()
);
alter table public.contact_messages enable row level security;
drop policy if exists "Users create contact messages" on public.contact_messages;
create policy "Users create contact messages" on public.contact_messages for insert to authenticated with check(auth.uid()=user_id);
drop policy if exists "Users read own contact messages" on public.contact_messages;
create policy "Users read own contact messages" on public.contact_messages for select to authenticated using(auth.uid()=user_id or public.is_admin());
drop policy if exists "Admins update contact messages" on public.contact_messages;
create policy "Admins update contact messages" on public.contact_messages for update to authenticated using(public.is_admin()) with check(public.is_admin());
grant select,insert,update on public.contact_messages to authenticated;

create or replace function public.admin_save_service(p_id uuid,p_slug text,p_name text,p_description text,p_price integer,p_is_active boolean,p_sort_order integer,p_icon text default '✨',p_badge text default '',p_price_label text default '/ งาน',p_requires_distance boolean default false,p_is_custom boolean default false,p_price_min integer default null,p_price_max integer default null,p_price_mode text default 'fixed') returns uuid language plpgsql security definer set search_path=public as $$ declare saved_id uuid; mn integer:=coalesce(p_price_min,p_price,0); mx integer:=coalesce(p_price_max,mn); begin if not public.is_admin() then raise exception 'ไม่มีสิทธิ์แอดมิน'; end if; if p_slug!~'^[a-z0-9-]+$' or btrim(p_name)='' or p_price_mode not in('fixed','range','quote') or (p_price_mode<>'quote' and (mn<1 or mx<mn)) then raise exception 'ข้อมูลบริการไม่ถูกต้อง'; end if; if p_id is null then insert into public.services(slug,name,description,price,price_min,price_max,price_mode,is_active,sort_order,icon,badge,price_label,requires_distance,is_custom,updated_at) values(p_slug,p_name,p_description,mn,mn,mx,p_price_mode,p_is_active,p_sort_order,p_icon,p_badge,p_price_label,p_requires_distance,p_is_custom,now()) returning id into saved_id; else update public.services set slug=p_slug,name=p_name,description=p_description,price=mn,price_min=mn,price_max=mx,price_mode=p_price_mode,is_active=p_is_active,sort_order=p_sort_order,icon=p_icon,badge=p_badge,price_label=p_price_label,requires_distance=p_requires_distance,is_custom=p_is_custom,updated_at=now() where id=p_id returning id into saved_id; end if; return saved_id; end $$;
grant execute on function public.admin_save_service(uuid,text,text,text,integer,boolean,integer,text,text,text,boolean,boolean,integer,integer,text) to authenticated;

do $$ begin
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='services') then alter publication supabase_realtime add table public.services; end if;
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='announcements') then alter publication supabase_realtime add table public.announcements; end if;
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='site_settings') then alter publication supabase_realtime add table public.site_settings; end if;
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='contact_messages') then alter publication supabase_realtime add table public.contact_messages; end if;
end $$;
select pg_notify('pgrst','reload schema');
commit;
