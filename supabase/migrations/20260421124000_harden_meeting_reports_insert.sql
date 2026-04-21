do $$
begin
    if exists (
        select 1
        from information_schema.columns
        where table_schema = 'public'
          and table_name = 'meeting_reports'
          and column_name = 'category'
          and data_type = 'text'
    ) then
        alter table public.meeting_reports
            alter column category set default '会議報告';
    end if;
end
$$;

create or replace function public.cidm_meeting_reports_fill_id_on_null()
returns trigger
language plpgsql
as $$
begin
    if new.id is null then
        new.id := nextval('public.meeting_reports_id_seq');
    end if;

    if new.category is null or btrim(new.category) = '' then
        new.category := '会議報告';
    end if;

    return new;
end;
$$;

drop trigger if exists trg_meeting_reports_fill_id_on_null on public.meeting_reports;

create trigger trg_meeting_reports_fill_id_on_null
before insert on public.meeting_reports
for each row
execute function public.cidm_meeting_reports_fill_id_on_null();
