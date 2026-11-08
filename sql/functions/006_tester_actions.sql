-- Tester mutations. A seat is either joined, opted_in, or dropped. A campaign
-- may use at most 15 distinct testers over its lifetime, because every tester is
-- paid. Dropping a seat does not free it for a different tester; only the same
-- tester may rejoin, reusing their own row. A tester may hold seats in any
-- number of campaigns.

create or replace function public.join_campaign(p_campaign_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_tester      uuid := public.require_tester();
  v_campaign    public.campaigns%rowtype;
  v_seat        public.campaign_seats%rowtype;
  v_seat_number smallint;
  v_used        integer;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_campaign_id::text, 0));

  select * into v_campaign from public.campaigns where id = p_campaign_id for update;
  if not found then
    raise exception 'That project no longer exists.';
  end if;
  if v_campaign.state not in ('live', 'at_risk') or v_campaign.play_opt_in_url is null then
    raise exception 'That project is not open to testers yet.';
  end if;

  select count(*) into v_used
  from public.campaign_seats
  where campaign_id = p_campaign_id;

  if exists (
    select 1 from public.campaign_seats
    where campaign_id = p_campaign_id
      and tester_id = v_tester
      and state in ('joined', 'opted_in')
  ) then
    raise exception 'You are already in this project.';
  end if;

  select * into v_seat
  from public.campaign_seats
  where campaign_id = p_campaign_id and tester_id = v_tester
  for update;

  if found then
    if v_seat.state <> 'dropped' then
      raise exception 'You are already in this project.';
    end if;

    select n into v_seat_number
    from generate_series(1, 15) as n
    where not exists (
      select 1 from public.campaign_seats s
      where s.campaign_id = p_campaign_id
        and s.seat_number = n
        and s.state in ('joined', 'opted_in')
    )
    order by n
    limit 1;

    if v_seat_number is null then
      raise exception 'All 15 tester seats for this project are in use.';
    end if;

    update public.campaign_seats
    set seat_number = v_seat_number,
        state = 'joined',
        joined_at = now(),
        opted_in_at = null,
        opt_in_verified_at = null,
        opt_in_verification = null,
        dropped_at = null,
        payout_amount_cents = v_campaign.tester_payout_cents
    where id = v_seat.id
    returning * into v_seat;
  else
    if v_used >= 15 then
      raise exception 'This project has already used all 15 tester seats.';
    end if;

    select n into v_seat_number
    from generate_series(1, 15) as n
    where not exists (
      select 1 from public.campaign_seats s
      where s.campaign_id = p_campaign_id
        and s.seat_number = n
        and s.state in ('joined', 'opted_in')
    )
    order by n
    limit 1;

    if v_seat_number is null then
      raise exception 'All 15 tester seats for this project are in use.';
    end if;

    insert into public.campaign_seats (
      campaign_id,
      tester_id,
      seat_number,
      state,
      joined_at,
      payout_amount_cents
    )
    values (
      p_campaign_id,
      v_tester,
      v_seat_number,
      'joined',
      now(),
      v_campaign.tester_payout_cents
    )
    returning * into v_seat;
  end if;

  perform public.write_audit(
    'seat.joined',
    v_campaign.app_name,
    jsonb_build_object('campaign_id', p_campaign_id, 'seat_number', v_seat.seat_number)
  );
  perform public.refresh_campaign_state(p_campaign_id);

  return jsonb_build_object(
    'campaign_id', p_campaign_id,
    'seat_number', v_seat.seat_number,
    'state', v_seat.state::text,
    'play_opt_in_url', v_campaign.play_opt_in_url,
    'app_name', v_campaign.app_name
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

  update public.campaigns
  set first_opt_in_at = coalesce(first_opt_in_at, v_seat.opted_in_at, now())
  where id = p_campaign_id;

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

-- Called only by the verify-opt-in Edge Function (service_role) after a failed
-- Google Group check. Dropping the row frees the tester to join again.
create or replace function public.release_unverified_seat(p_tester_id uuid, p_campaign_id uuid)
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

  if not found or v_seat.state = 'dropped' then
    return jsonb_build_object(
      'campaign_id', p_campaign_id,
      'released', false,
      'state', case when found then v_seat.state::text else null end
    );
  end if;

  update public.campaign_seats
  set state = 'dropped',
      opted_in_at = null,
      opt_in_verified_at = null,
      opt_in_verification = null,
      dropped_at = now()
  where id = v_seat.id
  returning * into v_seat;

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
    'seat.released_unverified',
    v_app,
    jsonb_build_object(
      'campaign_id', p_campaign_id,
      'seat_number', v_seat.seat_number,
      'tester_id', p_tester_id
    )
  );

  perform public.refresh_campaign_state(p_campaign_id);

  return jsonb_build_object(
    'campaign_id', p_campaign_id,
    'released', true,
    'state', v_seat.state::text
  );
end;
$$;

create or replace function public.record_tester_device(p_device_name text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_tester   uuid := public.require_tester();
  v_device   text := regexp_replace(btrim(coalesce(p_device_name, '')), '\s+', ' ', 'g');
  v_previous text;
  v_now      timestamptz := now();
begin
  if length(v_device) < 1 or length(v_device) > 120 then
    raise exception 'The device name must be between 1 and 120 characters.';
  end if;

  if v_device ~ '[[:cntrl:]]' then
    raise exception 'The device name contains invalid characters.';
  end if;

  select mobile_device_name
  into v_previous
  from public.testers
  where id = v_tester
  for update;

  update public.testers
  set mobile_device_name = v_device,
      mobile_device_seen_at = v_now
  where id = v_tester;

  if v_previous is distinct from v_device then
    perform public.write_audit(
      'tester.device_reported',
      v_device,
      jsonb_build_object('tester_id', v_tester)
    );
  end if;

  return jsonb_build_object(
    'device_name', v_device,
    'seen_at', v_now
  );
end;
$$;

create or replace function public.file_report(
  p_campaign_id uuid,
  p_severity text,
  p_title text,
  p_body text,
  p_build_label text default null,
  p_device text default null,
  p_evidence_url text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_tester uuid := public.require_tester();
  v_title  text := trim(coalesce(p_title, ''));
  v_body   text := trim(coalesce(p_body, ''));
  v_build  text := nullif(trim(coalesce(p_build_label, '')), '');
  v_device text := nullif(trim(coalesce(p_device, '')), '');
  v_url    text := nullif(trim(coalesce(p_evidence_url, '')), '');
  v_app    text;
  v_joined timestamptz;
  v_seat_created timestamptz;
  v_id     uuid;
  v_captured timestamptz := now();
  v_usage  jsonb;
  v_window_start date;
  v_window_end date := current_date;
  v_history jsonb;
begin
  if p_severity not in ('blocker', 'major', 'minor', 'cosmetic') then
    raise exception 'Choose a valid severity.';
  end if;
  if length(v_title) < 4 then
    raise exception 'Give the report a title of at least four characters.';
  end if;
  if v_body = '' then
    raise exception 'Describe what happened.';
  end if;
  if v_url is not null and v_url !~ '^https://' then
    raise exception 'Evidence links must use https://.';
  end if;

  select c.app_name, s.joined_at, s.created_at
  into v_app, v_joined, v_seat_created
  from public.campaigns c
  join public.campaign_seats s on s.campaign_id = c.id
  where c.id = p_campaign_id
    and s.tester_id = v_tester
    and s.state in ('joined', 'opted_in');

  if not found then
    raise exception 'Join this project before filing a report.';
  end if;

  v_window_start := coalesce(v_joined, v_seat_created, now())::date;
  if v_window_start < v_window_end - 365 then
    v_window_start := v_window_end - 365;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'date', g.day::date,
    'installed', h.installed,
    'checked', h.installed is not null,
    'checked_at', h.checked_at
  ) order by g.day), '[]'::jsonb)
  into v_history
  from generate_series(
    v_window_start::timestamp,
    v_window_end::timestamp,
    interval '1 day'
  ) as g(day)
  left join public.tester_app_install_daily h
    on h.tester_id = v_tester
   and h.campaign_id = p_campaign_id
   and h.status_date = g.day::date;

  select jsonb_build_object(
    'available', true,
    'package_name', us.package_name,
    'installed', us.installed,
    'distinct_days_used', us.distinct_days_used,
    'continuous_days_used', us.continuous_days_used,
    'meets_usage_requirement', us.meets_usage_requirement,
    'last_usage_at', us.last_usage_at,
    'first_install_at', us.first_install_at,
    'captured_at', v_captured
  )
  into v_usage
  from public.tester_app_usage_summary us
  where us.tester_id = v_tester
    and us.campaign_id = p_campaign_id;

  if v_usage is null then
    select jsonb_build_object(
      'available', false,
      'package_name', c.package_name,
      'installed', coalesce(
        i.last_seen_installed_at is not null and i.uninstalled_at is null,
        false
      ),
      'distinct_days_used', 0,
      'continuous_days_used', 0,
      'meets_usage_requirement', false,
      'last_usage_at', null,
      'first_install_at', i.first_seen_installed_at,
      'captured_at', v_captured
    )
    into v_usage
    from public.campaigns c
    left join public.tester_app_installs i
      on i.tester_id = v_tester
     and i.campaign_id = c.id
    where c.id = p_campaign_id;
  end if;

  insert into public.bug_reports (
    campaign_id, tester_id, severity, title, body, build_label, device, evidence_url,
    usage_snapshot, usage_captured_at,
    install_history, install_history_captured_at, install_window_start, install_window_end
  )
  values (
    p_campaign_id, v_tester, p_severity::public.report_severity,
    v_title, v_body, v_build, v_device, v_url,
    v_usage, v_captured,
    v_history, v_captured, v_window_start, v_window_end
  )
  returning id into v_id;

  perform public.write_audit(
    'report.filed',
    v_title,
    jsonb_build_object('report_id', v_id, 'campaign_id', p_campaign_id)
  );

  return jsonb_build_object(
    'id', v_id,
    'campaign_id', p_campaign_id,
    'app_name', v_app,
    'severity', p_severity,
    'status', 'open',
    'title', v_title,
    'created_at', now(),
    'usage', v_usage,
    'install_history', v_history,
    'install_history_captured_at', v_captured,
    'install_window_start', v_window_start,
    'install_window_end', v_window_end
  );
end;
$$;

create or replace function public.report_app_install_daily(
  p_campaign_id uuid,
  p_date date,
  p_installed boolean,
  p_source text default 'mobile_daily'
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_tester uuid := public.require_tester();
  v_campaign public.campaigns%rowtype;
  v_seat public.campaign_seats%rowtype;
  v_source text := coalesce(nullif(trim(p_source), ''), 'mobile_daily');
  v_join date;
  v_row public.tester_app_install_daily%rowtype;
  v_install public.tester_app_installs%rowtype;
begin
  if p_date is null then
    raise exception 'A date is required for an install check.';
  end if;
  if p_installed is null then
    raise exception 'An install state is required.';
  end if;
  if v_source not in ('mobile_daily', 'mobile_manual') then
    raise exception 'That install check source is not allowed.';
  end if;
  if p_date > current_date + 1 then
    raise exception 'Install checks cannot be recorded for a future date.';
  end if;

  select * into v_campaign from public.campaigns where id = p_campaign_id;
  if not found then
    raise exception 'That project no longer exists.';
  end if;
  if v_campaign.package_name is null or btrim(v_campaign.package_name) = '' then
    raise exception 'This project has no package name yet. Contact operations.';
  end if;
  if v_campaign.state in ('draft', 'pending', 'awaiting_link', 'cancelled') then
    raise exception 'This project is not running, so install checks are closed.';
  end if;
  if v_campaign.state = 'passed'
     and v_campaign.passed_at is not null
     and p_date > v_campaign.passed_at::date then
    raise exception 'This project has passed. Daily install checks stopped on the pass date.';
  end if;

  select * into v_seat
  from public.campaign_seats
  where campaign_id = p_campaign_id and tester_id = v_tester
    and state in ('joined', 'opted_in');
  if not found then
    raise exception 'Join this project before reporting install checks.';
  end if;

  v_join := coalesce(v_seat.joined_at, v_seat.created_at)::date;
  if p_date < v_join - 1 then
    raise exception 'Install checks cannot start before you joined this project.';
  end if;

  insert into public.tester_app_install_daily (
    tester_id, campaign_id, package_name, status_date, installed, source, checked_at
  )
  values (
    v_tester, p_campaign_id, v_campaign.package_name, p_date, p_installed, v_source, now()
  )
  on conflict (tester_id, campaign_id, status_date) do update set
    package_name = excluded.package_name,
    installed = excluded.installed,
    source = excluded.source,
    checked_at = now(),
    updated_at = now()
  returning * into v_row;

  if p_date = current_date then
    insert into public.tester_app_installs (
      tester_id, campaign_id, package_name,
      first_seen_installed_at, last_seen_installed_at
    )
    values (
      v_tester, p_campaign_id, v_campaign.package_name,
      case when p_installed then now() else null end,
      case when p_installed then now() else null end
    )
    on conflict (tester_id, campaign_id) do update set
      package_name = excluded.package_name,
      last_seen_installed_at = case when p_installed then now() else public.tester_app_installs.last_seen_installed_at end,
      first_seen_installed_at = coalesce(public.tester_app_installs.first_seen_installed_at, case when p_installed then now() else null end),
      uninstalled_at = case when p_installed then null else coalesce(public.tester_app_installs.uninstalled_at, now()) end,
      updated_at = now()
    returning * into v_install;

    insert into public.tester_app_usage_summary (tester_id, campaign_id, package_name, installed, first_install_at)
    values (v_tester, p_campaign_id, v_campaign.package_name, p_installed, v_install.first_seen_installed_at)
    on conflict (tester_id, campaign_id) do update set
      installed = p_installed,
      first_install_at = coalesce(public.tester_app_usage_summary.first_install_at, v_install.first_seen_installed_at),
      updated_at = now();
  end if;

  return jsonb_build_object(
    'campaign_id', p_campaign_id,
    'package_name', v_campaign.package_name,
    'date', p_date,
    'installed', p_installed,
    'source', v_source,
    'checked_at', v_row.checked_at
  );
end;
$$;

create or replace function public.report_app_install_status(p_campaign_id uuid, p_installed boolean)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_campaign public.campaigns%rowtype;
  v_date date := current_date;
begin
  select * into v_campaign from public.campaigns where id = p_campaign_id;
  if not found then
    raise exception 'That project no longer exists.';
  end if;

  if v_campaign.state in ('draft', 'pending', 'awaiting_link') then
    raise exception 'This project is not running yet.';
  end if;

  if v_campaign.state = 'cancelled' then
    return jsonb_build_object(
      'campaign_id', p_campaign_id,
      'package_name', v_campaign.package_name,
      'installed', p_installed,
      'recorded', false
    );
  end if;

  if v_campaign.state = 'passed' and v_campaign.passed_at is not null then
    v_date := least(current_date, v_campaign.passed_at::date);
  end if;

  return public.report_app_install_daily(p_campaign_id, v_date, p_installed, 'mobile_daily');
end;
$$;
