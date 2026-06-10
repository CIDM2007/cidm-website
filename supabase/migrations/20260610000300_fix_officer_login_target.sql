-- Fix member login eligibility for officers.
-- The admin setting "役員" should include members flagged by is_officer,
-- not only rows where member_type = '役員'.

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
    v_allow_officer boolean;
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
    v_allow_officer := '役員' = any(v_allowed_types);

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
                        v_allow_officer
                        and coalesce(m.is_officer, false)
                    )
                    or
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

grant execute on function public.cidm_member_login(text, text) to anon, authenticated;
