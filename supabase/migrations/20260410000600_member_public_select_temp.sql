-- TEMP: 管理画面の認証バイパス期間のみ使用
-- member / member_contacts を anon でも SELECT 可能にする
-- 本番復旧時はこのポリシーを削除すること

begin;

do $$
begin
    if exists (
        select 1 from information_schema.tables
        where table_schema = 'public' and table_name = 'member'
    ) then
        execute 'alter table public.member enable row level security';
        execute 'drop policy if exists "member_select_public_temp" on public.member';
        execute $pol$
            create policy "member_select_public_temp"
            on public.member
            for select
            to anon, authenticated
            using (true)
        $pol$;
    end if;
end;
$$;

do $$
begin
    if exists (
        select 1 from information_schema.tables
        where table_schema = 'public' and table_name = 'member_contacts'
    ) then
        execute 'alter table public.member_contacts enable row level security';
        execute 'drop policy if exists "member_contacts_select_public_temp" on public.member_contacts';
        execute $pol$
            create policy "member_contacts_select_public_temp"
            on public.member_contacts
            for select
            to anon, authenticated
            using (true)
        $pol$;
    end if;
end;
$$;

commit;
