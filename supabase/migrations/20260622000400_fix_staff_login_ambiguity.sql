-- Fix ambiguous column reference in cidm_staff_login (error 42702)
-- The RETURNS TABLE has a column named 'login_id' which conflicts with
-- the 'login_id' column in member_staff_auth during SELECT.

begin;

CREATE OR REPLACE FUNCTION public.cidm_staff_login(
    p_login_id TEXT,
    p_password TEXT
)
RETURNS TABLE (
    staff_id UUID,
    contact_id UUID,
    member_id UUID,
    staff_name TEXT,
    company_name TEXT,
    member_type TEXT,
    login_id TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_auth_id UUID;
    v_password_hash TEXT;
BEGIN
    SELECT msa.id, msa.password_hash
    INTO v_auth_id, v_password_hash
    FROM public.member_staff_auth msa
    WHERE LOWER(msa.login_id) = LOWER(btrim(p_login_id))
      AND msa.is_active = true
      AND msa.password_hash IS NOT NULL
    LIMIT 1;

    IF v_auth_id IS NULL THEN
        RAISE EXCEPTION 'Invalid credentials';
    END IF;

    IF NOT (extensions.crypt(p_password, v_password_hash) = v_password_hash) THEN
        RAISE EXCEPTION 'Invalid credentials';
    END IF;

    RETURN QUERY
    SELECT
        msa.id AS staff_id,
        mc.id AS contact_id,
        m.id AS member_id,
        mc.name AS staff_name,
        m.company_name,
        m.member_type,
        msa.login_id
    FROM public.member_staff_auth msa
    JOIN public.member_contacts mc ON mc.id = msa.contact_id
    JOIN public.member m ON m.id = mc.member_id
    WHERE msa.id = v_auth_id;
END;
$$;

grant execute on function public.cidm_staff_login(text, text)
  to anon, authenticated;

commit;
