-- Link meeting_reports to meeting_events for per-event minutes management

alter table public.meeting_reports
    add column if not exists event_id uuid references public.meeting_events(id) on delete set null;

create index if not exists meeting_reports_event_id_idx
    on public.meeting_reports(event_id);

-- Harden admin write policy (was previously open to anon/authenticated without role check)
drop policy if exists "meeting_reports_admin_all" on public.meeting_reports;
create policy "meeting_reports_admin_all"
on public.meeting_reports
for all
to authenticated
using (public.cidm_is_admin())
with check (public.cidm_is_admin());
