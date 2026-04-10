-- CIDM baseline RLS policies
-- Apply with: supabase db push

-- Helper: judge whether current authenticated user is admin.
create or replace function public.cidm_is_admin()
returns boolean
language sql
stable
as $$
  select
    coalesce(auth.jwt() -> 'app_metadata' ->> 'is_admin', 'false') = 'true'
    or coalesce(auth.jwt() -> 'user_metadata' ->> 'is_admin', 'false') = 'true';
$$;

-- =========================
-- meeting_reports
-- Public news is readable, admin can fully manage.
-- =========================
alter table if exists public.meeting_reports enable row level security;

drop policy if exists "meeting_reports_select_visible" on public.meeting_reports;
create policy "meeting_reports_select_visible"
on public.meeting_reports
for select
to anon, authenticated
using (coalesce(is_visible, false) = true);

drop policy if exists "meeting_reports_admin_all" on public.meeting_reports;
create policy "meeting_reports_admin_all"
on public.meeting_reports
for all
to authenticated
using (public.cidm_is_admin())
with check (public.cidm_is_admin());

-- =========================
-- applications
-- Public form can insert only. Read/update/delete are blocked.
-- =========================
alter table if exists public.applications enable row level security;

drop policy if exists "applications_insert_public" on public.applications;
create policy "applications_insert_public"
on public.applications
for insert
to anon, authenticated
with check (true);

-- =========================
-- member
-- Admin only. Applied only if the table exists.
-- =========================
do $$
begin
    if exists (
        select 1 from information_schema.tables
        where table_schema = 'public' and table_name = 'member'
    ) then
        execute 'alter table public.member enable row level security';
        execute 'drop policy if exists "member_admin_all" on public.member';
        execute $pol$
            create policy "member_admin_all"
            on public.member
            for all
            to authenticated
            using (public.cidm_is_admin())
            with check (public.cidm_is_admin())
        $pol$;
    end if;
end;
$$;

-- =========================
-- member_documents
-- Current portal uses anon key; keep read access for now.
-- Admin only for write operations. Applied only if the table exists.
-- =========================
do $$
begin
    if exists (
        select 1 from information_schema.tables
        where table_schema = 'public' and table_name = 'member_documents'
    ) then
        execute 'alter table public.member_documents enable row level security';
        execute 'drop policy if exists "member_documents_select_public" on public.member_documents';
        execute $pol$
            create policy "member_documents_select_public"
            on public.member_documents
            for select
            to anon, authenticated
            using (true)
        $pol$;
        execute 'drop policy if exists "member_documents_admin_insert" on public.member_documents';
        execute $pol$
            create policy "member_documents_admin_insert"
            on public.member_documents
            for insert
            to authenticated
            with check (public.cidm_is_admin())
        $pol$;
        execute 'drop policy if exists "member_documents_admin_update" on public.member_documents';
        execute $pol$
            create policy "member_documents_admin_update"
            on public.member_documents
            for update
            to authenticated
            using (public.cidm_is_admin())
            with check (public.cidm_is_admin())
        $pol$;
        execute 'drop policy if exists "member_documents_admin_delete" on public.member_documents';
        execute $pol$
            create policy "member_documents_admin_delete"
            on public.member_documents
            for delete
            to authenticated
            using (public.cidm_is_admin())
        $pol$;
    end if;
end;
$$;
