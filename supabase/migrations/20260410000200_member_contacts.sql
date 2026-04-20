-- CIDM member_contacts: 担当者の複数管理対応
-- 適用方法: Supabase Dashboard > SQL Editor に貼り付けて実行
--           または: npx supabase db push

-- ============================================================
-- 1. member テーブルにカラム追加
-- ============================================================
ALTER TABLE public.member
  ADD COLUMN IF NOT EXISTS member_type text,   -- '役員' / '正会員' / NULL
  ADD COLUMN IF NOT EXISTS cidm_role   text,   -- '副理事長' / '理事' / '監事' 等
  ADD COLUMN IF NOT EXISTS fax_number  text;   -- FAX番号

COMMENT ON COLUMN public.member.member_type IS 'CIDM会員種別: 役員 / 正会員 / NULL(事務局等)';
COMMENT ON COLUMN public.member.cidm_role   IS 'CIDM役職: 副理事長, 理事, 監事, 事務局長 等';
COMMENT ON COLUMN public.member.fax_number  IS 'FAX番号';

-- ============================================================
-- 2. member_contacts テーブル新規作成（担当者情報, 複数可）
-- ============================================================
CREATE TABLE IF NOT EXISTS public.member_contacts (
  id         uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  member_id  uuid        NOT NULL REFERENCES public.member(id) ON DELETE CASCADE,
  name       text,                             -- 担当者名
  phone      text,                             -- 担当者電話番号
  email      text,                             -- 担当者メールアドレス
  is_primary boolean     NOT NULL DEFAULT false, -- 主担当者フラグ (1社につき1名)
  sort_order int         NOT NULL DEFAULT 0,   -- 表示順
  created_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE  public.member_contacts              IS '会員担当者テーブル。1社に対して複数担当者を登録可能。';
COMMENT ON COLUMN public.member_contacts.is_primary   IS '主担当者フラグ。1社につき1名のみ true にすること。';
COMMENT ON COLUMN public.member_contacts.sort_order   IS '担当者の表示順 (昇順)。';

-- インデックス
CREATE INDEX IF NOT EXISTS member_contacts_member_id_idx
  ON public.member_contacts (member_id);

-- ============================================================
-- 3. RLS 設定（管理者のみ全操作可）
-- ============================================================
ALTER TABLE public.member_contacts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "member_contacts_admin_all" ON public.member_contacts;
CREATE POLICY "member_contacts_admin_all"
  ON public.member_contacts
  FOR ALL
  TO authenticated
  USING (public.cidm_is_admin())
  WITH CHECK (public.cidm_is_admin());

-- ============================================================
-- 4. 既存データ移行
--    member.staff_name / staff_mobile / staff_email を
--    member_contacts に is_primary=true で移行する
-- ============================================================
INSERT INTO public.member_contacts (member_id, name, phone, email, is_primary, sort_order)
SELECT
  id,
  staff_name,
  staff_mobile,
  staff_email,
  true,
  0
FROM public.member
WHERE
  staff_name IS NOT NULL
  AND btrim(staff_name) <> '';
