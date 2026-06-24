-- Remove super_admin concept: all admins can manage admin roles equally

begin;

-- 1. Revert any super_admin roles back to admin
update public.member set app_role = 'admin' where app_role = 'super_admin';

-- 2. cidm_is_super_admin: always returns false (deprecated, kept for compatibility)
create or replace function public.cidm_is_super_admin()
returns boolean
language sql
stable
as $$
  select false;
$$;

-- 3. cidm_is_admin: check member.app_role = 'admin'
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
      and m.app_role = 'admin'
  );
$$;

-- 4. cidm_set_member_app_role: any admin can change roles
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
  if not public.cidm_is_admin() then
    raise exception 'admin access required' using errcode = 'P0001';
  end if;

  if p_role not in ('member', 'admin') then
    raise exception 'invalid role: must be member or admin' using errcode = 'P0001';
  end if;

  update public.member set app_role = p_role where id = p_member_id;
end;
$$;

commit;
