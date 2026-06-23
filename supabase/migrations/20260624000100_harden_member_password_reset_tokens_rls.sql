-- Harden member password reset token storage.
-- This table must never be directly readable/writable from anon/authenticated roles.

alter table if exists public.member_password_reset_tokens
  enable row level security;

revoke all on table public.member_password_reset_tokens from public;
revoke all on table public.member_password_reset_tokens from anon;
revoke all on table public.member_password_reset_tokens from authenticated;

-- Keep service role maintenance explicit (idempotent).
drop policy if exists "member_password_reset_tokens_service_role_all"
  on public.member_password_reset_tokens;

create policy "member_password_reset_tokens_service_role_all"
  on public.member_password_reset_tokens
  for all
  to service_role
  using (true)
  with check (true);
