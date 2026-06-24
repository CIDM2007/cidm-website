-- Change super admin check from hardcoded email to member.app_role = 'super_admin'

begin;

-- 1. Update cidm_is_super_admin() to use app_role in member table
create or replace function public.cidm_is_super_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.member m
    where m.auth_user_id = auth.uid()
      and m.app_role = 'super_admin'
  );
$$;

-- 2. Update cidm_is_admin() to recognize super_admin as well
create or replace function public.cidm_is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.member m
    where m.auth_user_id = auth.uid()
      and m.app_role in ('admin', 'super_admin')
  );
$$;

-- 3. Update cidm_set_member_app_role to allow 'super_admin' value (super_admin only)
--    Prevent setting super_admin via this function to avoid privilege escalation
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
    raise exception 'super admin access required' using errcode = 'P0001';
  end if;

  if p_role not in ('member', 'admin') then
    raise exception 'invalid role: must be member or admin' using errcode = 'P0001';
  end if;

  update public.member
  set app_role = p_role
  where id = p_member_id;
end;
$$;

-- 4. Set the super admin's app_role to 'super_admin'
--    (the member whose auth_user_id matches carinformationdatamanagement@gmail.com)
update public.member
set app_role = 'super_admin'
where auth_user_id = (
  select id from auth.users
  where email = 'carinformationdatamanagement@gmail.com'
  limit 1
);

commit;
