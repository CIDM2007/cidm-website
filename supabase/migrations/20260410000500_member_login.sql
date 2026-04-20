-- CIDM member login management
-- Apply from Supabase SQL Editor if CLI cannot access the project.

create extension if not exists pgcrypto with schema extensions;

alter table if exists public.member
    add column if not exists login_id text,
    add column if not exists password_hash text,
    add column if not exists password_updated_at timestamptz;

create unique index if not exists member_login_id_unique_idx
    on public.member (lower(login_id))
    where login_id is not null and btrim(login_id) <> '';

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
begin
    return query
    select
        m.id,
        m.login_id,
        m.company_name,
        m.staff_name
    from public.member as m
    where (
            lower(m.login_id) = lower(btrim(p_login_id))
            or lower(m.email) = lower(btrim(p_login_id))
                        or lower(m.staff_email) = lower(btrim(p_login_id))
        )
      and m.password_hash is not null
      and extensions.crypt(p_password, m.password_hash) = m.password_hash
    limit 1;
end;
$$;

create or replace function public.cidm_get_member_login_settings(
    p_member_id uuid
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
begin
    if not coalesce(public.cidm_is_admin(), false) then
        raise exception 'admin access required';
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

    v_login_id := nullif(btrim(p_login_id), '');
    if v_login_id is null then
        raise exception 'login id is required';
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

revoke all on function public.cidm_member_login(text, text) from public;
grant execute on function public.cidm_member_login(text, text) to anon, authenticated;

revoke all on function public.cidm_get_member_login_settings(uuid) from public;
grant execute on function public.cidm_get_member_login_settings(uuid) to authenticated;

revoke all on function public.cidm_admin_set_member_login(uuid, text, text) from public;
grant execute on function public.cidm_admin_set_member_login(uuid, text, text) to authenticated;