alter table public.member
  add column if not exists is_officer boolean not null default false;

update public.member
set is_officer = true
where member_type = '役員';

update public.member
set member_type = null
where member_type = '役員';

comment on column public.member.is_officer is '役員フラグ: 役員の場合 true';

comment on column public.member.member_type is 'CIDM会員種別: 正会員 / 準会員 / 賛助会員 / 賛助 / NULL(事務局等)';
