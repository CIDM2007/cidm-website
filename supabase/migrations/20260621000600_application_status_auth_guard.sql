begin;

drop function if exists public.cidm_staff_login(text, text);

create or replace function public.cidm_staff_login(
    p_login_id text,
    p_password text
)
returns table (
    staff_id uuid,
    contact_id uuid,
    member_id uuid,
    staff_name text,
    company_name text,
    member_type text,
    login_id text
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
    v_auth_id uuid;
    v_password_hash text;
begin
    select id, password_hash
      into v_auth_id, v_password_hash
    from public.member_staff_auth
    where lower(login_id) = lower(btrim(p_login_id))
      and is_active = true
      and password_hash is not null
    limit 1;

    if v_auth_id is null then
        raise exception 'Invalid credentials';
    end if;

    if not (extensions.crypt(p_password, v_password_hash) = v_password_hash) then
        raise exception 'Invalid credentials';
    end if;

    return query
    select
        msa.id as staff_id,
        mc.id as contact_id,
        m.id as member_id,
        mc.name as staff_name,
        m.company_name,
        m.member_type,
        msa.login_id
    from public.member_staff_auth msa
    join public.member_contacts mc on msa.contact_id = mc.id
    join public.member m on mc.member_id = m.id
    where msa.id = v_auth_id
      and coalesce(m.application_status, '承認済') = '承認済'
    limit 1;

    if not found then
        raise exception 'Application not approved';
    end if;
end;
$$;

comment on function public.cidm_staff_login(text, text) is '担当者用ログイン認証。承認済の担当者のみログイン成功とする。';

drop function if exists public.cidm_admin_create_contact_invite(uuid, text, interval, text);

create or replace function public.cidm_admin_create_contact_invite(
  p_contact_id uuid,
  p_token_hash text,
  p_expires_in interval default interval '72 hours',
  p_token_type text default 'invite'
)
returns table (
  contact_id uuid,
  contact_name text,
  contact_email text,
  expires_at timestamptz
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_expires_at timestamptz;
begin
  if not coalesce(public.cidm_is_admin(), false) then
    raise exception 'admin access required';
  end if;

  if nullif(btrim(p_token_hash), '') is null then
    raise exception 'token_hash is required';
  end if;

  if not exists (
    select 1
    from public.member_contacts mc
    join public.member m on m.id = mc.member_id
    where mc.id = p_contact_id
      and coalesce(m.application_status, '承認済') = '承認済'
  ) then
    raise exception 'contact not found or member not approved';
  end if;

  v_expires_at := now() + p_expires_in;

  update public.contact_password_reset_tokens
  set used_at = now()
  where contact_id = p_contact_id
    and used_at is null;

  insert into public.contact_password_reset_tokens
    (contact_id, token_hash, expires_at, token_type)
  values
    (p_contact_id, p_token_hash, v_expires_at, p_token_type);

  return query
  select
    mc.id,
    mc.name,
    mc.email,
    v_expires_at
  from public.member_contacts mc
  where mc.id = p_contact_id;
end;
$$;

comment on function public.cidm_admin_create_contact_invite(uuid, text, interval, text) is
  '管理者が承認済の担当者に招待またはパスワードリセットトークンを発行する。';

drop function if exists public.cidm_consume_contact_password_reset(text, text);

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

  if nullif(coalesce(p_new_password, ''), '') is null or length(p_new_password) < 8 then
    return jsonb_build_object('ok', false, 'error', 'password must be at least 8 characters');
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

comment on function public.cidm_consume_contact_password_reset(text, text) is
  '担当者が承認済会員のトークンを使ってパスワードを設定する。';

grant execute on function public.cidm_consume_contact_password_reset(text, text)
  to anon, authenticated;

drop function if exists public.cidm_request_contact_password_reset(text, text, interval);

create or replace function public.cidm_request_contact_password_reset(
  p_login_id text,
  p_token_hash text,
  p_expires_in interval default interval '1 hour'
)
returns table (
  contact_id uuid,
  contact_email text
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_contact_id uuid;
  v_email text;
begin
  select msa.contact_id, mc.email
    into v_contact_id, v_email
  from public.member_staff_auth msa
  join public.member_contacts mc on mc.id = msa.contact_id
  join public.member m on m.id = mc.member_id
  where lower(msa.login_id) = lower(btrim(p_login_id))
    and msa.is_active = true
    and coalesce(m.application_status, '承認済') = '承認済'
  limit 1;

  if v_contact_id is null then
    return;
  end if;

  update public.contact_password_reset_tokens
  set used_at = now()
  where contact_id = v_contact_id
    and used_at is null;

  insert into public.contact_password_reset_tokens
    (contact_id, token_hash, expires_at, token_type)
  values
    (v_contact_id, p_token_hash, now() + p_expires_in, 'reset');

  return query select v_contact_id, v_email;
end;
$$;

grant execute on function public.cidm_request_contact_password_reset(text, text, interval)
  to anon, authenticated;

commit;