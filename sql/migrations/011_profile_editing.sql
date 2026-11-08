-- Live migration 011: developer and tester profile editing.
-- Adds display_name to developer_dashboard and two self-service RPCs.
-- Run once in the Supabase SQL editor after 008, 009 and 010.

create or replace function public.developer_dashboard()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_dev uuid := public.require_developer();
begin
  return jsonb_build_object(
    'developer', (
      select jsonb_build_object(
        'id', d.id,
        'display_name', coalesce(p.display_name, ''),
        'company_name', d.company_name,
        'contact_email', d.contact_email,
        'google_email', d.google_email,
        'created_at', d.created_at
      )
      from public.developers d
      left join public.profiles p on p.id = d.auth_user_id
      where d.id = v_dev
    ),
    'campaigns', coalesce((
      select jsonb_agg(public.developer_campaign_json(c.id) order by c.created_at desc)
      from public.campaigns c
      where c.developer_id = v_dev
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.update_developer_profile(
  p_display_name text,
  p_company_name text,
  p_contact_email text,
  p_google_email text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_dev     uuid := public.require_developer();
  v_name    text := btrim(coalesce(p_display_name, ''));
  v_company text := btrim(coalesce(p_company_name, ''));
  v_contact text := lower(btrim(coalesce(p_contact_email, '')));
  v_google  text := lower(btrim(coalesce(p_google_email, '')));
  v_email   text;
begin
  if length(v_name) < 2 or length(v_name) > 120 then
    raise exception 'Display name must be between 2 and 120 characters.';
  end if;

  if length(v_company) < 2 or length(v_company) > 120 then
    raise exception 'Company name must be between 2 and 120 characters.';
  end if;

  if v_contact !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Enter a valid contact email address.';
  end if;

  if v_google !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Enter a valid Google account email address.';
  end if;

  update public.profiles
  set display_name = v_name
  where id = (select auth_user_id from public.developers where id = v_dev)
  returning email into v_email;

  if v_email is null then
    raise exception 'Developer profile not found.';
  end if;

  update public.developers
  set company_name = v_company,
      contact_email = v_contact,
      google_email = v_google
  where id = v_dev;

  perform public.write_audit(
    'developer.profile_updated',
    v_dev::text,
    jsonb_build_object('company_name', v_company)
  );

  return jsonb_build_object(
    'display_name', v_name,
    'company_name', v_company,
    'contact_email', v_contact,
    'google_email', v_google
  );
end;
$$;

create or replace function public.update_tester_profile(
  p_display_name text,
  p_google_email text,
  p_region text default null,
  p_devices text[] default '{}'
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_tester  uuid := public.require_tester();
  v_name    text := btrim(coalesce(p_display_name, ''));
  v_google  text := lower(btrim(coalesce(p_google_email, '')));
  v_region  text := nullif(btrim(coalesce(p_region, '')), '');
  v_devices text[] := coalesce(p_devices, '{}');
begin
  if length(v_name) < 2 or length(v_name) > 120 then
    raise exception 'Display name must be between 2 and 120 characters.';
  end if;

  if v_google !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Enter a valid Google account email address.';
  end if;

  if length(coalesce(v_region, '')) > 120 then
    raise exception 'Keep the region under 120 characters.';
  end if;

  if array_length(v_devices, 1) > 10 then
    raise exception 'List up to 10 devices.';
  end if;

  if exists (
    select 1 from unnest(v_devices) as d(item)
    where length(btrim(d.item)) = 0 or length(btrim(d.item)) > 80
  ) then
    raise exception 'Each device must be between 1 and 80 characters.';
  end if;

  select array_agg(btrim(d.item))
  into v_devices
  from unnest(v_devices) as d(item);

  v_devices := coalesce(v_devices, '{}');

  if exists (
    select 1 from public.testers
    where lower(google_email) = v_google
      and id <> v_tester
  ) then
    raise exception 'That Google account is already linked to another tester.';
  end if;

  update public.profiles
  set display_name = v_name
  where id = (select auth_user_id from public.testers where id = v_tester);

  begin
    update public.testers
    set display_name = v_name,
        google_email = v_google,
        region = v_region,
        devices = v_devices
    where id = v_tester;
  exception
    when unique_violation then
      raise exception 'That Google account is already linked to another tester.';
  end;

  perform public.write_audit(
    'tester.profile_updated',
    v_tester::text,
    jsonb_build_object('region', v_region, 'devices', v_devices)
  );

  return jsonb_build_object(
    'display_name', v_name,
    'google_email', v_google,
    'region', v_region,
    'devices', to_jsonb(v_devices)
  );
end;
$$;

grant execute on function public.update_developer_profile(text, text, text, text)
  to authenticated;
grant execute on function public.update_tester_profile(text, text, text, text[])
  to authenticated;

notify pgrst, 'reload schema';
