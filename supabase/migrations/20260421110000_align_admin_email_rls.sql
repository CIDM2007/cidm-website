-- Align DB-side admin checks with the email allowlist used by the admin login UI.
-- This keeps RLS and SECURITY DEFINER RPC authorization consistent.

create or replace function public.cidm_is_admin()
returns boolean
language sql
stable
as $$
  select
    coalesce(auth.jwt() -> 'app_metadata' ->> 'is_admin', 'false') = 'true'
    or coalesce(auth.jwt() -> 'user_metadata' ->> 'is_admin', 'false') = 'true'
    or lower(coalesce(auth.jwt() ->> 'email', '')) = any (
      array[
        'carinformationdatamanagement@gmail.com'
      ]
    );
$$;