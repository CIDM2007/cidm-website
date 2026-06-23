-- Remove PUBLIC execution from admin-only SECURITY DEFINER functions.
-- Also drop the broad storage.objects select policy that enables bucket listing.

revoke execute on function public.cidm_admin_create_contact_invite(uuid, text, interval, text) from public;
revoke execute on function public.cidm_admin_create_contact_invite(uuid, text, interval, text) from anon;
grant execute on function public.cidm_admin_create_contact_invite(uuid, text, interval, text) to authenticated;

revoke execute on function public.cidm_admin_list_meeting_events() from public;
revoke execute on function public.cidm_admin_list_meeting_events() from anon;
grant execute on function public.cidm_admin_list_meeting_events() to authenticated;

revoke execute on function public.cidm_admin_list_meeting_invites(uuid) from public;
revoke execute on function public.cidm_admin_list_meeting_invites(uuid) from anon;
grant execute on function public.cidm_admin_list_meeting_invites(uuid) to authenticated;

revoke execute on function public.cidm_admin_list_members(boolean, boolean, boolean) from public;
revoke execute on function public.cidm_admin_list_members(boolean, boolean, boolean) from anon;
grant execute on function public.cidm_admin_list_members(boolean, boolean, boolean) to authenticated;

revoke execute on function public.cidm_admin_set_member_login(uuid, text, text) from public;
revoke execute on function public.cidm_admin_set_member_login(uuid, text, text) from anon;
grant execute on function public.cidm_admin_set_member_login(uuid, text, text) to authenticated;

revoke execute on function public.cidm_get_member_login_settings(uuid) from public;
revoke execute on function public.cidm_get_member_login_settings(uuid) from anon;
grant execute on function public.cidm_get_member_login_settings(uuid) to authenticated;

revoke execute on function public.cidm_admin_set_staff_login(uuid, text, text) from public;
revoke execute on function public.cidm_admin_set_staff_login(uuid, text, text) from anon;
grant execute on function public.cidm_admin_set_staff_login(uuid, text, text) to authenticated;

revoke execute on function public.cidm_get_staff_login_settings(uuid) from public;
revoke execute on function public.cidm_get_staff_login_settings(uuid) from anon;
grant execute on function public.cidm_get_staff_login_settings(uuid) to authenticated;

revoke execute on function public.cidm_set_member_app_role(uuid, text) from public;
revoke execute on function public.cidm_set_member_app_role(uuid, text) from anon;
grant execute on function public.cidm_set_member_app_role(uuid, text) to authenticated;

revoke execute on function public.cidm_create_meeting_event(text, text, timestamptz, text, text, text, text, uuid[], text[], text[], text[], text, text) from public;
revoke execute on function public.cidm_create_meeting_event(text, text, timestamptz, text, text, text, text, uuid[], text[], text[], text[], text, text) from anon;
grant execute on function public.cidm_create_meeting_event(text, text, timestamptz, text, text, text, text, uuid[], text[], text[], text[], text, text) to authenticated;

revoke execute on function public.cidm_create_meeting_event(text, text, timestamptz, text, text, text, text, uuid[], text[], text[], text[]) from public;
revoke execute on function public.cidm_create_meeting_event(text, text, timestamptz, text, text, text, text, uuid[], text[], text[], text[]) from anon;
grant execute on function public.cidm_create_meeting_event(text, text, timestamptz, text, text, text, text, uuid[], text[], text[], text[]) to authenticated;

drop policy if exists "meeting_report_assets_select_public" on storage.objects;