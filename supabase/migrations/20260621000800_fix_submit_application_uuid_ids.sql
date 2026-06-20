begin;

drop function if exists public.cidm_submit_application(jsonb);

create function public.cidm_submit_application(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payload jsonb := coalesce(p_payload, '{}'::jsonb);
  v_company_name text := nullif(btrim(coalesce(v_payload->>'company_name', v_payload->>'company', v_payload->>'companyName', v_payload->>'name')), '');
  v_company_name_kana text := nullif(btrim(coalesce(v_payload->>'company_name_kana', v_payload->>'companyKana', v_payload->>'company_name_ruby')), '');
  v_member_division text := nullif(btrim(coalesce(v_payload->>'member_division', v_payload->>'division', v_payload->>'memberDivision')), '');
  v_postal_code text := nullif(btrim(coalesce(v_payload->>'postal_code', v_payload->>'zip_code', v_payload->>'postalCode')), '');
  v_address text := nullif(btrim(coalesce(v_payload->>'address', v_payload->>'company_address')), '');
  v_phone text := nullif(btrim(coalesce(v_payload->>'phone', v_payload->>'tel', v_payload->>'telephone')), '');
  v_fax text := nullif(btrim(coalesce(v_payload->>'fax', v_payload->>'fax_number')), '');
  v_website text := nullif(btrim(coalesce(v_payload->>'website', v_payload->>'url', v_payload->>'company_url')), '');
  v_member_note text := nullif(btrim(coalesce(v_payload->>'member_note', v_payload->>'remarks', v_payload->>'note', v_payload->>'biko')), '');
  v_contact_name text := nullif(btrim(coalesce(v_payload->>'contact_name', v_payload->>'staff_name', v_payload->>'name', v_payload->>'applicant_name')), '');
  v_contact_email text := nullif(lower(btrim(coalesce(v_payload->>'contact_email', v_payload->>'email', v_payload->>'staff_email', v_payload->>'applicant_email'))), '');
  v_department text := nullif(btrim(coalesce(v_payload->>'department', v_payload->>'staff_department')), '');
  v_job_title text := nullif(btrim(coalesce(v_payload->>'job_title', v_payload->>'staff_job_title', v_payload->>'position')), '');
  v_phone_direct text := nullif(btrim(coalesce(v_payload->>'phone_direct', v_payload->>'direct_phone', v_payload->>'staff_phone_direct')), '');
  v_phone_mobile text := nullif(btrim(coalesce(v_payload->>'phone_mobile', v_payload->>'mobile', v_payload->>'mobile_phone', v_payload->>'staff_phone_mobile')), '');
  v_contact_note text := nullif(btrim(coalesce(v_payload->>'contact_note', v_payload->>'staff_note', v_payload->>'staff_biko', v_payload->>'biko', v_payload->>'remarks')), '');
  v_is_cidm_contact boolean := lower(coalesce(v_payload->>'is_cidm_contact', v_payload->>'cidm_contact', v_payload->>'isCidmContact', 'false')) in ('1', 'true', 't', 'yes', 'on');
  v_receive_bulletin_mail boolean := lower(coalesce(v_payload->>'receive_bulletin_mail', v_payload->>'receive_news_mail', 'false')) in ('1', 'true', 't', 'yes', 'on');
  v_receive_invoice_mail boolean := lower(coalesce(v_payload->>'receive_invoice_mail', 'false')) in ('1', 'true', 't', 'yes', 'on');
  v_receive_event_mail boolean := lower(coalesce(v_payload->>'receive_event_mail', v_payload->>'receive_meeting_mail', 'false')) in ('1', 'true', 't', 'yes', 'on');
  v_member_payload jsonb;
  v_contact_payload jsonb;
  v_insert_columns text;
  v_insert_values text;
  v_set_clause text;
  v_member_id uuid;
  v_existing_member_id uuid;
  v_existing_contact_id uuid;
  v_mode text := 'created';
begin
  if v_company_name is null then
    raise exception 'company_name is required';
  end if;

  if v_contact_name is null then
    raise exception 'contact_name is required';
  end if;

  if v_contact_email is null then
    raise exception 'contact_email is required';
  end if;

  select mc.member_id, mc.id
    into v_existing_member_id, v_existing_contact_id
  from public.member_contacts mc
  join public.member m
    on m.id = mc.member_id
  where lower(coalesce(mc.email, '')) = v_contact_email
    and lower(
      coalesce(
        nullif(to_jsonb(m)->>'company_name', ''),
        nullif(to_jsonb(m)->>'name', ''),
        ''
      )
    ) = lower(v_company_name)
    and coalesce(nullif(to_jsonb(m)->>'application_status', ''), '承認済') = '未審査'
  order by coalesce(mc.is_primary, false) desc, mc.id desc
  limit 1;

  v_member_payload := jsonb_strip_nulls(jsonb_build_object(
    'name', v_company_name,
    'company_name', v_company_name,
    'name_kana', v_company_name_kana,
    'company_name_kana', v_company_name_kana,
    'member_division', v_member_division,
    'division', v_member_division,
    'postal_code', v_postal_code,
    'zip_code', v_postal_code,
    'address', v_address,
    'tel', v_phone,
    'phone', v_phone,
    'fax', v_fax,
    'website', v_website,
    'url', v_website,
    'note', v_member_note,
    'biko', v_member_note,
    'application_status', '未審査',
    'application_submitted_at', now(),
    'application_source', '公開申込',
    'staff_name', v_contact_name,
    'staff_email', v_contact_email,
    'staff_department', v_department,
    'staff_job_title', v_job_title,
    'staff_phone_direct', v_phone_direct,
    'staff_phone_mobile', v_phone_mobile,
    'staff_biko', v_contact_note
  ));

  if v_existing_member_id is null then
    select string_agg(format('%I', c.column_name), ', ' order by c.ordinal_position),
           string_agg(format('%L', e.value #>> '{}'), ', ' order by c.ordinal_position)
      into v_insert_columns, v_insert_values
    from jsonb_each(v_member_payload) e(key, value)
    join information_schema.columns c
      on c.table_schema = 'public'
     and c.table_name = 'member'
     and c.column_name = e.key
    where e.value <> 'null'::jsonb;

    if v_insert_columns is null then
      raise exception 'No member columns matched application payload';
    end if;

    execute format(
      'insert into public.member (%s) values (%s) returning id',
      v_insert_columns,
      v_insert_values
    )
    into v_member_id;
  else
    select string_agg(format('%I = %L', c.column_name, e.value #>> '{}'), ', ' order by c.ordinal_position)
      into v_set_clause
    from jsonb_each(v_member_payload) e(key, value)
    join information_schema.columns c
      on c.table_schema = 'public'
     and c.table_name = 'member'
     and c.column_name = e.key
    where e.value <> 'null'::jsonb;

    if v_set_clause is null then
      raise exception 'No member columns matched application payload';
    end if;

    execute format(
      'update public.member set %s where id = %L returning id',
      v_set_clause,
      v_existing_member_id
    )
    into v_member_id;

    v_mode := 'updated';
  end if;

  v_contact_payload := jsonb_strip_nulls(jsonb_build_object(
    'member_id', v_member_id,
    'name', v_contact_name,
    'contact_name', v_contact_name,
    'email', v_contact_email,
    'department', v_department,
    'job_title', v_job_title,
    'phone_direct', v_phone_direct,
    'direct_phone', v_phone_direct,
    'phone_mobile', v_phone_mobile,
    'mobile', v_phone_mobile,
    'is_primary', true,
    'sort_order', 1,
    'is_cidm_contact', v_is_cidm_contact,
    'receive_bulletin_mail', v_receive_bulletin_mail,
    'receive_invoice_mail', v_receive_invoice_mail,
    'receive_event_mail', v_receive_event_mail,
    'receive_meeting_mail', v_receive_event_mail,
    'biko', v_contact_note,
    'note', v_contact_note
  ));

  if v_existing_contact_id is null then
    select mc.id
      into v_existing_contact_id
    from public.member_contacts mc
    where mc.member_id = v_member_id
      and lower(coalesce(mc.email, '')) = v_contact_email
    order by coalesce(mc.is_primary, false) desc, mc.id desc
    limit 1;
  end if;

  if v_existing_contact_id is null then
    select string_agg(format('%I', c.column_name), ', ' order by c.ordinal_position),
           string_agg(format('%L', e.value #>> '{}'), ', ' order by c.ordinal_position)
      into v_insert_columns, v_insert_values
    from jsonb_each(v_contact_payload) e(key, value)
    join information_schema.columns c
      on c.table_schema = 'public'
     and c.table_name = 'member_contacts'
     and c.column_name = e.key
    where e.value <> 'null'::jsonb;

    if v_insert_columns is null then
      raise exception 'No member_contacts columns matched application payload';
    end if;

    execute format(
      'insert into public.member_contacts (%s) values (%s)',
      v_insert_columns,
      v_insert_values
    );
  else
    select string_agg(format('%I = %L', c.column_name, e.value #>> '{}'), ', ' order by c.ordinal_position)
      into v_set_clause
    from jsonb_each(v_contact_payload) e(key, value)
    join information_schema.columns c
      on c.table_schema = 'public'
     and c.table_name = 'member_contacts'
     and c.column_name = e.key
    where e.value <> 'null'::jsonb
      and e.key <> 'member_id';

    if v_set_clause is null then
      raise exception 'No member_contacts columns matched application payload';
    end if;

    execute format(
      'update public.member_contacts set %s where id = %L',
      v_set_clause,
      v_existing_contact_id
    );

    v_mode := 'updated';
  end if;

  return jsonb_build_object(
    'member_id', v_member_id,
    'application_status', '未審査',
    'mode', v_mode
  );
end;
$$;

revoke all on function public.cidm_submit_application(jsonb) from public;
revoke all on function public.cidm_submit_application(jsonb) from anon;
revoke all on function public.cidm_submit_application(jsonb) from authenticated;
grant execute on function public.cidm_submit_application(jsonb) to anon, authenticated, service_role;

commit;