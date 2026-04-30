alter table public.meeting_reports
    alter column event_date type timestamptz using event_date::timestamptz;
