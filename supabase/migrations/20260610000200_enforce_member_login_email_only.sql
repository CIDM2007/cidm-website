-- Enforce member login_id to be email-only and normalize existing data.

-- 1) Normalize current login IDs to company representative email where present.
update public.member
set login_id = lower(btrim(email))
where nullif(btrim(coalesce(email, '')), '') is not null
  and coalesce(login_id, '') <> lower(btrim(email));

-- 2) Ensure login_id values are email format when set.
do $$
begin
    if not exists (
        select 1
        from pg_constraint
        where conname = 'member_login_id_email_chk'
          and conrelid = 'public.member'::regclass
    ) then
        alter table public.member
            add constraint member_login_id_email_chk
            check (
                nullif(btrim(coalesce(login_id, '')), '') is null
                or lower(btrim(login_id)) ~ '^[a-z0-9.!#$%&''*+/=?^_`{|}~-]+@[a-z0-9.-]+\.[a-z]{2,}$'
            );
    end if;
end
$$;

-- 3) Admin setter: require email format and always normalize to lowercase.
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
    if v_password is not null and length(v_password) < 8 then
        raise exception 'password must be at least 8 characters';
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

-- 4) Member login: allow only login_id (email) + password.
create or replace function public.cidm_member_login(
    p_login_id text,
    p_password text
)
returns table (
    member_id uuid,
    login_id text,
    company_name text,
    staff_name text
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
    v_allowed_types_text text;
    v_allowed_types text[];
    v_allow_related boolean;
    v_allow_unset_type boolean;
    v_login_id text;
begin
    v_login_id := lower(btrim(coalesce(p_login_id, '')));
    if v_login_id = '' then
        return;
    end if;

    select nullif(btrim(s.setting_value), '')
      into v_allowed_types_text
    from public.app_settings s
    where s.setting_key = 'member_login_allowed_member_types'
    limit 1;

    if v_allowed_types_text is null then
        v_allowed_types_text := '正会員,準会員';
    end if;

    v_allowed_types := regexp_split_to_array(v_allowed_types_text, '\\s*,\\s*');

    select coalesce(lower(nullif(btrim(s.setting_value), '')) in ('1', 'true', 'yes', 'on'), false)
      into v_allow_related
    from public.app_settings s
    where s.setting_key = 'member_login_allow_related'
    limit 1;

    v_allow_related := coalesce(v_allow_related, false);

    select coalesce(lower(nullif(btrim(s.setting_value), '')) in ('1', 'true', 'yes', 'on'), false)
      into v_allow_unset_type
    from public.app_settings s
    where s.setting_key = 'member_login_allow_unset_type'
    limit 1;

    v_allow_unset_type := coalesce(v_allow_unset_type, false);

    return query
    select
        m.id,
        m.login_id,
        m.company_name,
        m.staff_name
    from public.member as m
    where lower(coalesce(m.login_id, '')) = v_login_id
      and m.password_hash is not null
      and extensions.crypt(p_password, m.password_hash) = m.password_hash
      and (
            (
                coalesce(m.division_flag, '会員') = '関係者'
                and v_allow_related
            )
            or
            (
                coalesce(m.division_flag, '会員') <> '関係者'
                and (
                    (
                        nullif(btrim(coalesce(m.member_type, '')), '') is null
                        and v_allow_unset_type
                    )
                    or
                    (
                        nullif(btrim(coalesce(m.member_type, '')), '') is not null
                        and btrim(coalesce(m.member_type, '')) = any(v_allowed_types)
                    )
                )
            )
        )
    limit 1;
end;
$$;

-- 5) Password recovery: first factor must be login_id (email) only.
create or replace function public.cidm_member_verify_recovery_identity(
    p_login_id text,
    p_registered_email text
)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
    v_login_id text;
    v_email text;
    v_exists boolean;
begin
    v_login_id := lower(btrim(coalesce(p_login_id, '')));
    v_email := lower(btrim(coalesce(p_registered_email, '')));

    if v_login_id = '' or v_email = '' then
        return false;
    end if;

    select exists (
        select 1
        from public.member m
        where lower(coalesce(m.login_id, '')) = v_login_id
          and (
                lower(coalesce(m.email, '')) = v_email
                or lower(coalesce(m.staff_email, '')) = v_email
          )
    )
    into v_exists;

    return coalesce(v_exists, false);
end;
$$;

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

    if nullif(coalesce(p_new_password, ''), '') is null or length(p_new_password) < 8 then
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

revoke all on function public.cidm_admin_set_member_login(uuid, text, text) from public;
grant execute on function public.cidm_admin_set_member_login(uuid, text, text) to authenticated;

grant execute on function public.cidm_member_login(text, text) to anon, authenticated;

grant execute on function public.cidm_member_verify_recovery_identity(text, text)
    to anon, authenticated;

grant execute on function public.cidm_member_reset_password_self_service(text, text, text)
    to anon, authenticated;
