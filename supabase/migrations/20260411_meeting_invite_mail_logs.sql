create extension if not exists pgcrypto with schema extensions;

create table if not exists public.meeting_invite_mail_logs (
    id uuid primary key default gen_random_uuid(),
    event_id uuid not null references public.meeting_events(id) on delete cascade,
    recipient_email text not null,
    recipient_name text,
    company_name text,
    send_mode text not null default 'all'
        check (send_mode in ('all', 'pending')),
    send_status text not null
        check (send_status in ('success', 'failed')),
    error_message text,
    sent_at timestamptz not null default now(),
    created_at timestamptz not null default now()
);

create index if not exists meeting_invite_mail_logs_event_id_sent_at_idx
    on public.meeting_invite_mail_logs(event_id, sent_at desc);

alter table public.meeting_invite_mail_logs enable row level security;

drop policy if exists "meeting_invite_mail_logs_admin_all" on public.meeting_invite_mail_logs;
create policy "meeting_invite_mail_logs_admin_all"
on public.meeting_invite_mail_logs
for all
to anon, authenticated
using (true)
with check (true);
