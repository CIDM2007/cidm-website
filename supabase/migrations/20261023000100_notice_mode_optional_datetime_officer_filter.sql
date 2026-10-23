-- ============================================================
-- 案内のみ(notice)イベントで開催日時・場所を任意にする
-- admin-events.html は p_is_officer を送るため、20260513002000 の
-- 14引数版が呼ばれており、starts_at を無条件に必須としていた。
-- 出欠確認あり(rsvp)のみ starts_at を必須とし、notice では日時・場所を保存しない。
-- ============================================================

create or replace function public.cidm_create_meeting_event(
    p_event_name text,
    p_event_description text,
    p_starts_at timestamptz,
    p_location_info text,
    p_target_scope text,
    p_target_note text default null,
    p_target_mode text default 'scope',
    p_member_ids uuid[] default null,
    p_division_flags text[] default null,
    p_is_officer boolean default null,
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
begin
    if not coalesce(public.cidm_is_admin(), false) then
        raise exception 'admin only';
    end if;

    if nullif(btrim(p_event_name), '') is null then
        raise exception 'event name is required';
    end if;

    v_mode := coalesce(nullif(btrim(p_target_mode), ''), 'scope');
    v_scope := coalesce(nullif(btrim(p_target_scope), ''), '全員');
    v_delivery_mode := coalesce(nullif(btrim(p_delivery_mode), ''), 'rsvp');

    if v_mode not in ('scope', 'manual', 'filter') then
        raise exception 'invalid target mode';
    end if;

    if v_delivery_mode not in ('rsvp', 'notice') then
        raise exception 'invalid delivery mode';
    end if;

    if v_delivery_mode = 'rsvp' and p_starts_at is null then
        raise exception 'starts_at is required for rsvp mode';
    end if;

    if v_mode = 'scope' and v_scope not in ('全員', '会員', '関係者', '正会員', '準会員', '賛助会員', '役員') then
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
           and coalesce(array_length(p_cidm_roles, 1), 0) = 0
           and p_is_officer is null then
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
        case when v_delivery_mode = 'notice' then null else p_starts_at end,
        case when v_delivery_mode = 'notice' then null else nullif(btrim(p_location_info), '') end,
        v_scope,
        nullif(btrim(p_target_note), ''),
        nullif(btrim(p_invite_mail_body), ''),
        v_delivery_mode
    )
    returning id into v_event_id;

    insert into public.meeting_event_invites (event_id, member_id)
    select v_event_id, m.id
    from public.member m
    where
        (v_mode = 'manual' and m.id = any(p_member_ids))
        or (
            v_mode = 'filter'
            and (
                (
                    coalesce(array_length(p_member_ids, 1), 0) > 0
                    and m.id = any(p_member_ids)
                )
                or (
                    coalesce(array_length(p_member_ids, 1), 0) = 0
                    and (coalesce(array_length(p_division_flags, 1), 0) = 0 or m.division_flag = any(p_division_flags))
                    and (p_is_officer is null or coalesce(m.is_officer, false) = p_is_officer)
                    and (coalesce(array_length(p_member_types, 1), 0) = 0 or m.member_type = any(p_member_types))
                    and (coalesce(array_length(p_cidm_roles, 1), 0) = 0 or m.cidm_role = any(p_cidm_roles))
                )
            )
        )
        or (
            v_mode = 'scope'
            and (
                v_scope = '全員'
                or (v_scope = '会員' and m.division_flag = '会員')
                or (v_scope = '関係者' and m.division_flag = '関係者')
                or (v_scope = '正会員' and m.member_type = '正会員')
                or (v_scope = '準会員' and m.member_type = '準会員')
                or (v_scope = '賛助会員' and m.member_type in ('賛助会員', '賛助'))
                or (v_scope = '役員' and coalesce(m.is_officer, false) = true)
            )
        );

    return v_event_id;
end;
$$;
