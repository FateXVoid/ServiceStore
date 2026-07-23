-- ServiceStore v20 safe migration: no user/order/credit deletion
create table if not exists public.site_settings (
  key text primary key,
  value text not null default '',
  updated_at timestamptz not null default now()
);
alter table public.site_settings enable row level security;
drop policy if exists "Public can read site settings" on public.site_settings;
create policy "Public can read site settings" on public.site_settings for select using (true);
drop policy if exists "Admins manage site settings" on public.site_settings;
create policy "Admins manage site settings" on public.site_settings for all to authenticated using (public.is_admin()) with check (public.is_admin());
grant select on public.site_settings to anon, authenticated;
grant insert, update, delete on public.site_settings to authenticated;
insert into public.site_settings(key,value) values
('site_name','FateX Service'),
('hero_title','บริการดิจิทัล'),
('hero_accent','ที่ดูดีและใช้งานได้จริง')
on conflict(key) do nothing;
select pg_notify('pgrst','reload schema');
