-- Member password reset workflow
-- 1) request: edge function generates token and stores hashed token
-- 2) reset: this SQL function validates token and updates password hash

create table if not exists public.member_password_reset_tokens (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.member(id) on delete cascade,
  token_hash text not null,
  expires_at timestamptz not null,
  used_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists idx_member_password_reset_tokens_member_id
  on public.member_password_reset_tokens(member_id);

create index if not exists idx_member_password_reset_tokens_expires_at
  on public.member_password_reset_tokens(expires_at);

create unique index if not exists uq_member_password_reset_tokens_token_hash
  on public.member_password_reset_tokens(token_hash);

create or replace function public.cidm_consume_member_password_reset(
  p_token_hash text,
  p_new_password text
)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_token public.member_password_reset_tokens%rowtype;
begin
  if nullif(btrim(coalesce(p_token_hash, '')), '') is null then
    return false;
  end if;

  if nullif(coalesce(p_new_password, ''), '') is null or length(p_new_password) < 8 then
    return false;
  end if;

  select *
    into v_token
  from public.member_password_reset_tokens
  where token_hash = p_token_hash
    and used_at is null
    and expires_at > now()
  order by created_at desc
  limit 1
  for update;

  if not found then
    return false;
  end if;

  update public.member
  set
    password_hash = extensions.crypt(p_new_password, extensions.gen_salt('bf')),
    password_updated_at = now()
  where id = v_token.member_id;

  if not found then
    return false;
  end if;

  update public.member_password_reset_tokens
  set used_at = now()
  where id = v_token.id;

  return true;
end;
$$;

grant execute on function public.cidm_consume_member_password_reset(text, text)
  to anon, authenticated;
