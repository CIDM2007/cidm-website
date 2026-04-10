-- meeting events and RSVP system

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.meeting_events (
    id uuid primary key default gen_random_uuid(),
    event_name text not null,
    event_description text,
    starts_at timestamptz not null,
    location_info text,
    target_scope text not null default '全員',
    target_note text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint meeting_events_target_scope_chk
        check (target_scope in ('全員', '会員', '関係者', '正会員', '準会員', '賛助会員', '個別選択', '条件指定'))
);

do $$
begin
    if exists (
        select 1
        from information_schema.table_constraints
        where table_schema = 'public'
          and table_name = 'meeting_events'
          and constraint_name = 'meeting_events_target_scope_chk'
    ) then
        alter table public.meeting_events
            drop constraint meeting_events_target_scope_chk;
        alter table public.meeting_events
            add constraint meeting_events_target_scope_chk
            check (target_scope in ('全員', '会員', '関係者', '正会員', '準会員', '賛助会員', '個別選択', '条件指定'));
    end if;
end;
$$;

create table if not exists public.meeting_event_invites (
    id uuid primary key default gen_random_uuid(),
    event_id uuid not null references public.meeting_events(id) on delete cascade,
    member_id uuid not null references public.member(id) on delete cascade,
    access_token uuid not null unique default gen_random_uuid(),
    response_status text not null default '未回答',
    memo text,
    responded_at timestamptz,
    created_at timestamptz not null default now(),
    constraint meeting_event_invites_status_chk
        check (response_status in ('未回答', '出席', '欠席', '検討中')),
    constraint meeting_event_invites_event_member_uk unique(event_id, member_id)
);

create index if not exists meeting_event_invites_event_id_idx
    on public.meeting_event_invites(event_id);

create index if not exists meeting_event_invites_member_id_idx
    on public.meeting_event_invites(member_id);

alter table public.meeting_events enable row level security;
alter table public.meeting_event_invites enable row level security;

drop policy if exists "meeting_events_admin_all" on public.meeting_events;
create policy "meeting_events_admin_all"
on public.meeting_events
for all
to anon, authenticated
using (true)
with check (true);

drop policy if exists "meeting_event_invites_admin_all" on public.meeting_event_invites;
create policy "meeting_event_invites_admin_all"
on public.meeting_event_invites
for all
to anon, authenticated
using (true)
with check (true);

drop function if exists public.cidm_create_meeting_event(text, text, timestamptz, text, text, text);

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
    p_cidm_roles text[] default null
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
begin
    if nullif(btrim(p_event_name), '') is null then
        raise exception 'event name is required';
    end if;

    if p_starts_at is null then
        raise exception 'starts_at is required';
    end if;

    v_mode := coalesce(nullif(btrim(p_target_mode), ''), 'scope');
    v_scope := coalesce(nullif(btrim(p_target_scope), ''), '全員');

    if v_mode not in ('scope', 'manual', 'filter') then
        raise exception 'invalid target mode';
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
        target_note
    ) values (
        btrim(p_event_name),
        nullif(btrim(p_event_description), ''),
        p_starts_at,
        nullif(btrim(p_location_info), ''),
        v_scope,
        nullif(btrim(p_target_note), '')
    )
    returning id into v_event_id;

    if v_mode = 'manual' then
        insert into public.meeting_event_invites (event_id, member_id)
        select v_event_id, m.id
        from public.member m
        where m.id = any(p_member_ids);
    elsif v_mode = 'filter' then
        insert into public.meeting_event_invites (event_id, member_id)
        select v_event_id, m.id
        from public.member m
        where
            (coalesce(array_length(p_division_flags, 1), 0) = 0 or m.division_flag = any(p_division_flags))
            and (coalesce(array_length(p_member_types, 1), 0) = 0 or m.member_type = any(p_member_types))
            and (coalesce(array_length(p_cidm_roles, 1), 0) = 0 or m.cidm_role = any(p_cidm_roles));
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

create or replace function public.cidm_admin_list_meeting_events()
returns table (
    event_id uuid,
    event_name text,
    event_description text,
    starts_at timestamptz,
    location_info text,
    target_scope text,
    target_note text,
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

create or replace function public.cidm_admin_list_meeting_invites(
    p_event_id uuid
)
returns table (
    invite_id uuid,
    event_id uuid,
    access_token uuid,
    response_status text,
    memo text,
    responded_at timestamptz,
    member_id uuid,
    division_flag text,
    member_type text,
    cidm_role text,
    company_name text,
    staff_name text,
    staff_email text,
    staff_mobile text
)
language sql
security definer
set search_path = public, extensions
as $$
    select
        i.id,
        i.event_id,
        i.access_token,
        i.response_status,
        i.memo,
        i.responded_at,
        m.id,
        m.division_flag,
        m.member_type,
        m.cidm_role,
        m.company_name,
        m.staff_name,
        m.staff_email,
        m.staff_mobile
    from public.meeting_event_invites i
    join public.member m
        on m.id = i.member_id
    where i.event_id = p_event_id
    order by m.company_name asc;
$$;

create or replace function public.cidm_get_meeting_invite_by_token(
    p_token text
)
returns table (
    invite_id uuid,
    event_id uuid,
    event_name text,
    event_description text,
    starts_at timestamptz,
    location_info text,
    target_scope text,
    response_status text,
    memo text,
    company_name text,
    staff_name text
)
language sql
security definer
set search_path = public, extensions
as $$
    select
        i.id,
        e.id,
        e.event_name,
        e.event_description,
        e.starts_at,
        e.location_info,
        e.target_scope,
        i.response_status,
        i.memo,
        m.company_name,
        m.staff_name
    from public.meeting_event_invites i
    join public.meeting_events e
        on e.id = i.event_id
    join public.member m
        on m.id = i.member_id
    where i.access_token = p_token::uuid;
$$;

create or replace function public.cidm_submit_meeting_response(
    p_token text,
    p_response_status text,
    p_memo text default null
)
returns table (
    success boolean,
    message text
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
    v_invite_id uuid;
begin
    if p_response_status not in ('出席', '欠席', '検討中') then
        return query select false, 'invalid response status';
        return;
    end if;

    select i.id
      into v_invite_id
    from public.meeting_event_invites i
    where i.access_token = p_token::uuid;

    if v_invite_id is null then
        return query select false, 'invite not found';
        return;
    end if;

    update public.meeting_event_invites
    set
        response_status = p_response_status,
        memo = nullif(btrim(p_memo), ''),
        responded_at = now()
    where id = v_invite_id;

    return query select true, 'ok';
end;
$$;
