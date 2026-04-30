alter table public.meeting_reports
    add column if not exists photo_urls jsonb not null default '[]'::jsonb;

update public.meeting_reports
set photo_urls = '[]'::jsonb
where photo_urls is null;
