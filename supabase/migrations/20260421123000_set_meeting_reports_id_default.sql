create extension if not exists pgcrypto with schema extensions;

do $$
declare
    v_id_type text;
    v_seq_name text;
begin
    select c.data_type
      into v_id_type
      from information_schema.columns c
     where c.table_schema = 'public'
       and c.table_name = 'meeting_reports'
       and c.column_name = 'id';

    if v_id_type is null then
        raise notice 'public.meeting_reports.id が見つからないためスキップします';
        return;
    end if;

    if v_id_type = 'uuid' then
        alter table public.meeting_reports
            alter column id set default gen_random_uuid();
        return;
    end if;

    if v_id_type in ('integer', 'bigint', 'smallint') then
        select pg_get_serial_sequence('public.meeting_reports', 'id')
          into v_seq_name;

        if v_seq_name is null then
            v_seq_name := 'public.meeting_reports_id_seq';
            execute 'create sequence if not exists public.meeting_reports_id_seq';
            execute 'alter sequence public.meeting_reports_id_seq owned by public.meeting_reports.id';
        end if;

        execute format(
            'alter table public.meeting_reports alter column id set default nextval(%L)',
            v_seq_name
        );

        execute format(
            'select setval(%L, coalesce((select max(id) from public.meeting_reports), 0) + 1, false)',
            v_seq_name
        );
        return;
    end if;

    raise notice 'public.meeting_reports.id の型 % は未対応です', v_id_type;
end
$$;
