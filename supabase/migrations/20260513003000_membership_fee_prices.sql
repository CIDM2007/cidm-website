create table if not exists public.membership_fee_prices (
    fee_category text primary key,
    amount integer not null default 0 check (amount >= 0),
    updated_at timestamptz not null default now(),
    check (fee_category in ('正会員', '準会員', '賛助会員'))
);

create or replace function public.cidm_touch_membership_fee_prices_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at := now();
    return new;
end;
$$;

drop trigger if exists trg_membership_fee_prices_updated_at on public.membership_fee_prices;
create trigger trg_membership_fee_prices_updated_at
before update on public.membership_fee_prices
for each row
execute function public.cidm_touch_membership_fee_prices_updated_at();

alter table public.membership_fee_prices enable row level security;

drop policy if exists "membership_fee_prices_admin_all" on public.membership_fee_prices;
create policy "membership_fee_prices_admin_all"
on public.membership_fee_prices
for all
to authenticated
using (public.cidm_is_admin())
with check (public.cidm_is_admin());

insert into public.membership_fee_prices (fee_category, amount)
values
    ('正会員', 0),
    ('準会員', 0),
    ('賛助会員', 0)
on conflict (fee_category) do nothing;
