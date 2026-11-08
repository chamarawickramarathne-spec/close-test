-- Account provisioning. Sign-up metadata decides whether the new auth user is
-- a developer or a tester. Admin accounts are created only by bootstrap_admin.

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_meta       jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  v_role       text := lower(trim(coalesce(v_meta->>'role', '')));
  v_display    text := trim(coalesce(v_meta->>'display_name', ''));
  v_company    text := trim(coalesce(v_meta->>'company_name', ''));
  v_google     text := lower(trim(coalesce(v_meta->>'google_email', '')));
  v_region     text := nullif(trim(coalesce(v_meta->>'region', '')), '');
  v_devices    text[] := '{}';
  v_email      text := lower(coalesce(new.email, ''));
begin
  if v_role = '' then
    return new;
  end if;

  if v_role not in ('developer', 'tester') then
    raise exception 'Choose developer or tester when creating an account.';
  end if;

  if v_email = '' then
    raise exception 'An email address is required.';
  end if;

  if v_display = '' then
    v_display := split_part(v_email, '@', 1);
  end if;

  if v_google = '' then
    v_google := v_email;
  end if;

  if v_google !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Enter a valid Google account email address.';
  end if;

  if v_role = 'tester' and exists (
    select 1 from public.testers where lower(google_email) = lower(v_google)
  ) then
    raise exception 'That Google account is already linked to another tester.';
  end if;

  insert into public.profiles (id, role, display_name, email)
  values (new.id, v_role::public.app_role, v_display, v_email);

  if v_role = 'developer' then
    if length(v_company) < 2 then
      raise exception 'Enter the company or studio name.';
    end if;

    insert into public.developers (auth_user_id, company_name, contact_email, google_email)
    values (new.id, v_company, v_email, v_google);
  else
    if jsonb_typeof(v_meta->'devices') = 'array' then
      select coalesce(array_agg(trim(d.item)), '{}')
      into v_devices
      from jsonb_array_elements_text(v_meta->'devices') as d(item)
      where trim(d.item) <> '';
    elsif nullif(trim(coalesce(v_meta->>'devices', '')), '') is not null then
      select coalesce(array_agg(trim(d.item)), '{}')
      into v_devices
      from unnest(string_to_array(v_meta->>'devices', ',')) as d(item)
      where trim(d.item) <> '';
    end if;

    insert into public.testers (auth_user_id, display_name, google_email, devices, region)
    values (new.id, v_display, v_google, v_devices, v_region);
  end if;

  insert into public.audit_log (actor_id, actor_role, actor_label, action, target)
  values (new.id, v_role, v_display, 'account.created', v_email);

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create or replace function public.require_developer()
returns uuid
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_id uuid := public.current_developer_id();
begin
  if v_id is null then
    raise exception 'This action needs a developer account.';
  end if;
  return v_id;
end;
$$;

create or replace function public.require_tester()
returns uuid
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_id uuid := public.current_tester_id();
begin
  if v_id is null then
    raise exception 'This action needs a tester account.';
  end if;
  return v_id;
end;
$$;

create or replace function public.require_admin()
returns uuid
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_admin() then
    raise exception 'This action needs an operations account.';
  end if;
  return auth.uid();
end;
$$;

create or replace function public.whoami()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_profile public.profiles%rowtype;
  v_developer public.developers%rowtype;
  v_tester public.testers%rowtype;
begin
  select * into v_profile from public.profiles where id = auth.uid();
  if not found then
    raise exception 'This sign-in has no TesterLoop profile. Ask operations for help.';
  end if;

  select * into v_developer from public.developers where auth_user_id = auth.uid();
  select * into v_tester from public.testers where auth_user_id = auth.uid();

  return jsonb_build_object(
    'user_id', v_profile.id,
    'role', v_profile.role,
    'display_name', v_profile.display_name,
    'email', v_profile.email,
    'developer_id', v_developer.id,
    'tester_id', v_tester.id,
    'company_name', v_developer.company_name,
    'tester_name', v_tester.display_name
  );
end;
$$;

-- Any non-admin account may use both the developer and tester workspaces. The
-- first use of a role creates the matching profile from the account's existing
-- name and Google address. profiles.role stays as the account's origin for
-- display and audit; access checks use the developers/testers rows.
create or replace function public.ensure_account_role(p_role text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid       uuid := auth.uid();
  v_role      text := lower(trim(coalesce(p_role, '')));
  v_profile   public.profiles%rowtype;
  v_developer public.developers%rowtype;
  v_tester    public.testers%rowtype;
  v_meta      jsonb;
  v_email     text;
  v_display   text;
  v_company   text;
  v_google    text;
  v_region    text;
  v_devices   text[] := '{}';
begin
  if v_uid is null then
    raise exception 'Sign in again to continue.';
  end if;

  if v_role not in ('developer', 'tester') then
    raise exception 'Choose developer or tester.';
  end if;

  select * into v_profile from public.profiles where id = v_uid;
  if not found then
    raise exception 'This sign-in has no TesterLoop profile. Ask operations for help.';
  end if;

  if v_profile.role = 'admin' then
    raise exception 'Operations accounts cannot add a developer or tester role.';
  end if;

  select coalesce(raw_user_meta_data, '{}'::jsonb), lower(coalesce(email, ''))
  into v_meta, v_email
  from auth.users
  where id = v_uid;

  if not found then
    raise exception 'This sign-in has no account record.';
  end if;

  select * into v_developer from public.developers where auth_user_id = v_uid;
  select * into v_tester from public.testers where auth_user_id = v_uid;

  if v_role = 'developer' then
    if v_developer.id is null then
      v_display := coalesce(nullif(trim(v_profile.display_name), ''), split_part(v_email, '@', 1));
      v_company := nullif(trim(coalesce(v_meta->>'company_name', '')), '');
      if v_company is null or length(v_company) < 2 then
        v_company := left(v_display || ' Studio', 120);
      end if;
      if length(v_company) < 2 then
        v_company := 'TesterLoop Studio';
      end if;

      v_google := lower(trim(coalesce(
        nullif(v_meta->>'google_email', ''),
        nullif(v_tester.google_email, ''),
        v_email)));
      if v_google !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
        v_google := v_email;
      end if;

      insert into public.developers (auth_user_id, company_name, contact_email, google_email)
      values (v_uid, v_company, v_email, v_google);

      perform public.write_audit(
        'account.role_added', 'developer',
        jsonb_build_object('role', 'developer'));
    end if;
  else
    if v_tester.id is null then
      v_display := coalesce(nullif(trim(v_profile.display_name), ''), split_part(v_email, '@', 1));
      if length(v_display) < 2 then
        v_display := left(v_display || ' tester', 120);
      end if;
      if length(v_display) < 2 then
        v_display := 'TesterLoop tester';
      end if;

      v_google := lower(trim(coalesce(
        nullif(v_meta->>'google_email', ''),
        nullif(v_developer.google_email, ''),
        v_email)));
      if v_google !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
        v_google := v_email;
      end if;

      if exists (
        select 1 from public.testers t
        where lower(t.google_email) = lower(v_google)
          and t.auth_user_id is distinct from v_uid
      ) then
        raise exception 'That Google account is already linked to another tester.';
      end if;

      v_region := nullif(trim(coalesce(v_meta->>'region', '')), '');

      if jsonb_typeof(v_meta->'devices') = 'array' then
        select coalesce(array_agg(trim(d.item)), '{}')
        into v_devices
        from jsonb_array_elements_text(v_meta->'devices') as d(item)
        where trim(d.item) <> '';
      elsif nullif(trim(coalesce(v_meta->>'devices', '')), '') is not null then
        select coalesce(array_agg(trim(d.item)), '{}')
        into v_devices
        from unnest(string_to_array(v_meta->>'devices', ',')) as d(item)
        where trim(d.item) <> '';
      end if;

      insert into public.testers (auth_user_id, display_name, google_email, devices, region)
      values (v_uid, v_display, v_google, v_devices, v_region);

      perform public.write_audit(
        'account.role_added', 'tester',
        jsonb_build_object('role', 'tester'));
    end if;
  end if;

  return public.whoami();
end;
$$;

create or replace function public.claim_profile()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid      uuid := auth.uid();
  v_meta     jsonb;
  v_email    text;
  v_role     text;
  v_display  text;
  v_company  text;
  v_google   text;
  v_region   text;
  v_devices  text[] := '{}';
begin
  if v_uid is null then
    raise exception 'Sign in again to continue.';
  end if;

  if exists (select 1 from public.profiles where id = v_uid) then
    return jsonb_build_object('claimed', false);
  end if;

  select coalesce(raw_user_meta_data, '{}'::jsonb), lower(coalesce(email, ''))
  into v_meta, v_email
  from auth.users
  where id = v_uid;

  if not found then
    raise exception 'This sign-in has no account record.';
  end if;

  v_role := lower(trim(coalesce(v_meta->>'role', '')));
  v_display := trim(coalesce(v_meta->>'display_name', ''));
  v_company := trim(coalesce(v_meta->>'company_name', ''));
  v_google := lower(trim(coalesce(v_meta->>'google_email', '')));
  v_region := nullif(trim(coalesce(v_meta->>'region', '')), '');

  if v_role not in ('developer', 'tester') then
    raise exception 'This sign-in cannot create a TesterLoop account.';
  end if;

  if v_email = '' then
    raise exception 'An email address is required.';
  end if;

  if v_display = '' then
    v_display := split_part(v_email, '@', 1);
  end if;

  if v_google = '' then
    v_google := v_email;
  end if;

  if v_google !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Enter a valid Google account email address.';
  end if;

  if v_role = 'tester' and exists (
    select 1 from public.testers where lower(google_email) = lower(v_google)
  ) then
    raise exception 'That Google account is already linked to another tester.';
  end if;

  insert into public.profiles (id, role, display_name, email)
  values (v_uid, v_role::public.app_role, v_display, v_email);

  if v_role = 'developer' then
    if length(v_company) < 2 then
      raise exception 'Enter the company or studio name.';
    end if;

    insert into public.developers (auth_user_id, company_name, contact_email, google_email)
    values (v_uid, v_company, v_email, v_google);
  else
    if jsonb_typeof(v_meta->'devices') = 'array' then
      select coalesce(array_agg(trim(d.item)), '{}')
      into v_devices
      from jsonb_array_elements_text(v_meta->'devices') as d(item)
      where trim(d.item) <> '';
    elsif nullif(trim(coalesce(v_meta->>'devices', '')), '') is not null then
      select coalesce(array_agg(trim(d.item)), '{}')
      into v_devices
      from unnest(string_to_array(v_meta->>'devices', ',')) as d(item)
      where trim(d.item) <> '';
    end if;

    insert into public.testers (auth_user_id, display_name, google_email, devices, region)
    values (v_uid, v_display, v_google, v_devices, v_region);
  end if;

  insert into public.audit_log (actor_id, actor_role, actor_label, action, target)
  values (v_uid, v_role, v_display, 'account.repaired', v_email);

  return jsonb_build_object('claimed', true);
end;
$$;
