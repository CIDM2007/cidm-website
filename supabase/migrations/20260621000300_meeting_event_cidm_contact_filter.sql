-- ============================================================
-- 会議イベント対象条件: CIDM役職フィルタを CIDM担当者フラグ対応へ橋渡し
-- 互換方針:
--   p_cidm_roles = ARRAY['CIDM担当者'] を新設計のフラグ条件として扱う
-- ============================================================

CREATE OR REPLACE FUNCTION public.cidm_create_meeting_event(
    p_event_name text,
    p_event_description text,
    p_starts_at timestamptz,
    p_location_info text,
    p_target_scope text,
    p_target_note text default null,
    p_target_mode text default 'scope',
    p_member_ids uuid[] default null,
    p_division_flags text[] default null,
    p_member_types text[] default null,
    p_cidm_roles text[] default null,
    p_invite_mail_body text default null,
    p_delivery_mode text default 'rsvp'
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
    v_event_id uuid;
    v_mode text;
    v_scope text;
    v_delivery_mode text;
    v_require_cidm_contact boolean;
    v_cidm_roles text[];
begin
    if not coalesce(public.cidm_is_admin(), false) then
        raise exception 'admin only';
    end if;

    if nullif(btrim(p_event_name), '') is null then
        raise exception 'event name is required';
    end if;

    if p_starts_at is null and coalesce(nullif(btrim(p_delivery_mode), ''), 'rsvp') <> 'notice' then
        raise exception 'starts_at is required';
    end if;

    v_mode := coalesce(nullif(btrim(p_target_mode), ''), 'scope');
    v_scope := coalesce(nullif(btrim(p_target_scope), ''), '全員');
    v_delivery_mode := coalesce(nullif(btrim(p_delivery_mode), ''), 'rsvp');
    v_require_cidm_contact := coalesce(array_position(coalesce(p_cidm_roles, '{}'::text[]), 'CIDM担当者') is not null, false);
    v_cidm_roles := array(
        select role_name
        from unnest(coalesce(p_cidm_roles, '{}'::text[])) as role_name
        where role_name <> 'CIDM担当者'
    );

    if v_mode not in ('scope', 'manual', 'filter') then
        raise exception 'invalid target mode';
    end if;

    if v_delivery_mode not in ('rsvp', 'notice') then
        raise exception 'invalid delivery mode';
    end if;

    if v_mode = 'scope' and v_scope not in ('全員', '会員', '関係者', '正会員', '準会員', '賛助会員') then
        raise exception 'invalid target scope';
    end if;

    if v_mode = 'manual' then
        v_scope := '個別選択';
        if coalesce(array_length(p_member_ids, 1), 0) = 0 then
            raise exception 'member ids are required for manual mode';
        end if;
    elsif v_mode = 'filter' then
        v_scope := '条件指定';
        if coalesce(array_length(p_division_flags, 1), 0) = 0
           and coalesce(array_length(p_member_types, 1), 0) = 0
           and coalesce(array_length(v_cidm_roles, 1), 0) = 0
           and not v_require_cidm_contact then
            raise exception 'at least one filter is required';
        end if;
    end if;

    insert into public.meeting_events (
        event_name,
        event_description,
        starts_at,
        location_info,
        target_scope,
        target_note,
        invite_mail_body,
        delivery_mode
    ) values (
        btrim(p_event_name),
        nullif(btrim(p_event_description), ''),
        p_starts_at,
        nullif(btrim(p_location_info), ''),
        v_scope,
        nullif(btrim(p_target_note), ''),
        nullif(btrim(p_invite_mail_body), ''),
        v_delivery_mode
    )
    returning id into v_event_id;

    if v_mode = 'manual' then
        insert into public.meeting_event_invites (event_id, member_id)
        select v_event_id, m.id
        from public.member m
        where m.id = any(p_member_ids);
    elsif v_mode = 'filter' then
        insert into public.meeting_event_invites (event_id, member_id)
        select distinct v_event_id, m.id
        from public.member m
        left join public.member_contacts mc
               on mc.member_id = m.id
        where
            (coalesce(array_length(p_division_flags, 1), 0) = 0 or m.division_flag = any(p_division_flags))
            and (coalesce(array_length(p_member_types, 1), 0) = 0 or m.member_type = any(p_member_types))
            and (coalesce(array_length(v_cidm_roles, 1), 0) = 0 or m.cidm_role = any(v_cidm_roles))
            and (not v_require_cidm_contact or mc.is_cidm_contact = true);
    else
        insert into public.meeting_event_invites (event_id, member_id)
        select v_event_id, m.id
        from public.member m
        where
            v_scope = '全員'
            or (v_scope = '会員' and m.division_flag = '会員')
            or (v_scope = '関係者' and m.division_flag = '関係者')
            or (v_scope = '正会員' and m.member_type = '正会員')
            or (v_scope = '準会員' and m.member_type = '準会員')
            or (v_scope = '賛助会員' and m.member_type in ('賛助会員', '賛助'));
    end if;

    return v_event_id;
end;
$$;

CREATE OR REPLACE FUNCTION public.cidm_create_meeting_event(
    p_event_name text,
    p_event_description text,
    p_starts_at timestamptz,
    p_location_info text,
    p_target_scope text,
    p_target_note text default null,
    p_target_mode text default 'scope',
    p_member_ids uuid[] default null,
    p_division_flags text[] default null,
    p_member_types text[] default null,
    p_cidm_roles text[] default null
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
    if not coalesce(public.cidm_is_admin(), false) then
        raise exception 'admin only';
    end if;

    return public.cidm_create_meeting_event(
        p_event_name,
        p_event_description,
        p_starts_at,
        p_location_info,
        p_target_scope,
        p_target_note,
        p_target_mode,
        p_member_ids,
        p_division_flags,
        p_member_types,
        p_cidm_roles,
        null,
        'rsvp'
    );
end;
$$;
