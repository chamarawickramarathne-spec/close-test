-- Migration 032: Daily install checks and report install history
-- Stores one install-check row per tester, campaign and day. Reports snapshot the
-- whole window from the join date to the report date.

create table if not exists public.tester_app_install_daily (
  id uuid primary key default gen_random_uuid(),
  tester_id uuid not null references public.testers (id) on delete cascade,
  campaign_id uuid not null references public.campaigns (id) on delete cascade,
  package_name text not null,
  status_date date not null,
  installed boolean not null,
  source text not null default 'mobile_daily'
    check (source in ('mobile_daily', 'mobile_manual', 'desktop')),
  checked_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tester_id, campaign_id, status_date)
);

create index if not exists tester_app_install_daily_campaign_idx
  on public.tester_app_install_daily (campaign_id, status_date);

drop trigger if exists tester_app_install_daily_touch on public.tester_app_install_daily;
create trigger tester_app_install_daily_touch before update on public.tester_app_install_daily
  for each row execute function public.touch_updated_at();

alter table public.tester_app_install_daily enable row level security;

drop policy if exists tester_app_install_daily_self on public.tester_app_install_daily;
create policy tester_app_install_daily_self on public.tester_app_install_daily
  for select using (tester_id = public.current_tester_id());

drop policy if exists tester_app_install_daily_admin on public.tester_app_install_daily;
create policy tester_app_install_daily_admin on public.tester_app_install_daily
  for select using (public.is_admin());

revoke all on public.tester_app_install_daily from public, anon, authenticated;

alter table public.bug_reports
  add column if not exists install_history jsonb not null default '[]'::jsonb,
  add column if not exists install_history_captured_at timestamptz,
  add column if not exists install_window_start date,
  add column if not exists install_window_end date;

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

-- Older APKs call report_app_install_status. Keep it working and route active
-- projects through the daily record so history stays complete.
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
        'mobile_device_name', t.mobile_device_name,
        'mobile_device_seen_at', t.mobile_device_seen_at,
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
        'package_name', c.package_name,
        'group_email', g.email,
        'group_name', g.name,
        'play_opt_in_url', coalesce(c.play_opt_in_url, ''),
        'seat_number', s.seat_number,
        'state', s.state::text,
        'campaign_state', c.state::text,
        'joined_at', s.joined_at,
        'opted_in_at', s.opted_in_at,
        'opt_in_verified_at', s.opt_in_verified_at,
        'opt_in_verification', s.opt_in_verification,
        'days', case
          when s.opted_in_at is null then 0
          else floor(extract(epoch from (now() - s.opted_in_at)) / 86400)::int
        end,
        'required_testers', c.required_testers,
        'usage_status', (
          select jsonb_build_object(
            'installed', coalesce(us.installed, false),
            'distinct_days_used', coalesce(us.distinct_days_used, 0),
            'continuous_days_used', coalesce(us.continuous_days_used, 0),
            'meets_usage_requirement', coalesce(us.meets_usage_requirement, false),
            'last_usage_at', us.last_usage_at,
            'first_install_at', us.first_install_at
          )
          from public.tester_app_usage_summary us
          where us.tester_id = v_tester and us.campaign_id = c.id
        )
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
        'group_name', g.name,
        'seats_free', greatest(0, 15 - (
          select count(*) from public.campaign_seats s
          where s.campaign_id = c.id
        )::int + case when exists (
          select 1 from public.campaign_seats s
          where s.campaign_id = c.id and s.tester_id = v_tester
        ) then 1 else 0 end),
        'required_testers', c.required_testers
      ) order by c.started_at desc nulls last, c.created_at desc)
      from public.campaigns c
      left join public.google_groups g on g.id = c.group_id
      where c.state in ('live', 'at_risk')
        and c.play_opt_in_url is not null
        and not exists (
          select 1
          from public.campaign_seats s
          where s.campaign_id = c.id
            and s.tester_id = v_tester
            and s.state in ('joined', 'opted_in')
        )
        and (
          exists (
            select 1 from public.campaign_seats s
            where s.campaign_id = c.id and s.tester_id = v_tester
          )
          or (
            select count(*) from public.campaign_seats s
            where s.campaign_id = c.id
          ) < 15
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
        'created_at', r.created_at,
        'usage', case
          when r.usage_snapshot = '{}'::jsonb then null
          else r.usage_snapshot
        end,
        'usage_captured_at', r.usage_captured_at,
        'install_history', r.install_history,
        'install_history_captured_at', r.install_history_captured_at,
        'install_window_start', r.install_window_start,
        'install_window_end', r.install_window_end
      ) order by r.created_at desc)
      from public.bug_reports r
      join public.campaigns c on c.id = r.campaign_id
      where r.tester_id = v_tester
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.admin_report_detail(p_report_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_admin uuid := public.require_admin();
  v_report public.bug_reports%rowtype;
  v_campaign public.campaigns%rowtype;
  v_tester public.testers%rowtype;
  v_developer text;
  v_email text;
  v_current jsonb;
begin
  select * into v_report
  from public.bug_reports
  where id = p_report_id;

  if v_report.id is null then
    raise exception 'Report not found.';
  end if;

  select * into v_campaign
  from public.campaigns
  where id = v_report.campaign_id;

  select * into v_tester
  from public.testers
  where id = v_report.tester_id;

  select d.company_name, p.email
  into v_developer, v_email
  from public.developers d
  left join public.profiles p on p.id = v_tester.auth_user_id
  where d.id = v_campaign.developer_id;

  select jsonb_build_object(
    'package_name', us.package_name,
    'installed', us.installed,
    'distinct_days_used', us.distinct_days_used,
    'continuous_days_used', us.continuous_days_used,
    'meets_usage_requirement', us.meets_usage_requirement,
    'last_usage_at', us.last_usage_at,
    'first_install_at', us.first_install_at
  )
  into v_current
  from public.tester_app_usage_summary us
  where us.tester_id = v_report.tester_id
    and us.campaign_id = v_report.campaign_id;

  return jsonb_build_object(
    'report', jsonb_build_object(
      'id', v_report.id,
      'severity', v_report.severity::text,
      'status', v_report.status::text,
      'title', v_report.title,
      'body', v_report.body,
      'build_label', v_report.build_label,
      'device', v_report.device,
      'evidence_url', v_report.evidence_url,
      'created_at', v_report.created_at,
      'updated_at', v_report.updated_at
    ),
    'campaign', jsonb_build_object(
      'id', v_campaign.id,
      'app_name', v_campaign.app_name,
      'package_name', v_campaign.package_name,
      'state', v_campaign.state::text,
      'developer', v_developer
    ),
    'tester', jsonb_build_object(
      'id', v_tester.id,
      'display_name', v_tester.display_name,
      'email', v_email,
      'google_email', v_tester.google_email,
      'region', v_tester.region,
      'devices', to_jsonb(v_tester.devices),
      'mobile_device_name', v_tester.mobile_device_name
    ),
    'usage_snapshot', case
      when v_report.usage_snapshot = '{}'::jsonb then null
      else v_report.usage_snapshot
    end,
    'usage_captured_at', v_report.usage_captured_at,
    'install_history', v_report.install_history,
    'install_history_captured_at', v_report.install_history_captured_at,
    'install_window_start', v_report.install_window_start,
    'install_window_end', v_report.install_window_end,
    'current_usage', v_current
  );
end;
$$;

revoke all on function public.report_app_install_daily(uuid, date, boolean, text) from public, anon, authenticated;
revoke all on function public.report_app_install_status(uuid, boolean) from public, anon, authenticated;
revoke all on function public.file_report(uuid, text, text, text, text, text, text) from public, anon, authenticated;
revoke all on function public.tester_dashboard() from public, anon, authenticated;
revoke all on function public.admin_report_detail(uuid) from public, anon, authenticated;

grant execute on function public.report_app_install_daily(uuid, date, boolean, text) to authenticated;
grant execute on function public.report_app_install_status(uuid, boolean) to authenticated;
grant execute on function public.file_report(uuid, text, text, text, text, text, text) to authenticated;
grant execute on function public.tester_dashboard() to authenticated;
grant execute on function public.admin_report_detail(uuid) to authenticated;

notify pgrst, 'reload schema';
