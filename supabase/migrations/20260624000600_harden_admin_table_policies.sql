-- Reassert admin-only policies for sensitive public tables.

drop policy if exists "meeting_events_admin_all" on public.meeting_events;
create policy "meeting_events_admin_all"
on public.meeting_events
for all
to authenticated
using (public.cidm_is_admin())
with check (public.cidm_is_admin());

drop policy if exists "meeting_event_invites_admin_all" on public.meeting_event_invites;
create policy "meeting_event_invites_admin_all"
on public.meeting_event_invites
for all
to authenticated
using (public.cidm_is_admin())
with check (public.cidm_is_admin());

drop policy if exists "meeting_invite_mail_logs_admin_all" on public.meeting_invite_mail_logs;
create policy "meeting_invite_mail_logs_admin_all"
on public.meeting_invite_mail_logs
for all
to authenticated
using (public.cidm_is_admin())
with check (public.cidm_is_admin());

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

drop policy if exists "meeting_report_assets_insert_admin" on storage.objects;
drop policy if exists "meeting_report_assets_insert_public" on storage.objects;
create policy "meeting_report_assets_insert_admin"
on storage.objects
for insert
to authenticated
with check (
    bucket_id = 'meeting-report-assets'
    and public.cidm_is_admin()
);

drop policy if exists "meeting_report_assets_update_admin" on storage.objects;
drop policy if exists "meeting_report_assets_update_public" on storage.objects;
create policy "meeting_report_assets_update_admin"
on storage.objects
for update
to authenticated
using (
    bucket_id = 'meeting-report-assets'
    and public.cidm_is_admin()
)
with check (
    bucket_id = 'meeting-report-assets'
    and public.cidm_is_admin()
);

drop policy if exists "meeting_report_assets_delete_admin" on storage.objects;
drop policy if exists "meeting_report_assets_delete_public" on storage.objects;
create policy "meeting_report_assets_delete_admin"
on storage.objects
for delete
to authenticated
using (
    bucket_id = 'meeting-report-assets'
    and public.cidm_is_admin()
);