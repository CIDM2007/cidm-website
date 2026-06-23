-- Tighten overly permissive admin-side RLS policies.

drop policy if exists "contact_inquiries_admin_all" on public.contact_inquiries;
create policy "contact_inquiries_admin_all"
on public.contact_inquiries
for all
to authenticated
using (public.cidm_is_admin())
with check (public.cidm_is_admin());

drop policy if exists "app_settings_admin_all" on public.app_settings;
create policy "app_settings_admin_all"
on public.app_settings
for all
to authenticated
using (public.cidm_is_admin())
with check (public.cidm_is_admin());