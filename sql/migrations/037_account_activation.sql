-- Email account activation.
--
-- New developer and tester accounts are created inactive. A 24-hour single-use
-- token is emailed by the account-activation Apps Script; only the activation
-- Edge Function, using the service role, may mark the profile active.
--
-- Run this after 036_free_access.sql.

alter table public.profiles
  add column if not exists status text;

update public.profiles
set status = 'active'
where status is null;

alter table public.profiles
  alter column status set default 'inactive';

alter table public.profiles
  alter column status set not null;

alter table public.profiles
  drop constraint if exists profiles_status_check;

alter table public.profiles
  add constraint profiles_status_check
  check (status in ('active', 'inactive'));

create table if not exists public.account_activations (
  id          uuid primary key default gen_random_uuid(),
  profile_id  uuid not null references public.profiles (id) on delete cascade,
  token_hash  text not null unique check (token_hash ~ '^[0-9a-f]{64}$'),
  expires_at  timestamptz not null default (now() + interval '24 hours'),
  used_at     timestamptz,
  created_at  timestamptz not null default now(),
  sent_at     timestamptz
);

create index if not exists account_activations_profile_idx
  on public.account_activations (profile_id, created_at desc);

create index if not exists account_activations_expiry_idx
  on public.account_activations (expires_at);

alter table public.account_activations enable row level security;

revoke all on public.account_activations from public, anon, authenticated;
grant select, insert, update on public.account_activations to service_role;

create or replace function public.create_activation_token(p_profile_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_profile public.profiles%rowtype;
  v_last    timestamptz;
  v_token   text;
  v_expires timestamptz;
  v_id      uuid;
begin
  select * into v_profile
  from public.profiles
  where id = p_profile_id
  for update;

  if not found then
    return jsonb_build_object('created', false, 'reason', 'missing');
  end if;

  if v_profile.status = 'active' then
    return jsonb_build_object('created', false, 'reason', 'active');
  end if;

  select max(created_at)
  into v_last
  from public.account_activations
  where profile_id = p_profile_id;

  if v_last is not null and v_last > now() - interval '60 seconds' then
    return jsonb_build_object('created', false, 'reason', 'cooldown');
  end if;

  update public.account_activations
  set used_at = now()
  where profile_id = p_profile_id
    and used_at is null;

  v_token := replace(gen_random_uuid()::text, '-', '')
             || replace(gen_random_uuid()::text, '-', '');
  v_expires := now() + interval '24 hours';

  insert into public.account_activations (profile_id, token_hash, expires_at)
  values (
    p_profile_id,
    encode(sha256(convert_to(v_token, 'UTF8')), 'hex'),
    v_expires
  )
  returning id into v_id;

  return jsonb_build_object(
    'created', true,
    'activation_id', v_id,
    'token', v_token,
    'profile_id', v_profile.id,
    'email', v_profile.email,
    'role', v_profile.role,
    'expires_at', v_expires
  );
end;
$$;

create or replace function public.request_activation(p_email text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_email   text := lower(trim(coalesce(p_email, '')));
  v_profile uuid;
begin
  if v_email !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    return jsonb_build_object('created', false, 'reason', 'missing');
  end if;

  select id into v_profile
  from public.profiles
  where lower(email) = v_email
    and status = 'inactive'
  order by created_at
  limit 1;

  if v_profile is null then
    return jsonb_build_object('created', false, 'reason', 'missing');
  end if;

  return public.create_activation_token(v_profile);
end;
$$;

create or replace function public.activate_account(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_token   text := lower(trim(coalesce(p_token, '')));
  v_row     public.account_activations%rowtype;
  v_profile public.profiles%rowtype;
begin
  if v_token !~ '^[0-9a-f]{64}$' then
    raise exception 'This activation link is not valid.';
  end if;

  select * into v_row
  from public.account_activations
  where token_hash = encode(sha256(convert_to(v_token, 'UTF8')), 'hex')
  for update;

  if v_row.id is null then
    raise exception 'This activation link is not valid or has expired.';
  end if;

  select * into v_profile
  from public.profiles
  where id = v_row.profile_id
  for update;

  if not found then
    raise exception 'This activation link is not valid.';
  end if;

  if v_profile.status = 'active' then
    update public.account_activations
    set used_at = coalesce(used_at, now())
    where id = v_row.id;

    return jsonb_build_object(
      'activated', true,
      'already_active', true,
      'email', v_profile.email,
      'role', v_profile.role
    );
  end if;

  if v_row.used_at is not null then
    raise exception 'This activation link has already been used.';
  end if;

  if v_row.expires_at <= now() then
    raise exception 'This activation link has expired. Ask for a new one.';
  end if;

  update public.profiles
  set status = 'active'
  where id = v_profile.id;

  update public.account_activations
  set used_at = now()
  where id = v_row.id;

  insert into public.audit_log (actor_id, actor_role, actor_label, action, target, detail)
  values (
    v_profile.id,
    v_profile.role::text,
    v_profile.display_name,
    'account.activated',
    v_profile.email,
    jsonb_build_object('profile_id', v_profile.id)
  );

  return jsonb_build_object(
    'activated', true,
    'already_active', false,
    'email', v_profile.email,
    'role', v_profile.role
  );
end;
$$;

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

  insert into public.profiles (id, role, display_name, email, status)
  values (new.id, v_role::public.app_role, v_display, v_email, 'inactive');

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

  if v_profile.status <> 'active' then
    raise exception 'Your TesterLoop account is not activated yet. Open the activation email we sent, then sign in again.';
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

  if v_profile.status <> 'active' then
    raise exception 'Your TesterLoop account is not activated yet. Open the activation email we sent, then sign in again.';
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

  insert into public.profiles (id, role, display_name, email, status)
  values (v_uid, v_role::public.app_role, v_display, v_email, 'inactive');

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

create or replace function public.bootstrap_admin(p_email text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_auth    uuid;
  v_email   text;
  v_profile public.profiles%rowtype;
  v_name    text;
begin
  if session_user not in ('postgres', 'supabase_admin') then
    raise exception 'bootstrap_admin can only be run from the Supabase Dashboard.';
  end if;

  select id, lower(email)
  into v_auth, v_email
  from auth.users
  where lower(email) = lower(trim(p_email));

  if v_auth is null then
    raise exception 'Create the auth user in Supabase first, then run bootstrap_admin.';
  end if;

  select * into v_profile from public.profiles where id = v_auth;
  if v_profile.id is not null and v_profile.role <> 'admin' then
    raise exception 'That account already has the % role.', v_profile.role;
  end if;

  if v_profile.id is null then
    v_name := split_part(v_email, '@', 1);
    insert into public.profiles (id, role, display_name, email, status)
    values (v_auth, 'admin', v_name, v_email, 'active');
  else
    update public.profiles
    set status = 'active'
    where id = v_auth
      and status <> 'active';
  end if;

  insert into public.admins (auth_user_id, note)
  values (v_auth, 'Bootstrapped from the Supabase Dashboard')
  on conflict (auth_user_id) do nothing;

  insert into public.audit_log (actor_id, actor_role, actor_label, action, target)
  values (v_auth, 'admin', v_email, 'admin.bootstrapped', v_email);

  return jsonb_build_object(
    'user_id', v_auth,
    'email', v_email,
    'role', 'admin'
  );
end;
$$;

-- Identity checks also refuse inactive accounts, so a tampered client cannot
-- skip whoami and call a data RPC directly.
create or replace function public.current_role_name()
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select p.role::text
  from public.profiles p
  where p.id = auth.uid()
    and p.status = 'active';
$$;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.admins a
    join public.profiles p on p.id = a.auth_user_id
    where a.auth_user_id = auth.uid()
      and p.status = 'active'
  );
$$;

create or replace function public.current_developer_id()
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select d.id
  from public.developers d
  join public.profiles p on p.id = d.auth_user_id
  where d.auth_user_id = auth.uid()
    and p.status = 'active';
$$;

create or replace function public.current_tester_id()
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select t.id
  from public.testers t
  join public.profiles p on p.id = t.auth_user_id
  where t.auth_user_id = auth.uid()
    and p.status = 'active';
$$;

revoke execute on function public.create_activation_token(uuid) from public, anon, authenticated;
grant execute on function public.create_activation_token(uuid) to service_role;

revoke execute on function public.request_activation(text) from public, anon, authenticated;
grant execute on function public.request_activation(text) to service_role;

revoke execute on function public.activate_account(text) from public, anon, authenticated;
grant execute on function public.activate_account(text) to service_role;

notify pgrst, 'reload schema';
