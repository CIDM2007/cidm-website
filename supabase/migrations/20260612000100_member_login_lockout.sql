-- Member login lockout policy:
-- lock the account for 1 hour after 5 consecutive failed attempts.

alter table if exists public.member
    add column if not exists failed_login_attempts integer not null default 0,
    add column if not exists login_locked_until timestamptz,
    add column if not exists last_failed_login_at timestamptz;

create index if not exists idx_member_login_locked_until
    on public.member (login_locked_until)
    where login_locked_until is not null;

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
    v_member public.member%rowtype;
    v_member_type text;
    v_eligible boolean;
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

    select m.*
      into v_member
    from public.member m
    where lower(coalesce(m.login_id, '')) = v_login_id
    limit 1
    for update;

    if v_member.id is null then
        return;
    end if;

    if v_member.login_locked_until is not null and v_member.login_locked_until > now() then
        raise exception 'account temporarily locked';
    end if;

    if v_member.password_hash is null
       or extensions.crypt(p_password, v_member.password_hash) <> v_member.password_hash then
        update public.member m
           set failed_login_attempts = coalesce(m.failed_login_attempts, 0) + 1,
               last_failed_login_at = now(),
               login_locked_until = case
                   when coalesce(m.failed_login_attempts, 0) + 1 >= 5
                       then now() + interval '1 hour'
                   else m.login_locked_until
               end
         where m.id = v_member.id;
        return;
    end if;

    v_member_type := btrim(coalesce(v_member.member_type, ''));

    if coalesce(v_member.division_flag, '会員') = '関係者' then
        v_eligible := v_allow_related;
    else
        v_eligible := (
            (v_allow_officer and coalesce(v_member.is_officer, false))
            or (v_member_type = '' and v_allow_unset_type)
            or (v_member_type <> '' and v_member_type = any(v_allowed_types))
        );
    end if;

    if not coalesce(v_eligible, false) then
        return;
    end if;

    update public.member m
       set failed_login_attempts = 0,
           last_failed_login_at = null,
           login_locked_until = null
     where m.id = v_member.id;

    return query
    select
        v_member.id,
        v_member.login_id,
        v_member.company_name,
        v_member.staff_name;
end;
$$;

grant execute on function public.cidm_member_login(text, text) to anon, authenticated;
