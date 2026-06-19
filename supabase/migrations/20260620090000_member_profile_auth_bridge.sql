-- Bridge migration: make public.member a profile/role table linked to auth.users.
-- Non-breaking by design: legacy login/password columns remain for compatibility.

begin;

alter table if exists public.member
    add column if not exists auth_user_id uuid,
    add column if not exists app_role text,
    add column if not exists auth_linked_at timestamptz;

do $$
begin
    if not exists (
        select 1
        from pg_constraint
        where conname = 'member_auth_user_fk'
          and conrelid = 'public.member'::regclass
    ) then
        alter table public.member
            add constraint member_auth_user_fk
            foreign key (auth_user_id)
            references auth.users(id)
            on delete set null;
    end if;
end
$$;

create unique index if not exists member_auth_user_id_unique_idx
    on public.member (auth_user_id)
    where auth_user_id is not null;

update public.member
set app_role = coalesce(nullif(btrim(app_role), ''), 'member')
where app_role is null
   or btrim(app_role) = '';

do $$
begin
    if not exists (
        select 1
        from pg_constraint
        where conname = 'member_app_role_chk'
          and conrelid = 'public.member'::regclass
    ) then
        alter table public.member
            add constraint member_app_role_chk
            check (app_role in ('member', 'staff', 'admin'));
    end if;
end
$$;

alter table public.member
    alter column app_role set default 'member';

-- Backfill auth_user_id from login_id=email (already normalized in previous migration).
with login_matches as (
    select
        m.id as member_id,
        u.id as auth_user_id,
        row_number() over (partition by m.id order by u.created_at asc, u.id asc) as rn_member,
        row_number() over (partition by u.id order by m.id asc) as rn_user
    from public.member m
    join auth.users u
      on lower(btrim(coalesce(m.login_id, ''))) = lower(btrim(coalesce(u.email, '')))
    where nullif(btrim(coalesce(m.login_id, '')), '') is not null
)
update public.member m
set auth_user_id = lm.auth_user_id,
    auth_linked_at = coalesce(m.auth_linked_at, now())
from login_matches lm
where m.id = lm.member_id
  and lm.rn_member = 1
  and lm.rn_user = 1
  and m.auth_user_id is null;

create or replace function public.cidm_my_member_id()
returns uuid
language sql
security definer
set search_path = public
stable
as $$
    select m.id
    from public.member m
    where m.auth_user_id = auth.uid()
    limit 1;
$$;

revoke all on function public.cidm_my_member_id() from public;
grant execute on function public.cidm_my_member_id() to authenticated;

create or replace function public.cidm_link_member_to_auth_user(
    p_member_id uuid,
    p_auth_user_id uuid
)
returns public.member
language plpgsql
security definer
set search_path = public
as $$
declare
    v_member public.member;
begin
    if not coalesce(public.cidm_is_admin(), false) then
        raise exception 'admin access required';
    end if;

    update public.member m
    set auth_user_id = p_auth_user_id,
        auth_linked_at = now()
    where m.id = p_member_id
    returning m.* into v_member;

    if v_member.id is null then
        raise exception 'member not found';
    end if;

    return v_member;
end;
$$;

revoke all on function public.cidm_link_member_to_auth_user(uuid, uuid) from public;
grant execute on function public.cidm_link_member_to_auth_user(uuid, uuid) to authenticated;

comment on column public.member.auth_user_id is
    'References auth.users.id. Authentication owner for this member profile.';

comment on column public.member.app_role is
    'Application role for authorization: member | staff | admin.';

comment on column public.member.auth_linked_at is
    'Timestamp when auth_user_id was linked.';

comment on column public.member.login_id is
    'Deprecated for authentication. Keep for transition only.';

comment on column public.member.password_hash is
    'Deprecated for authentication. Keep for transition only.';

commit;
