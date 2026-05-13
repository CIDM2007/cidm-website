alter table public.member_contacts
  add column if not exists receive_invoice_mail boolean not null default true;

comment on column public.member_contacts.receive_invoice_mail is '会費請求メールの送信対象に含めるかどうか';
