-- Admin role management via member.app_role
-- Super admin (carinformationdatamanagement@gmail.com) can grant/revoke admin role to members.
-- Members with app_role = 'admin' gain full admin access.

begin;

-- 1. Super admin check (hardcoded email, never changes via UI)
create or replace function public.cidm_is_super_admin()
returns boolean
language sql
stable
as $$
  select lower(coalesce(auth.jwt() ->> 'email', '')) = 'carinformationdatamanagement@gmail.com';
$$;

revoke all on function public.cidm_is_super_admin() from public;
grant execute on function public.cidm_is_super_admin() to authenticated;

-- 2. Update cidm_is_admin to also recognize member.app_role = 'admin'
create or replace function public.cidm_is_admin()
returns boolean
language sql
stable
as $$
  select
    -- Super admin (hardcoded)
    public.cidm_is_super_admin()
    -- Legacy metadata flags
    or coalesce(auth.jwt() -> 'app_metadata' ->> 'is_admin', 'false') = 'true'
    or coalesce(auth.jwt() -> 'user_metadata' ->> 'is_admin', 'false') = 'true'
    -- Member table app_role = 'admin'
    or exists (
      select 1 from public.member m
      where m.auth_user_id = auth.uid()
        and m.app_role = 'admin'
    );
$$;

-- 3. RPC to change member app_role (super admin only)
create or replace function public.cidm_set_member_app_role(
  p_member_id uuid,
  p_role text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.cidm_is_super_admin() then
    raise exception 'super admin only';
  end if;

  if p_role not in ('member', 'staff', 'admin') then
    raise exception 'invalid role';
  end if;

  update public.member
  set app_role = p_role
  where id = p_member_id;

  if not found then
    raise exception 'member not found';
  end if;
end;
$$;

revoke all on function public.cidm_set_member_app_role(uuid, text) from public;
grant execute on function public.cidm_set_member_app_role(uuid, text) to authenticated;

-- 4. Update cidm_admin_list_members to include app_role
drop function if exists public.cidm_admin_list_members(boolean, boolean, boolean);

create or replace function public.cidm_admin_list_members(
  p_include_member boolean default true,
  p_include_related boolean default true,
  p_include_pending_only boolean default false
)
returns table (
  id uuid,
  division_flag text,
  member_type text,
  is_officer boolean,
  company_name text,
  cidm_role text,
  staff_name text,
  staff_mobile text,
  staff_email text,
  biko text,
  application_status text,
  application_review_note text,
  application_submitted_at timestamptz,
  contact_count bigint,
  app_role text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not coalesce(public.cidm_is_admin(), false) then
    raise exception 'admin access required';
  end if;

  return query
  with normalized as (
    select
      m.id,
      case when btrim(coalesce(m.division_flag, '')) = '関係者' then '関係者' else '会員' end as division_flag,
      m.member_type,
      m.is_officer,
      m.company_name,
      m.cidm_role,
      m.staff_name,
      m.staff_mobile,
      m.staff_email,
      m.biko,
      coalesce(nullif(btrim(m.application_status), ''), '承認済') as application_status,
      m.application_review_note,
      m.application_submitted_at,
      count(mc.id)::bigint as contact_count,
      coalesce(nullif(btrim(m.app_role), ''), 'member') as app_role
    from public.member m
    left join public.member_contacts mc
      on mc.member_id = m.id
    group by
      m.id,
      m.division_flag,
      m.member_type,
      m.is_officer,
      m.company_name,
      m.cidm_role,
      m.staff_name,
      m.staff_mobile,
      m.staff_email,
      m.biko,
      m.application_status,
      m.application_review_note,
      m.application_submitted_at,
      m.app_role
  )
  select
    n.id,
    n.division_flag,
    n.member_type,
    n.is_officer,
    n.company_name,
    n.cidm_role,
    n.staff_name,
    n.staff_mobile,
    n.staff_email,
    n.biko,
    n.application_status,
    n.application_review_note,
    n.application_submitted_at,
    n.contact_count,
    n.app_role
  from normalized n
  where
    case
      when p_include_pending_only and not (coalesce(p_include_member, false) or coalesce(p_include_related, false)) then
        n.application_status = '未審査'
      when p_include_pending_only then
        ((n.division_flag = '会員' and coalesce(p_include_member, false))
         or (n.division_flag = '関係者' and coalesce(p_include_related, false))
         or n.application_status = '未審査')
      else
        n.application_status <> '未審査'
        and ((n.division_flag = '会員' and coalesce(p_include_member, false))
             or (n.division_flag = '関係者' and coalesce(p_include_related, false)))
    end;
end;
$$;

grant execute on function public.cidm_admin_list_members(boolean, boolean, boolean)
  to authenticated, service_role;

commit;
