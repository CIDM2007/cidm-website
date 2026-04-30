alter table public.meeting_invite_mail_logs
  drop constraint if exists meeting_invite_mail_logs_send_mode_check;

alter table public.meeting_invite_mail_logs
  add constraint meeting_invite_mail_logs_send_mode_check
  check (send_mode in ('all', 'pending', 'retry'));
