begin;

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
  contact_count bigint
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
      count(mc.id)::bigint as contact_count
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
      m.application_submitted_at
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
    n.contact_count
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

comment on function public.cidm_admin_list_members(boolean, boolean, boolean) is
  '会員一覧の抽出条件（区分・未審査のみ）をDB側で適用して返す管理者向けRPC。';

commit;