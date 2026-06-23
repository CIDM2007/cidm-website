-- Harden SECURITY DEFINER / utility functions against search_path tampering.

create or replace function public.cidm_is_super_admin()
returns boolean
language sql
stable
set search_path = public
as $$
  select lower(coalesce(auth.jwt() ->> 'email', '')) = 'carinformationdatamanagement@gmail.com';
$$;

create or replace function public.cidm_is_admin()
returns boolean
language sql
stable
set search_path = public
as $$
  select
    public.cidm_is_super_admin()
    or coalesce(auth.jwt() -> 'app_metadata' ->> 'is_admin', 'false') = 'true'
    or coalesce(auth.jwt() -> 'user_metadata' ->> 'is_admin', 'false') = 'true'
    or exists (
      select 1 from public.member m
      where m.auth_user_id = auth.uid()
        and m.app_role = 'admin'
    );
$$;

create or replace function public.cidm_touch_membership_fee_prices_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
    new.updated_at := now();
    return new;
end;
$$;

create or replace function public.cidm_meeting_reports_fill_id_on_null()
returns trigger
language plpgsql
set search_path = public
as $$
begin
    if new.id is null then
        new.id := nextval('public.meeting_reports_id_seq');
    end if;

    if new.category is null or btrim(new.category) = '' then
        new.category := '会議報告';
    end if;

    return new;
end;
$$;

create or replace function public.cidm_touch_app_settings_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
    new.updated_at := now();
    return new;
end;
$$;