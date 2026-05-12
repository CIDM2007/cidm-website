alter table public.member_contacts
  add column if not exists receive_invite_mail boolean not null default true;

comment on column public.member_contacts.receive_invite_mail is '会議案内メールの送信対象に含めるかどうか';
