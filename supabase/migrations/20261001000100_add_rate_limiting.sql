-- Generic rate limiting primitive for public, unauthenticated write endpoints
-- (contact form, membership application, password reset requests).
--
-- Usage: select public.cidm_check_rate_limit('submit_application:203.0.113.5', 3, 3600);
-- Returns true while the caller is still within the limit, false once the
-- limit for the current time window has been exceeded.

create table if not exists public.rate_limit_counters (
  rl_key text not null,
  window_start timestamptz not null,
  count integer not null default 0,
  updated_at timestamptz not null default now(),
  primary key (rl_key, window_start)
);

alter table public.rate_limit_counters enable row level security;
-- Intentionally no policies: only reachable through the SECURITY DEFINER
-- function below, never directly by anon/authenticated clients.

create or replace function public.cidm_check_rate_limit(
  p_key text,
  p_limit integer,
  p_window_seconds integer
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_window_start timestamptz;
  v_count integer;
begin
  if nullif(btrim(coalesce(p_key, '')), '') is null or p_limit <= 0 or p_window_seconds <= 0 then
    return true;
  end if;

  v_window_start := to_timestamp(floor(extract(epoch from now()) / p_window_seconds) * p_window_seconds);

  insert into public.rate_limit_counters (rl_key, window_start, count, updated_at)
  values (p_key, v_window_start, 1, now())
  on conflict (rl_key, window_start)
  do update set count = public.rate_limit_counters.count + 1, updated_at = now()
  returning count into v_count;

  return v_count <= p_limit;
end;
$$;

revoke all on function public.cidm_check_rate_limit(text, integer, integer) from public;
grant execute on function public.cidm_check_rate_limit(text, integer, integer) to anon, authenticated;

-- Opportunistic cleanup of old buckets; safe to call repeatedly, cheap once
-- the table is small. Not scheduled automatically (no pg_cron assumed) --
-- can be run manually or wired into a scheduled job later.
create or replace function public.cidm_cleanup_rate_limit_counters()
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.rate_limit_counters where window_start < now() - interval '2 days';
$$;

revoke all on function public.cidm_cleanup_rate_limit_counters() from public;
