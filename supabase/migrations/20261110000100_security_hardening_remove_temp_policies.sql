-- 1) 20260410000600 / 20260410000700 で作った一時ポリシー（anon に member / member_contacts の
--    読み書きを全許可）を確実に削除する。本番では削除済みだが、マイグレーションから DB を
--    作り直すと再作成されてしまうため、ここで明示的に消す。
drop policy if exists "member_select_public_temp" on public.member;
drop policy if exists "member_insert_public_temp" on public.member;
drop policy if exists "member_update_public_temp" on public.member;
drop policy if exists "member_delete_public_temp" on public.member;
drop policy if exists "member_contacts_select_public_temp" on public.member_contacts;
drop policy if exists "member_contacts_insert_public_temp" on public.member_contacts;
drop policy if exists "member_contacts_update_public_temp" on public.member_contacts;
drop policy if exists "member_contacts_delete_public_temp" on public.member_contacts;

-- 2) トークン無しで「ログインID＋登録メール」だけでパスワードを書き換えられる旧関数。
--    現在の画面は Supabase Auth とメールのワンタイムURLを使っており未使用のため、外部から呼べなくする。
revoke execute on function public.cidm_member_reset_password_self_service(text, text, text) from public, anon, authenticated;

-- 3) 旧ログイン関数（現在は Supabase Auth に移行済みで未使用）。パスワード総当たりの窓口になるため閉じる。
revoke execute on function public.cidm_member_login(text, text) from public, anon, authenticated;

-- 4) レート制限カウンタの掃除はサーバー内部（service_role）専用。
revoke execute on function public.cidm_cleanup_rate_limit_counters() from anon, authenticated;
