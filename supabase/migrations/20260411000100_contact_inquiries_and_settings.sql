create table if not exists public.contact_inquiries (
    id uuid primary key default gen_random_uuid(),
    company text,
    department text,
    name text not null,
    postal text,
    pref text,
    address text,
    phone text,
    fax text,
    email text not null,
    category text,
    message text not null,
    sent_to text,
    send_status text not null default 'pending' check (send_status in ('pending', 'sent', 'failed')),
    send_error text,
    created_at timestamptz not null default now(),
    sent_at timestamptz
);

create table if not exists public.app_settings (
    setting_key text primary key,
    setting_value text not null,
    updated_at timestamptz not null default now()
);

create or replace function public.cidm_touch_app_settings_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at := now();
    return new;
end;
$$;

drop trigger if exists trg_app_settings_updated_at on public.app_settings;
create trigger trg_app_settings_updated_at
before update on public.app_settings
for each row
execute function public.cidm_touch_app_settings_updated_at();

alter table public.contact_inquiries enable row level security;
alter table public.app_settings enable row level security;

drop policy if exists "contact_inquiries_insert_public" on public.contact_inquiries;
create policy "contact_inquiries_insert_public"
on public.contact_inquiries
for insert
to anon, authenticated
with check (true);

drop policy if exists "contact_inquiries_admin_all" on public.contact_inquiries;
create policy "contact_inquiries_admin_all"
on public.contact_inquiries
for all
to anon, authenticated
using (true)
with check (true);

drop policy if exists "app_settings_admin_all" on public.app_settings;
create policy "app_settings_admin_all"
on public.app_settings
for all
to anon, authenticated
using (true)
with check (true);

insert into public.app_settings (setting_key, setting_value)
values ('contact_to_email', 'yamamoto.yasuhiro.japan@gmail.com')
on conflict (setting_key) do nothing;
