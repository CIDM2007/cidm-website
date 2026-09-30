-- Strengthen password policy from "8+ characters, no complexity" to
-- "12+ characters, must include uppercase, lowercase and a number"
-- across every RPC that sets a member/staff/admin password.

create or replace function public.cidm_is_strong_password(p_password text)
returns boolean
language sql
immutable
set search_path = public
as $$
  select p_password is not null
     and length(p_password) >= 12
     and p_password ~ '[A-Z]'
     and p_password ~ '[a-z]'
     and p_password ~ '[0-9]';
$$;

-- 1) Admin setter for a member's login/password.
create or replace function public.cidm_admin_set_member_login(
    p_member_id uuid,
    p_login_id text,
    p_password text default null
)
returns table (
    login_id text,
    has_password boolean,
    password_updated_at timestamptz
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
    v_login_id text;
    v_password text;
begin
    if not coalesce(public.cidm_is_admin(), false) then
        raise exception 'admin access required';
    end if;

    v_login_id := lower(nullif(btrim(p_login_id), ''));
    if v_login_id is null then
        raise exception 'login id is required';
    end if;
    if v_login_id !~ '^[a-z0-9.!#$%&''*+/=?^_`{|}~-]+@[a-z0-9.-]+\.[a-z]{2,}$' then
        raise exception 'login id must be a valid email address';
    end if;

    v_password := nullif(coalesce(p_password, ''), '');
    if v_password is not null and not public.cidm_is_strong_password(v_password) then
        raise exception 'password must be at least 12 characters and include uppercase, lowercase and a number';
    end if;

    update public.member as m
    set login_id = v_login_id,
        password_hash = case
            when v_password is not null then extensions.crypt(v_password, extensions.gen_salt('bf'))
            else m.password_hash
        end,
        password_updated_at = case
            when v_password is not null then now()
            else m.password_updated_at
        end
    where m.id = p_member_id;

    if not found then
        raise exception 'member not found';
    end if;

    return query
    select
        m.login_id,
        m.password_hash is not null,
        m.password_updated_at
    from public.member as m
    where m.id = p_member_id;
end;
$$;

-- 2) Member self-service password reset (recovery via registered email).
create or replace function public.cidm_member_reset_password_self_service(
    p_login_id text,
    p_registered_email text,
    p_new_password text
)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
    v_login_id text;
    v_email text;
    v_member_id uuid;
begin
    v_login_id := lower(btrim(coalesce(p_login_id, '')));
    v_email := lower(btrim(coalesce(p_registered_email, '')));

    if v_login_id = '' or v_email = '' then
        return false;
    end if;

    if not public.cidm_is_strong_password(p_new_password) then
        return false;
    end if;

    select m.id
      into v_member_id
    from public.member m
    where lower(coalesce(m.login_id, '')) = v_login_id
      and (
            lower(coalesce(m.email, '')) = v_email
            or lower(coalesce(m.staff_email, '')) = v_email
      )
    limit 1;

    if v_member_id is null then
        return false;
    end if;

    update public.member
    set
        password_hash = extensions.crypt(p_new_password, extensions.gen_salt('bf')),
        password_updated_at = now()
    where id = v_member_id;

    return found;
end;
$$;

-- 3) Member password reset via one-time email URL (legacy member token).
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

  if not public.cidm_is_strong_password(p_new_password) then
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
    password_updated_at = now(),
    failed_login_attempts = 0,
    login_locked_until = null,
    last_failed_login_at = null
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

-- 4) Contact (staff) password reset via one-time invite/reset token.
create or replace function public.cidm_consume_contact_password_reset(
  p_token_hash text,
  p_new_password text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_token public.contact_password_reset_tokens%rowtype;
  v_email text;
  v_application_status text;
begin
  if nullif(btrim(coalesce(p_token_hash, '')), '') is null then
    return jsonb_build_object('ok', false, 'error', 'token is required');
  end if;

  if not public.cidm_is_strong_password(p_new_password) then
    return jsonb_build_object('ok', false, 'error', 'password must be at least 12 characters and include uppercase, lowercase and a number');
  end if;

  select *
    into v_token
  from public.contact_password_reset_tokens
  where token_hash = p_token_hash
    and used_at is null
    and expires_at > now()
  order by created_at desc
  limit 1
  for update;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'invalid or expired token');
  end if;

  select mc.email, coalesce(m.application_status, '承認済')
    into v_email, v_application_status
  from public.member_contacts mc
  join public.member m on m.id = mc.member_id
  where mc.id = v_token.contact_id;

  if v_email is null or btrim(v_email) = '' then
    return jsonb_build_object('ok', false, 'error', 'contact email not found');
  end if;

  if v_application_status <> '承認済' then
    return jsonb_build_object('ok', false, 'error', 'member application is not approved');
  end if;

  insert into public.member_staff_auth
    (contact_id, login_id, password_hash, is_active, updated_at)
  values
    (v_token.contact_id, lower(btrim(v_email)),
     extensions.crypt(p_new_password, extensions.gen_salt('bf')), true, now())
  on conflict (contact_id) do update
  set
    login_id = lower(btrim(v_email)),
    password_hash = extensions.crypt(p_new_password, extensions.gen_salt('bf')),
    is_active = true,
    updated_at = now();

  update public.contact_password_reset_tokens
  set used_at = now()
  where id = v_token.id;

  return jsonb_build_object('ok', true);
end;
$$;
