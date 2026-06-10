-- Allow admins to configure who can log in to member portal.
-- Stored in app_settings:
--   member_login_allowed_member_types: CSV of member.member_type values
--   member_login_allow_related: true/false
--   member_login_allow_unset_type: true/false

insert into public.app_settings (setting_key, setting_value)
values
  ('member_login_allowed_member_types', '正会員,準会員'),
  ('member_login_allow_related', 'false'),
  ('member_login_allow_unset_type', 'false')
on conflict (setting_key) do nothing;

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
begin
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
    where (
            lower(m.login_id) = lower(btrim(p_login_id))
            or lower(m.email) = lower(btrim(p_login_id))
            or lower(m.staff_email) = lower(btrim(p_login_id))
        )
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

grant execute on function public.cidm_member_login(text, text) to anon, authenticated;
