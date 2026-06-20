-- ============================================================
-- member_contacts 拡張: 担当者単位ログイン設計への移行
-- 追加カラム: department, job_title, phone_direct,
--             is_cidm_contact (1社1名 UNIQUE), biko
-- 既存データ移行: member.department/job_title/biko → 主担当者レコード
-- ============================================================

-- ============================================================
-- 1. member_contacts にカラム追加
-- ============================================================
ALTER TABLE public.member_contacts
  ADD COLUMN IF NOT EXISTS department     text,
  ADD COLUMN IF NOT EXISTS job_title      text,
  ADD COLUMN IF NOT EXISTS phone_direct   text,
  ADD COLUMN IF NOT EXISTS is_cidm_contact boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS biko           text;

COMMENT ON COLUMN public.member_contacts.department      IS '担当者の部署';
COMMENT ON COLUMN public.member_contacts.job_title       IS '担当者の役職';
COMMENT ON COLUMN public.member_contacts.phone_direct    IS '担当者の直通電話番号（固定）';
COMMENT ON COLUMN public.member_contacts.is_cidm_contact IS 'CIDM担当者フラグ。1社につき1名のみ true にすること。';
COMMENT ON COLUMN public.member_contacts.biko            IS '担当者備考';

-- ============================================================
-- 2. CIDM担当者フラグは1社1名のみ（部分UNIQUE制約）
-- ============================================================
CREATE UNIQUE INDEX IF NOT EXISTS member_contacts_cidm_contact_unique
  ON public.member_contacts (member_id)
  WHERE is_cidm_contact = true;

-- ============================================================
-- 3. 既存データ移行: member.department / job_title / biko → 主担当者
-- ============================================================
UPDATE public.member_contacts mc
SET
  department = COALESCE(mc.department, m.department),
  job_title  = COALESCE(mc.job_title,  m.job_title),
  biko       = COALESCE(mc.biko,       m.biko)
FROM public.member m
WHERE mc.member_id = m.id
  AND mc.is_primary = true
  AND (m.department IS NOT NULL OR m.job_title IS NOT NULL OR m.biko IS NOT NULL);

-- ============================================================
-- 4. 既存データ移行: cidm_role が設定されている会社の主担当者を
--    is_cidm_contact = true にセット
-- ============================================================
UPDATE public.member_contacts mc
SET is_cidm_contact = true
FROM public.member m
WHERE mc.member_id = m.id
  AND mc.is_primary = true
  AND m.cidm_role IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM public.member_contacts mc2
    WHERE mc2.member_id = m.id AND mc2.is_cidm_contact = true
  );

-- ============================================================
-- 5. 安全ガード: 主担当者レコードが存在しない会員に対してデフォルト行を生成
-- ============================================================
INSERT INTO public.member_contacts (member_id, name, phone, email, is_primary, sort_order)
SELECT
  m.id,
  m.staff_name,
  m.staff_mobile,
  m.staff_email,
  true,
  0
FROM public.member m
WHERE
  NOT EXISTS (SELECT 1 FROM public.member_contacts mc WHERE mc.member_id = m.id)
  AND (m.staff_name IS NOT NULL OR m.staff_email IS NOT NULL);

-- ============================================================
-- 6. receive_invite_mail / receive_invoice_mail カラムが
--    まだ存在しない場合に追加（旧環境向け）
-- ============================================================
ALTER TABLE public.member_contacts
  ADD COLUMN IF NOT EXISTS receive_invite_mail  boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS receive_invoice_mail boolean NOT NULL DEFAULT true;

COMMENT ON COLUMN public.member_contacts.receive_invite_mail  IS '会議案内メール送付対象フラグ';
COMMENT ON COLUMN public.member_contacts.receive_invoice_mail IS '会費請求メール送付対象フラグ';
