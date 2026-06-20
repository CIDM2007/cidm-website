begin;

grant execute on function public.cidm_submit_application(jsonb)
  to anon, authenticated, service_role;

comment on function public.cidm_submit_application(jsonb) is
  '公開申込を member/member_contacts へ仮登録するRPC。公開フォームからの実行を許可。';

commit;