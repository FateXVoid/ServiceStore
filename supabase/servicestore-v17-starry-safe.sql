-- ServiceStore v17 Starry safe patch: no DELETE/TRUNCATE/DROP TABLE
create extension if not exists pgcrypto;
alter table if exists public.topup_requests add column if not exists admin_note text;
alter table if exists public.withdrawal_requests add column if not exists admin_note text;
alter table if exists public.service_orders add column if not exists admin_note text;
alter table if exists public.services add column if not exists slug text;
alter table if exists public.services add column if not exists is_active boolean not null default true;
alter table if exists public.services add column if not exists sort_order integer not null default 0;
alter table if exists public.services add column if not exists updated_at timestamptz not null default now();
update public.services set slug=coalesce(nullif(slug,''),'service-'||substr(id::text,1,8)) where slug is null or slug='';
create unique index if not exists services_slug_v17_unique on public.services(slug);
grant select on public.services to anon,authenticated;
select pg_notify('pgrst','reload schema');
