-- Drop legacy email-link password reset artifacts.
-- Current production flow uses RPC-based self-service recovery.

drop function if exists public.cidm_consume_member_password_reset(text, text);

drop table if exists public.member_password_reset_tokens;
