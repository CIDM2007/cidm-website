-- Fix ambiguous column reference in cidm_admin_create_contact_invite (error 42702)
-- The RETURNS TABLE has a column named 'contact_id' which conflicts with
-- the 'contact_id' column in contact_password_reset_tokens during UPDATE.

begin;

DROP FUNCTION IF EXISTS public.cidm_admin_create_contact_invite(uuid, text, interval, text);

CREATE OR REPLACE FUNCTION public.cidm_admin_create_contact_invite(
  p_contact_id uuid,
  p_token_hash text,
  p_expires_in interval DEFAULT interval '72 hours',
  p_token_type text     DEFAULT 'invite'
)
RETURNS TABLE (
  contact_id    uuid,
  contact_name  text,
  contact_email text,
  expires_at    timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_expires_at timestamptz;
BEGIN
  IF NOT COALESCE(public.cidm_is_admin(), false) THEN
    RAISE EXCEPTION 'admin access required';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.member_contacts WHERE id = p_contact_id) THEN
    RAISE EXCEPTION 'contact not found';
  END IF;

  IF NULLIF(btrim(p_token_hash), '') IS NULL THEN
    RAISE EXCEPTION 'token_hash is required';
  END IF;

  v_expires_at := now() + p_expires_in;

  -- 未使用の旧トークンを無効化（テーブル名で修飾して曖昧さを解消）
  UPDATE public.contact_password_reset_tokens t
  SET used_at = now()
  WHERE t.contact_id = p_contact_id
    AND t.used_at IS NULL;

  -- 新トークン挿入
  INSERT INTO public.contact_password_reset_tokens
    (contact_id, token_hash, expires_at, token_type)
  VALUES
    (p_contact_id, p_token_hash, v_expires_at, p_token_type);

  RETURN QUERY
  SELECT
    mc.id,
    mc.name,
    mc.email,
    v_expires_at
  FROM public.member_contacts mc
  WHERE mc.id = p_contact_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.cidm_admin_create_contact_invite(uuid, text, interval, text)
  TO authenticated, service_role;

commit;
