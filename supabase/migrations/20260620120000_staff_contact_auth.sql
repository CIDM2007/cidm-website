-- Staff (Contact) Authentication System
-- 担当者が独立してログイン可能なシステム
-- member_contacts ベースのログイン認証テーブル

create extension if not exists pgcrypto with schema extensions;

-- ============================================================
-- 1. member_staff_auth テーブル作成
--    （担当者ごとのログイン認証情報）
-- ============================================================
CREATE TABLE IF NOT EXISTS public.member_staff_auth (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    contact_id UUID NOT NULL UNIQUE REFERENCES public.member_contacts(id) ON DELETE CASCADE,
    login_id TEXT NOT NULL UNIQUE,
    password_hash TEXT,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT member_staff_auth_login_id_email_format
        CHECK (login_id ~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}$')
);

COMMENT ON TABLE public.member_staff_auth IS '担当者（contact）のログイン認証情報。1contact = 1login_id。';
COMMENT ON COLUMN public.member_staff_auth.contact_id IS '紐付ける担当者ID（member_contacts.id）';
COMMENT ON COLUMN public.member_staff_auth.login_id IS 'ログインID（メール形式）';
COMMENT ON COLUMN public.member_staff_auth.password_hash IS 'パスワードハッシュ（bcrypt）';
COMMENT ON COLUMN public.member_staff_auth.is_active IS '有効フラグ';

CREATE INDEX IF NOT EXISTS member_staff_auth_contact_id_idx
    ON public.member_staff_auth(contact_id);

CREATE INDEX IF NOT EXISTS member_staff_auth_login_id_idx
    ON public.member_staff_auth(LOWER(login_id))
    WHERE is_active = true;

-- ============================================================
-- 2. RLS ポリシー設定
-- ============================================================
ALTER TABLE public.member_staff_auth ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "member_staff_auth_admin_all" ON public.member_staff_auth;
CREATE POLICY "member_staff_auth_admin_all"
    ON public.member_staff_auth
    FOR ALL
    TO authenticated
    USING (public.cidm_is_admin())
    WITH CHECK (public.cidm_is_admin());

-- ============================================================
-- 3. cidm_staff_login RPC 関数
--    担当者用ログイン認証（会社の権限レベルを返す）
-- ============================================================
DROP FUNCTION IF EXISTS public.cidm_staff_login(text, text);

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
    -- ログインIDで認証レコードを検索（小文字比較）
    SELECT id, password_hash
    INTO v_auth_id, v_password_hash
    FROM public.member_staff_auth
    WHERE LOWER(login_id) = LOWER(btrim(p_login_id))
      AND is_active = true
      AND password_hash IS NOT NULL
    LIMIT 1;

    -- ユーザーが見つからない
    IF v_auth_id IS NULL THEN
        RAISE EXCEPTION 'Invalid credentials';
    END IF;

    -- パスワード検証
    IF NOT (extensions.crypt(p_password, v_password_hash) = v_password_hash) THEN
        RAISE EXCEPTION 'Invalid credentials';
    END IF;

    -- 認証成功：該当する担当者と会社情報を返す
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
    JOIN public.member_contacts mc ON msa.contact_id = mc.id
    JOIN public.member m ON mc.member_id = m.id
    WHERE msa.id = v_auth_id
    LIMIT 1;
END;
$$;

COMMENT ON FUNCTION public.cidm_staff_login(text, text) IS '担当者用ログイン認証。login_idとpasswordで検証し、成功時は担当者・会社情報を返す。';

-- ============================================================
-- 4. 管理者用：担当者ログイン情報設定 RPC
-- ============================================================
DROP FUNCTION IF EXISTS public.cidm_admin_set_staff_login(uuid, text, text);

CREATE OR REPLACE FUNCTION public.cidm_admin_set_staff_login(
    p_contact_id UUID,
    p_login_id TEXT,
    p_password TEXT DEFAULT NULL
)
RETURNS TABLE (
    login_id TEXT,
    has_password BOOLEAN,
    updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_login_id TEXT;
    v_password_hash TEXT;
BEGIN
    -- 管理者チェック
    IF NOT COALESCE(public.cidm_is_admin(), false) THEN
        RAISE EXCEPTION 'admin access required';
    END IF;

    -- contact_id 存在チェック
    IF NOT EXISTS (SELECT 1 FROM public.member_contacts WHERE id = p_contact_id) THEN
        RAISE EXCEPTION 'contact not found';
    END IF;

    v_login_id := NULLIF(btrim(p_login_id), '');
    IF v_login_id IS NULL THEN
        RAISE EXCEPTION 'login_id is required';
    END IF;

    -- パスワード処理
    IF p_password IS NOT NULL THEN
        v_password_hash := extensions.crypt(p_password, extensions.gen_salt('bf'));
    ELSE
        v_password_hash := NULL;
    END IF;

    -- Upsert: 既存なら更新、なければ挿入
    INSERT INTO public.member_staff_auth (contact_id, login_id, password_hash, updated_at)
    VALUES (p_contact_id, v_login_id, v_password_hash, now())
    ON CONFLICT (contact_id) DO UPDATE
    SET
        login_id = EXCLUDED.login_id,
        password_hash = COALESCE(EXCLUDED.password_hash, member_staff_auth.password_hash),
        updated_at = now();

    -- 結果を返す
    RETURN QUERY
    SELECT
        msa.login_id,
        msa.password_hash IS NOT NULL,
        msa.updated_at
    FROM public.member_staff_auth msa
    WHERE msa.contact_id = p_contact_id;
END;
$$;

COMMENT ON FUNCTION public.cidm_admin_set_staff_login(uuid, text, text) IS '管理者が担当者のログイン情報を設定。contact_idで対象担当者を特定。';

-- ============================================================
-- 5. 担当者ログイン情報取得 RPC（管理画面用）
-- ============================================================
DROP FUNCTION IF EXISTS public.cidm_get_staff_login_settings(uuid);

CREATE OR REPLACE FUNCTION public.cidm_get_staff_login_settings(
    p_contact_id UUID
)
RETURNS TABLE (
    contact_id UUID,
    staff_name TEXT,
    login_id TEXT,
    has_password BOOLEAN,
    is_active BOOLEAN,
    updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
    -- 管理者チェック
    IF NOT COALESCE(public.cidm_is_admin(), false) THEN
        RAISE EXCEPTION 'admin access required';
    END IF;

    RETURN QUERY
    SELECT
        mc.id,
        mc.name,
        msa.login_id,
        msa.password_hash IS NOT NULL,
        msa.is_active,
        msa.updated_at
    FROM public.member_contacts mc
    LEFT JOIN public.member_staff_auth msa ON mc.id = msa.contact_id
    WHERE mc.id = p_contact_id;
END;
$$;

COMMENT ON FUNCTION public.cidm_get_staff_login_settings(uuid) IS '管理者が担当者のログイン設定状況を確認。';

-- ============================================================
-- 6. audit_log テーブル（監査ログ用）
-- ============================================================
CREATE TABLE IF NOT EXISTS public.audit_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_type VARCHAR NOT NULL, -- 'member' or 'staff'
    actor_id UUID,
    actor_name TEXT,
    action VARCHAR NOT NULL,
    resource_type VARCHAR,
    resource_id UUID,
    details JSONB,
    ip_address VARCHAR,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.audit_log IS '監査ログ。誰がいつ何をしたかを追跡。';

CREATE INDEX IF NOT EXISTS audit_log_actor_id_idx
    ON public.audit_log(actor_id);

CREATE INDEX IF NOT EXISTS audit_log_created_at_idx
    ON public.audit_log(created_at);

ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "audit_log_admin_read" ON public.audit_log;
CREATE POLICY "audit_log_admin_read"
    ON public.audit_log
    FOR SELECT
    TO authenticated
    USING (public.cidm_is_admin());
