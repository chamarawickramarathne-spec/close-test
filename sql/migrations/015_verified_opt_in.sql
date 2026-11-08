-- 015: verified opt-in.
-- A tester may only move to opted_in after the Edge Function has found their
-- Google account in the campaign's Google Group.

alter table public.campaign_seats
  add column if not exists opt_in_verified_at timestamptz,
  add column if not exists opt_in_verification text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'campaign_seats_opt_in_verification_check'
  ) then
    alter table public.campaign_seats
      add constraint campaign_seats_opt_in_verification_check
      check (opt_in_verification is null or opt_in_verification = 'google_group');
  end if;
end;
$$;

create or replace function public.tester_dashboard()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_tester uuid := public.require_tester();
begin
  return jsonb_build_object(
    'tester', (
      select jsonb_build_object(
        'id', t.id,
        'display_name', t.display_name,
        'google_email', t.google_email,
        'email', p.email,
        'devices', to_jsonb(t.devices),
        'region', t.region,
        'reliability', t.reliability
      )
      from public.testers t
      join public.profiles p on p.id = t.auth_user_id
      where t.id = v_tester
    ),
    'mine', coalesce((
      select jsonb_agg(jsonb_build_object(
        'campaign_id', c.id,
        'app_name', c.app_name,
        'group_email', g.email,
        'play_opt_in_url', coalesce(c.play_opt_in_url, ''),
        'seat_number', s.seat_number,
        'state', s.state::text,
        'opted_in_at', s.opted_in_at,
        'opt_in_verified_at', s.opt_in_verified_at,
        'opt_in_verification', s.opt_in_verification,
        'days', case
          when s.opted_in_at is null then 0
          else floor(extract(epoch from (now() - s.opted_in_at)) / 86400)::int
        end,
        'required_testers', c.required_testers
      ) order by s.seat_number)
      from public.campaign_seats s
      join public.campaigns c on c.id = s.campaign_id
      left join public.google_groups g on g.id = c.group_id
      where s.tester_id = v_tester
        and s.state in ('joined', 'opted_in')
    ), '[]'::jsonb),
    'available', coalesce((
      select jsonb_agg(jsonb_build_object(
        'campaign_id', c.id,
        'app_name', c.app_name,
        'package_name', c.package_name,
        'group_email', g.email,
        'seats_free', 15 - coalesce(h.seats_used, 0),
        'required_testers', c.required_testers
      ) order by c.started_at desc nulls last, c.created_at desc)
      from public.campaigns c
      left join public.google_groups g on g.id = c.group_id
      left join public.campaign_health h on h.campaign_id = c.id
      where c.state in ('live', 'at_risk')
        and c.play_opt_in_url is not null
        and not exists (
          select 1
          from public.campaign_seats s
          where s.campaign_id = c.id
            and s.tester_id = v_tester
            and s.state in ('joined', 'opted_in')
        )
    ), '[]'::jsonb),
    'reports', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id,
        'campaign_id', r.campaign_id,
        'app_name', c.app_name,
        'severity', r.severity::text,
        'status', r.status::text,
        'title', r.title,
        'created_at', r.created_at
      ) order by r.created_at desc)
      from public.bug_reports r
      join public.campaigns c on c.id = r.campaign_id
      where r.tester_id = v_tester
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.set_opt_in(p_campaign_id uuid, p_opted_in boolean)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_tester uuid := public.require_tester();
  v_seat   public.campaign_seats%rowtype;
  v_app    text;
begin
  select app_name into v_app
  from public.campaigns
  where id = p_campaign_id;

  select * into v_seat
  from public.campaign_seats
  where campaign_id = p_campaign_id and tester_id = v_tester
  for update;

  if not found or v_seat.state not in ('joined', 'opted_in') then
    raise exception 'Join this project before recording an opt-in.';
  end if;

  if p_opted_in then
    raise exception 'Confirm opt-in checks the Google Group. Use the Confirm opt-in button.';
  end if;

  update public.campaign_seats
  set state = 'dropped',
      dropped_at = now(),
      opted_in_at = null,
      opt_in_verified_at = null,
      opt_in_verification = null
  where id = v_seat.id
  returning * into v_seat;

  perform public.write_audit(
    'seat.opted_out',
    v_app,
    jsonb_build_object('campaign_id', p_campaign_id, 'seat_number', v_seat.seat_number)
  );

  perform public.refresh_campaign_state(p_campaign_id);

  return jsonb_build_object(
    'campaign_id', p_campaign_id,
    'state', v_seat.state::text,
    'opted_in_at', v_seat.opted_in_at
  );
end;
$$;

create or replace function public.record_verified_opt_in(
  p_tester_id uuid,
  p_campaign_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_seat  public.campaign_seats%rowtype;
  v_app   text;
  v_actor uuid;
  v_role  text;
  v_label text;
begin
  select app_name into v_app
  from public.campaigns
  where id = p_campaign_id;

  if v_app is null then
    raise exception 'That project no longer exists.';
  end if;

  select * into v_seat
  from public.campaign_seats
  where campaign_id = p_campaign_id and tester_id = p_tester_id
  for update;

  if not found or v_seat.state not in ('joined', 'opted_in') then
    raise exception 'Join this project before confirming opt-in.';
  end if;

  if v_seat.state = 'opted_in' then
    update public.campaign_seats
    set opt_in_verified_at = coalesce(opt_in_verified_at, now()),
        opt_in_verification = 'google_group'
    where id = v_seat.id
    returning * into v_seat;
  else
    update public.campaign_seats
    set state = 'opted_in',
        opted_in_at = now(),
        dropped_at = null,
        opt_in_verified_at = now(),
        opt_in_verification = 'google_group'
    where id = v_seat.id
    returning * into v_seat;
  end if;

  select t.auth_user_id,
         coalesce(p.role::text, 'tester'),
         coalesce(p.display_name, t.display_name, 'Tester')
  into v_actor, v_role, v_label
  from public.testers t
  left join public.profiles p on p.id = t.auth_user_id
  where t.id = p_tester_id;

  insert into public.audit_log (actor_id, actor_role, actor_label, action, target, detail)
  values (
    v_actor,
    coalesce(v_role, 'tester'),
    coalesce(v_label, 'Tester'),
    'seat.opted_in_verified',
    v_app,
    jsonb_build_object(
      'campaign_id', p_campaign_id,
      'seat_number', v_seat.seat_number,
      'verification', 'google_group'
    )
  );

  perform public.refresh_campaign_state(p_campaign_id);

  return jsonb_build_object(
    'campaign_id', p_campaign_id,
    'state', v_seat.state::text,
    'opted_in_at', v_seat.opted_in_at,
    'opt_in_verified_at', v_seat.opt_in_verified_at,
    'opt_in_verification', v_seat.opt_in_verification
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
  v_current_google text;
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

  select google_email into v_current_google
  from public.testers
  where id = v_tester;

  if v_google <> v_current_google and exists (
    select 1 from public.campaign_seats
    where tester_id = v_tester and state = 'opted_in'
  ) then
    raise exception 'Opt out of your active projects before changing your Google account email.';
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

revoke execute on function public.record_verified_opt_in(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.record_verified_opt_in(uuid, uuid) to service_role;
grant execute on function public.set_opt_in(uuid, boolean) to authenticated;

notify pgrst, 'reload schema';
