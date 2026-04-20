alter table public.meeting_events
    add column if not exists delivery_mode text not null default 'rsvp';

alter table public.meeting_events
    drop constraint if exists meeting_events_delivery_mode_chk;

alter table public.meeting_events
    add constraint meeting_events_delivery_mode_chk
    check (delivery_mode in ('rsvp', 'notice'));

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
    if nullif(btrim(p_event_name), '') is null then
        raise exception 'event name is required';
    end if;

    if p_starts_at is null then
        raise exception 'starts_at is required';
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
           and coalesce(array_length(p_cidm_roles, 1), 0) = 0 then
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

    insert into public.meeting_event_invites (event_id, member_id)
    select v_event_id, m.id
    from public.member m
    where
        (v_mode = 'manual' and m.id = any(p_member_ids))
        or (
            v_mode = 'filter'
            and (coalesce(array_length(p_division_flags, 1), 0) = 0 or m.division_flag = any(p_division_flags))
            and (coalesce(array_length(p_member_types, 1), 0) = 0 or m.member_type = any(p_member_types))
            and (coalesce(array_length(p_cidm_roles, 1), 0) = 0 or m.cidm_role = any(p_cidm_roles))
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
            )
        );

    return v_event_id;
end;
$$;

drop function if exists public.cidm_admin_list_meeting_events();

create or replace function public.cidm_admin_list_meeting_events()
returns table (
    event_id uuid,
    event_name text,
    event_description text,
    starts_at timestamptz,
    location_info text,
    target_scope text,
    target_note text,
    invite_mail_body text,
    delivery_mode text,
    total_invites bigint,
    attended_count bigint,
    absent_count bigint,
    pending_count bigint,
    considering_count bigint,
    created_at timestamptz
)
language sql
security definer
set search_path = public, extensions
as $$
    select
        e.id,
        e.event_name,
        e.event_description,
        e.starts_at,
        e.location_info,
        e.target_scope,
        e.target_note,
        e.invite_mail_body,
        e.delivery_mode,
        count(i.id) as total_invites,
        count(i.id) filter (where i.response_status = '出席') as attended_count,
        count(i.id) filter (where i.response_status = '欠席') as absent_count,
        count(i.id) filter (where i.response_status = '未回答') as pending_count,
        count(i.id) filter (where i.response_status = '検討中') as considering_count,
        e.created_at
    from public.meeting_events e
    left join public.meeting_event_invites i
        on i.event_id = e.id
    group by e.id
    order by e.starts_at desc;
$$;
