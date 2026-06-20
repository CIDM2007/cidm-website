-- ============================================================
-- 招待方式ログイン: contact_password_reset_tokens テーブルと
-- 関連 RPC（招待発行・トークン消費）
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

-- ============================================================
-- 1. contact_password_reset_tokens テーブル
--    担当者の招待・パスワードリセット両用トークン管理
-- ============================================================
CREATE TABLE IF NOT EXISTS public.contact_password_reset_tokens (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  contact_id  uuid        NOT NULL REFERENCES public.member_contacts(id) ON DELETE CASCADE,
  token_hash  text        NOT NULL,
  expires_at  timestamptz NOT NULL,
  used_at     timestamptz,
  token_type  text        NOT NULL DEFAULT 'invite'
                          CHECK (token_type IN ('invite', 'reset')),
  created_at  timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE  public.contact_password_reset_tokens IS '担当者向け招待・パスワードリセットトークン';
COMMENT ON COLUMN public.contact_password_reset_tokens.token_type IS '''invite'': 初回招待, ''reset'': パスワード再設定';

CREATE UNIQUE INDEX IF NOT EXISTS uq_contact_reset_tokens_token_hash
  ON public.contact_password_reset_tokens(token_hash);

CREATE INDEX IF NOT EXISTS idx_contact_reset_tokens_contact_id
  ON public.contact_password_reset_tokens(contact_id);

ALTER TABLE public.contact_password_reset_tokens ENABLE ROW LEVEL SECURITY;

-- 管理者は全操作可
DROP POLICY IF EXISTS "contact_reset_tokens_admin_all" ON public.contact_password_reset_tokens;
CREATE POLICY "contact_reset_tokens_admin_all"
  ON public.contact_password_reset_tokens
  FOR ALL TO authenticated
  USING  (public.cidm_is_admin())
  WITH CHECK (public.cidm_is_admin());

-- ============================================================
-- 2. cidm_admin_create_contact_invite
--    管理者が担当者の招待トークンを発行する
--    戻り値: token_hash（raw token は Edge Function 側で生成・管理）
-- ============================================================
DROP FUNCTION IF EXISTS public.cidm_admin_create_contact_invite(uuid, text, interval);

CREATE OR REPLACE FUNCTION public.cidm_admin_create_contact_invite(
  p_contact_id uuid,
  p_token_hash text,
  p_expires_in interval DEFAULT interval '72 hours',
  p_token_type text     DEFAULT 'invite'
)
RETURNS TABLE (
  contact_id  uuid,
  contact_name text,
  contact_email text,
  expires_at  timestamptz
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

  -- 未使用の旧トークンを無効化
  UPDATE public.contact_password_reset_tokens
  SET used_at = now()
  WHERE contact_id = p_contact_id
    AND used_at IS NULL;

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

COMMENT ON FUNCTION public.cidm_admin_create_contact_invite IS
  '管理者が担当者に招待またはパスワードリセットトークンを発行する。';

-- ============================================================
-- 3. cidm_consume_contact_password_reset
--    担当者がトークンを使ってパスワードを設定・変更する
--    member_staff_auth を UPSERT する
-- ============================================================
DROP FUNCTION IF EXISTS public.cidm_consume_contact_password_reset(text, text);

CREATE OR REPLACE FUNCTION public.cidm_consume_contact_password_reset(
  p_token_hash  text,
  p_new_password text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_token  public.contact_password_reset_tokens%rowtype;
  v_email  text;
BEGIN
  IF NULLIF(btrim(COALESCE(p_token_hash, '')), '') IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'token is required');
  END IF;

  IF NULLIF(COALESCE(p_new_password, ''), '') IS NULL OR length(p_new_password) < 8 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'password must be at least 8 characters');
  END IF;

  SELECT *
    INTO v_token
  FROM public.contact_password_reset_tokens
  WHERE token_hash = p_token_hash
    AND used_at IS NULL
    AND expires_at > now()
  ORDER BY created_at DESC
  LIMIT 1
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid or expired token');
  END IF;

  -- 担当者のメールアドレス取得（login_id として使用）
  SELECT email INTO v_email
  FROM public.member_contacts
  WHERE id = v_token.contact_id;

  IF v_email IS NULL OR btrim(v_email) = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'contact email not found');
  END IF;

  -- member_staff_auth に UPSERT（login_id = contact's email）
  INSERT INTO public.member_staff_auth
    (contact_id, login_id, password_hash, is_active, updated_at)
  VALUES
    (v_token.contact_id, LOWER(btrim(v_email)),
     extensions.crypt(p_new_password, extensions.gen_salt('bf')), true, now())
  ON CONFLICT (contact_id) DO UPDATE
  SET
    login_id     = LOWER(btrim(v_email)),
    password_hash = extensions.crypt(p_new_password, extensions.gen_salt('bf')),
    is_active    = true,
    updated_at   = now();

  -- トークンを消費済みにする
  UPDATE public.contact_password_reset_tokens
  SET used_at = now()
  WHERE id = v_token.id;

  RETURN jsonb_build_object('ok', true);
END;
$$;

COMMENT ON FUNCTION public.cidm_consume_contact_password_reset IS
  '担当者がトークンを使ってパスワードを設定する。member_staff_auth を UPSERT。';

-- 匿名ユーザーから呼び出し可（パスワードリセットページ用）
GRANT EXECUTE ON FUNCTION public.cidm_consume_contact_password_reset(text, text)
  TO anon, authenticated;

-- ============================================================
-- 4. cidm_request_contact_password_reset
--    担当者自身がパスワードリセットを要求する（セルフサービス用）
--    login_id(email) から contact を特定し、トークンを作成して返す
--    ※ Edge Function 側でメール送信する
-- ============================================================
DROP FUNCTION IF EXISTS public.cidm_request_contact_password_reset(text, text);

CREATE OR REPLACE FUNCTION public.cidm_request_contact_password_reset(
  p_login_id   text,
  p_token_hash text,
  p_expires_in interval DEFAULT interval '1 hour'
)
RETURNS TABLE (
  contact_id    uuid,
  contact_email text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_contact_id uuid;
  v_email      text;
BEGIN
  -- member_staff_auth で login_id 検索
  SELECT msa.contact_id, mc.email
    INTO v_contact_id, v_email
  FROM public.member_staff_auth msa
  JOIN public.member_contacts mc ON mc.id = msa.contact_id
  WHERE LOWER(msa.login_id) = LOWER(btrim(p_login_id))
    AND msa.is_active = true
  LIMIT 1;

  IF v_contact_id IS NULL THEN
    -- 存在しなくても成功扱い（列挙攻撃防止）
    RETURN;
  END IF;

  -- 旧トークン無効化
  UPDATE public.contact_password_reset_tokens
  SET used_at = now()
  WHERE contact_id = v_contact_id
    AND used_at IS NULL;

  -- 新トークン挿入
  INSERT INTO public.contact_password_reset_tokens
    (contact_id, token_hash, expires_at, token_type)
  VALUES
    (v_contact_id, p_token_hash, now() + p_expires_in, 'reset');

  RETURN QUERY SELECT v_contact_id, v_email;
END;
$$;

GRANT EXECUTE ON FUNCTION public.cidm_request_contact_password_reset(text, text, interval)
  TO anon, authenticated;

-- ============================================================
-- 5. cidm_admin_list_meeting_invites を member_contacts 対応に更新
--    送付先メールは receive_invite_mail=true の担当者全員
-- ============================================================
DROP FUNCTION IF EXISTS public.cidm_admin_list_meeting_invites(uuid);

CREATE OR REPLACE FUNCTION public.cidm_admin_list_meeting_invites(
  p_event_id uuid
)
RETURNS TABLE (
  invite_id      uuid,
  event_id       uuid,
  access_token   uuid,
  response_status text,
  memo           text,
  responded_at   timestamptz,
  member_id      uuid,
  division_flag  text,
  member_type    text,
  cidm_role      text,
  company_name   text,
  -- 主担当者情報（後方互換）
  staff_name     text,
  staff_email    text,
  staff_mobile   text,
  -- 会議案内送付対象担当者リスト (JSON)
  invite_contacts jsonb
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
  SELECT
    i.id,
    i.event_id,
    i.access_token,
    i.response_status,
    i.memo,
    i.responded_at,
    m.id,
    m.division_flag,
    m.member_type,
    m.cidm_role,
    m.company_name,
    -- 後方互換: 主担当者
    primary_mc.name,
    primary_mc.email,
    primary_mc.phone,
    -- 会議案内フラグが ON の担当者全員 (JSON 配列)
    COALESCE(
      (SELECT jsonb_agg(jsonb_build_object(
          'name',  mc2.name,
          'email', mc2.email,
          'phone', mc2.phone
        ) ORDER BY mc2.sort_order)
       FROM public.member_contacts mc2
       WHERE mc2.member_id = m.id
         AND mc2.receive_invite_mail = true
         AND mc2.email IS NOT NULL
         AND btrim(mc2.email) <> ''
      ),
      '[]'::jsonb
    )
  FROM public.meeting_event_invites i
  JOIN public.member m ON m.id = i.member_id
  LEFT JOIN public.member_contacts primary_mc
         ON primary_mc.member_id = m.id AND primary_mc.is_primary = true
  WHERE i.event_id = p_event_id
  ORDER BY m.company_name ASC;
$$;
