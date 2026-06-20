-- ============================================================
-- 会費請求書表示: snapshot 未設定時は member.staff_* ではなく
-- member_contacts の主担当者へフォールバック
-- ============================================================

DROP FUNCTION IF EXISTS public.cidm_get_membership_invoice_by_token(text);

CREATE OR REPLACE FUNCTION public.cidm_get_membership_invoice_by_token(
    p_token text
)
RETURNS TABLE (
    issue_id uuid,
    invoice_no text,
    billing_year integer,
    billing_month integer,
    due_date date,
    amount integer,
    company_name text,
    staff_name text,
    staff_email text,
    member_type text,
    send_status text,
    issued_at timestamptz
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
    select
        i.id,
        i.invoice_no,
        i.billing_year,
        i.billing_month,
        i.due_date,
        i.amount,
        coalesce(i.company_name_snapshot, m.company_name),
        coalesce(i.staff_name_snapshot, mc.name, m.staff_name),
        coalesce(i.staff_email_snapshot, mc.email, m.staff_email),
        coalesce(i.member_type_snapshot, m.member_type),
        i.send_status,
        coalesce(i.sent_at, i.created_at)
    from public.membership_invoice_issues i
    left join public.member m
      on m.id = i.member_id
    left join public.member_contacts mc
      on mc.member_id = m.id and mc.is_primary = true
    where i.access_token = p_token::uuid
    limit 1;
$$;

grant execute on function public.cidm_get_membership_invoice_by_token(text)
    to anon, authenticated;
