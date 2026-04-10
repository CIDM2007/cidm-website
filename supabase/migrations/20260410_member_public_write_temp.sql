-- TEMP: 認証バイパス期間のみ利用
-- member / member_contacts の更新系操作を anon, authenticated に一時開放
-- 本番復旧時は必ず削除すること

begin;

-- member: insert/update/delete を一時許可
do $$
begin
    if exists (
        select 1 from information_schema.tables
        where table_schema = 'public' and table_name = 'member'
    ) then
        execute 'alter table public.member enable row level security';

        execute 'drop policy if exists "member_insert_public_temp" on public.member';
        execute $pol$
            create policy "member_insert_public_temp"
            on public.member
            for insert
            to anon, authenticated
            with check (true)
        $pol$;

        execute 'drop policy if exists "member_update_public_temp" on public.member';
        execute $pol$
            create policy "member_update_public_temp"
            on public.member
            for update
            to anon, authenticated
            using (true)
            with check (true)
        $pol$;

        execute 'drop policy if exists "member_delete_public_temp" on public.member';
        execute $pol$
            create policy "member_delete_public_temp"
            on public.member
            for delete
            to anon, authenticated
            using (true)
        $pol$;
    end if;
end;
$$;

-- member_contacts: insert/update/delete を一時許可
do $$
begin
    if exists (
        select 1 from information_schema.tables
        where table_schema = 'public' and table_name = 'member_contacts'
    ) then
        execute 'alter table public.member_contacts enable row level security';

        execute 'drop policy if exists "member_contacts_insert_public_temp" on public.member_contacts';
        execute $pol$
            create policy "member_contacts_insert_public_temp"
            on public.member_contacts
            for insert
            to anon, authenticated
            with check (true)
        $pol$;

        execute 'drop policy if exists "member_contacts_update_public_temp" on public.member_contacts';
        execute $pol$
            create policy "member_contacts_update_public_temp"
            on public.member_contacts
            for update
            to anon, authenticated
            using (true)
            with check (true)
        $pol$;

        execute 'drop policy if exists "member_contacts_delete_public_temp" on public.member_contacts';
        execute $pol$
            create policy "member_contacts_delete_public_temp"
            on public.member_contacts
            for delete
            to anon, authenticated
            using (true)
        $pol$;
    end if;
end;
$$;

commit;
