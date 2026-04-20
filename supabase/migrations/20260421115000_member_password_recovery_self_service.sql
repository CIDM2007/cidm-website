-- Self-service member password recovery
-- Flow:
-- 1) verify identity by login id + registered email
-- 2) set new password when verified

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
        where (
            lower(coalesce(m.login_id, '')) = v_login_id
            or lower(coalesce(m.email, '')) = v_login_id
            or lower(coalesce(m.staff_email, '')) = v_login_id
        )
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
    where (
        lower(coalesce(m.login_id, '')) = v_login_id
        or lower(coalesce(m.email, '')) = v_login_id
        or lower(coalesce(m.staff_email, '')) = v_login_id
    )
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

grant execute on function public.cidm_member_verify_recovery_identity(text, text)
    to anon, authenticated;

grant execute on function public.cidm_member_reset_password_self_service(text, text, text)
    to anon, authenticated;
