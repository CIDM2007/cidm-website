-- ============================================================
-- A案: Supabase Auth 統一ログイン対応
-- Step 1: member_contacts に auth_user_id 追加
--         + 会員情報取得 RPC 追加
-- ============================================================

begin;

-- ============================================================
-- 1. member_contacts に auth_user_id カラム追加
--    Supabase Auth の auth.users.id と紐付ける
-- ============================================================
ALTER TABLE public.member_contacts
  ADD COLUMN IF NOT EXISTS auth_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL;

COMMENT ON COLUMN public.member_contacts.auth_user_id IS 'Supabase Auth ユーザーID。招待後に設定される。';

CREATE UNIQUE INDEX IF NOT EXISTS member_contacts_auth_user_id_unique
  ON public.member_contacts (auth_user_id)
  WHERE auth_user_id IS NOT NULL;

-- ============================================================
-- 2. RLS ポリシー追加
--    会員担当者本人が自分の情報を読める
-- ============================================================
DROP POLICY IF EXISTS "member_contacts_self_select" ON public.member_contacts;
CREATE POLICY "member_contacts_self_select"
  ON public.member_contacts
  FOR SELECT
  TO authenticated
  USING (auth_user_id = auth.uid());

-- ============================================================
-- 3. cidm_get_my_contact_info
--    ログイン中の担当者が自分の会員情報を取得する RPC
-- ============================================================
DROP FUNCTION IF EXISTS public.cidm_get_my_contact_info();

CREATE OR REPLACE FUNCTION public.cidm_get_my_contact_info()
RETURNS TABLE (
  contact_id    uuid,
  contact_name  text,
  contact_email text,
  member_id     uuid,
  company_name  text,
  member_type   text,
  division_flag text,
  app_role      text
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    mc.id            AS contact_id,
    mc.name          AS contact_name,
    mc.email         AS contact_email,
    m.id             AS member_id,
    m.company_name,
    m.member_type,
    CASE WHEN btrim(COALESCE(m.division_flag, '')) = '関係者'
         THEN '関係者' ELSE '会員' END AS division_flag,
    COALESCE(NULLIF(btrim(m.app_role), ''), 'member') AS app_role
  FROM public.member_contacts mc
  JOIN public.member m ON m.id = mc.member_id
  WHERE mc.auth_user_id = auth.uid()
  LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.cidm_get_my_contact_info()
  TO authenticated;

-- ============================================================
-- 4. cidm_get_my_admin_info
--    ログイン中の管理者が自分の member 情報を取得する RPC
--    （member.auth_user_id で紐付け）
-- ============================================================
DROP FUNCTION IF EXISTS public.cidm_get_my_admin_info();

CREATE OR REPLACE FUNCTION public.cidm_get_my_admin_info()
RETURNS TABLE (
  member_id    uuid,
  company_name text,
  app_role     text
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    m.id AS member_id,
    m.company_name,
    COALESCE(NULLIF(btrim(m.app_role), ''), 'member') AS app_role
  FROM public.member m
  WHERE m.auth_user_id = auth.uid()
  LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.cidm_get_my_admin_info()
  TO authenticated;

commit;
