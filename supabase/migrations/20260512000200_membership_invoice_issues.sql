create extension if not exists pgcrypto with schema extensions;

create table if not exists public.membership_invoice_issues (
    id uuid primary key default gen_random_uuid(),
    access_token uuid not null unique default gen_random_uuid(),
    member_id uuid not null references public.member(id) on delete cascade,
    billing_year integer not null check (billing_year between 2000 and 2100),
    billing_month integer not null check (billing_month between 1 and 12),
    invoice_no text not null,
    amount integer not null check (amount >= 0),
    due_date date not null,
    company_name_snapshot text,
    staff_name_snapshot text,
    staff_email_snapshot text,
    member_type_snapshot text,
    mail_subject text,
    mail_body text,
    send_status text not null default 'failed' check (send_status in ('success', 'failed')),
    error_message text,
    sent_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create index if not exists membership_invoice_issues_member_idx
    on public.membership_invoice_issues(member_id);

create index if not exists membership_invoice_issues_billing_idx
    on public.membership_invoice_issues(billing_year, billing_month, created_at desc);

create index if not exists membership_invoice_issues_token_idx
    on public.membership_invoice_issues(access_token);

alter table public.membership_invoice_issues enable row level security;

drop policy if exists "membership_invoice_issues_admin_all" on public.membership_invoice_issues;

create or replace function public.cidm_get_membership_invoice_by_token(
    p_token text
)
returns table (
    issue_id uuid,
    invoice_no text,
    billing_year integer,
    billing_month integer,
    due_date date,
    amount integer,
    company_name text,
    staff_name text,
    staff_email text,
    member_type text,
    send_status text,
    issued_at timestamptz
)
language sql
security definer
set search_path = public, extensions
as $$
    select
        i.id,
        i.invoice_no,
        i.billing_year,
        i.billing_month,
        i.due_date,
        i.amount,
        coalesce(i.company_name_snapshot, m.company_name),
        coalesce(i.staff_name_snapshot, m.staff_name),
        coalesce(i.staff_email_snapshot, m.staff_email),
        coalesce(i.member_type_snapshot, m.member_type),
        i.send_status,
        coalesce(i.sent_at, i.created_at)
    from public.membership_invoice_issues i
    left join public.member m
      on m.id = i.member_id
    where i.access_token = p_token::uuid
    limit 1;
$$;

grant execute on function public.cidm_get_membership_invoice_by_token(text)
    to anon, authenticated;