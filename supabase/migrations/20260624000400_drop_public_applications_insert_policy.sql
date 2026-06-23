-- Remove the overly permissive public insert policy from applications.
-- The public application flow uses cidm_submit_application() instead of direct table inserts.

drop policy if exists "applications_insert_public" on public.applications;