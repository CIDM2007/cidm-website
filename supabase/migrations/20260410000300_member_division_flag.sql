-- member table: 区分フラグ追加（会員 / 関係者）

alter table public.member
  add column if not exists division_flag text;

update public.member
set division_flag = '会員'
where division_flag is null or btrim(division_flag) = '';

alter table public.member
  alter column division_flag set default '会員';

alter table public.member
  alter column division_flag set not null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'member_division_flag_chk'
  ) then
    alter table public.member
      add constraint member_division_flag_chk
      check (division_flag in ('会員', '関係者'));
  end if;
end;
$$;

comment on column public.member.division_flag is '区分フラグ: 会員 / 関係者';
