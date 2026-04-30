alter table public.member
    add column if not exists department text,
    add column if not exists job_title  text;
