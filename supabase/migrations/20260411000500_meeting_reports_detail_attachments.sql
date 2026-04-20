alter table public.meeting_reports
    add column if not exists detail_text text;

alter table public.meeting_reports
    add column if not exists attachment_urls jsonb not null default '[]'::jsonb;

update public.meeting_reports
set attachment_urls = '[]'::jsonb
where attachment_urls is null;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
    'meeting-report-assets',
    'meeting-report-assets',
    true,
    52428800,
    array['application/pdf', 'image/*', 'video/*']
)
on conflict (id) do update
set
    public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "meeting_report_assets_select_public" on storage.objects;
create policy "meeting_report_assets_select_public"
on storage.objects
for select
to anon, authenticated
using (bucket_id = 'meeting-report-assets');

drop policy if exists "meeting_report_assets_insert_public" on storage.objects;
create policy "meeting_report_assets_insert_public"
on storage.objects
for insert
to anon, authenticated
with check (bucket_id = 'meeting-report-assets');

drop policy if exists "meeting_report_assets_update_public" on storage.objects;
create policy "meeting_report_assets_update_public"
on storage.objects
for update
to anon, authenticated
using (bucket_id = 'meeting-report-assets')
with check (bucket_id = 'meeting-report-assets');

drop policy if exists "meeting_report_assets_delete_public" on storage.objects;
create policy "meeting_report_assets_delete_public"
on storage.objects
for delete
to anon, authenticated
using (bucket_id = 'meeting-report-assets');
