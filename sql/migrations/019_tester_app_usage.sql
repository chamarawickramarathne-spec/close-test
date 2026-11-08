-- Migration 019: Tester app install and usage tracking (Android tester app)
-- Only for testers. Tracks installed developer apps and 14-day usage.

create table if not exists public.tester_app_installs (
  id uuid primary key default gen_random_uuid(),
  tester_id uuid not null references public.testers(id) on delete cascade,
  campaign_id uuid not null references public.campaigns(id) on delete cascade,
  package_name text not null,
  first_seen_installed_at timestamptz,
  last_seen_installed_at timestamptz,
  uninstalled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tester_id, campaign_id)
);

create table if not exists public.tester_app_usage (
  id uuid primary key default gen_random_uuid(),
  tester_id uuid not null references public.testers(id) on delete cascade,
  campaign_id uuid not null references public.campaigns(id) on delete cascade,
  package_name text not null,
  usage_date date not null,
  total_foreground_ms bigint not null default 0,
  sessions integer not null default 0,
  first_used_at timestamptz,
  last_used_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tester_id, campaign_id, usage_date)
);

create table if not exists public.tester_app_usage_summary (
  tester_id uuid not null references public.testers(id) on delete cascade,
  campaign_id uuid not null references public.campaigns(id) on delete cascade,
  package_name text not null,
  installed boolean not null default false,
  distinct_days_used integer not null default 0,
  continuous_days_used integer not null default 0,
  first_install_at timestamptz,
  last_usage_at timestamptz,
  meets_usage_requirement boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (tester_id, campaign_id)
);

drop trigger if exists tester_app_installs_touch on public.tester_app_installs;
drop trigger if exists tester_app_usage_touch on public.tester_app_usage;
drop trigger if exists tester_app_usage_summary_touch on public.tester_app_usage_summary;

create trigger tester_app_installs_touch before update on public.tester_app_installs
  for each row execute function public.touch_updated_at();
create trigger tester_app_usage_touch before update on public.tester_app_usage
  for each row execute function public.touch_updated_at();
create trigger tester_app_usage_summary_touch before update on public.tester_app_usage_summary
  for each row execute function public.touch_updated_at();

alter table public.tester_app_installs enable row level security;
alter table public.tester_app_usage enable row level security;
alter table public.tester_app_usage_summary enable row level security;

drop policy if exists tester_app_installs_self on public.tester_app_installs;
drop policy if exists tester_app_usage_self on public.tester_app_usage;
drop policy if exists tester_app_usage_summary_self on public.tester_app_usage_summary;

create policy tester_app_installs_self on public.tester_app_installs
  for all
  using (tester_id = public.current_tester_id())
  with check (tester_id = public.current_tester_id());

create policy tester_app_usage_self on public.tester_app_usage
  for all
  using (tester_id = public.current_tester_id())
  with check (tester_id = public.current_tester_id());

create policy tester_app_usage_summary_self on public.tester_app_usage_summary
  for all
  using (tester_id = public.current_tester_id())
  with check (tester_id = public.current_tester_id());

drop policy if exists tester_app_installs_admin on public.tester_app_installs;
drop policy if exists tester_app_usage_admin on public.tester_app_usage;
drop policy if exists tester_app_usage_summary_admin on public.tester_app_usage_summary;

create policy tester_app_installs_admin on public.tester_app_installs
  for select using (public.is_admin());
create policy tester_app_usage_admin on public.tester_app_usage
  for select using (public.is_admin());
create policy tester_app_usage_summary_admin on public.tester_app_usage_summary
  for select using (public.is_admin());

revoke all on public.tester_app_installs from public, anon, authenticated;
revoke all on public.tester_app_usage from public, anon, authenticated;
revoke all on public.tester_app_usage_summary from public, anon, authenticated;

-- Report install status for a joined campaign
create or replace function public.report_app_install_status(p_campaign_id uuid, p_installed boolean)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_tester uuid := public.require_tester();
  v_campaign public.campaigns%rowtype;
  v_seat public.campaign_seats%rowtype;
  v_row public.tester_app_installs%rowtype;
begin
  select * into v_campaign from public.campaigns where id = p_campaign_id;
  if not found then
    raise exception 'That project no longer exists.';
  end if;

  select * into v_seat
  from public.campaign_seats
  where campaign_id = p_campaign_id and tester_id = v_tester
    and state in ('joined', 'opted_in');
  if not found then
    raise exception 'Join this project before reporting install status.';
  end if;

  insert into public.tester_app_installs (tester_id, campaign_id, package_name, first_seen_installed_at, last_seen_installed_at)
  values (v_tester, p_campaign_id, v_campaign.package_name,
          case when p_installed then now() else null end,
          case when p_installed then now() else null end)
  on conflict (tester_id, campaign_id) do update set
    package_name = excluded.package_name,
    last_seen_installed_at = case when p_installed then now() else public.tester_app_installs.last_seen_installed_at end,
    first_seen_installed_at = coalesce(public.tester_app_installs.first_seen_installed_at, case when p_installed then now() else null end),
    uninstalled_at = case when p_installed then null else coalesce(public.tester_app_installs.uninstalled_at, now()) end,
    updated_at = now()
  returning * into v_row;

  insert into public.tester_app_usage_summary (tester_id, campaign_id, package_name, installed, first_install_at)
  values (v_tester, p_campaign_id, v_campaign.package_name, p_installed, v_row.first_seen_installed_at)
  on conflict (tester_id, campaign_id) do update set
    installed = p_installed,
    first_install_at = coalesce(public.tester_app_usage_summary.first_install_at, v_row.first_seen_installed_at),
    updated_at = now();

  return jsonb_build_object(
    'campaign_id', p_campaign_id,
    'package_name', v_campaign.package_name,
    'installed', p_installed,
    'first_seen_installed_at', v_row.first_seen_installed_at,
    'last_seen_installed_at', v_row.last_seen_installed_at,
    'uninstalled_at', v_row.uninstalled_at
  );
end;
$$;

-- Report daily usage for a joined campaign
create or replace function public.report_app_usage_daily(p_campaign_id uuid, p_date date, p_foreground_ms bigint, p_sessions integer)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_tester uuid := public.require_tester();
  v_campaign public.campaigns%rowtype;
  v_seat public.campaign_seats%rowtype;
  v_ms bigint := greatest(coalesce(p_foreground_ms, 0), 0);
  v_sess integer := greatest(coalesce(p_sessions, 0), 0);
  v_days integer;
  v_cont integer;
  v_meets boolean := false;
begin
  if p_date is null or p_date < current_date - 1 or p_date > current_date then
    raise exception 'Usage can only be reported for today or yesterday.';
  end if;

  select * into v_campaign from public.campaigns where id = p_campaign_id;
  if not found then
    raise exception 'That project no longer exists.';
  end if;

  select * into v_seat
  from public.campaign_seats
  where campaign_id = p_campaign_id and tester_id = v_tester
    and state in ('joined', 'opted_in');
  if not found then
    raise exception 'Join this project before reporting usage.';
  end if;

  insert into public.tester_app_usage (tester_id, campaign_id, package_name, usage_date, total_foreground_ms, sessions, first_used_at, last_used_at)
  values (v_tester, p_campaign_id, v_campaign.package_name, p_date, v_ms, v_sess, now(), now())
  on conflict (tester_id, campaign_id, usage_date) do update set
    total_foreground_ms = greatest(public.tester_app_usage.total_foreground_ms, excluded.total_foreground_ms),
    sessions = greatest(public.tester_app_usage.sessions, excluded.sessions),
    last_used_at = now(),
    updated_at = now();

  -- recompute distinct days with usage >= 60s
  select count(distinct usage_date)
  into v_days
  from public.tester_app_usage
  where tester_id = v_tester and campaign_id = p_campaign_id and total_foreground_ms >= 60000;

  -- count the run of consecutive days ending today or yesterday; an older run is stale
  with days as (
    select distinct usage_date
    from public.tester_app_usage
    where tester_id = v_tester and campaign_id = p_campaign_id and total_foreground_ms >= 60000
  ),
  latest as (
    select max(usage_date) as last_day from days
  ),
  seq as (
    select usage_date, usage_date - (row_number() over (order by usage_date desc))::int as grp
    from days
  )
  select case
    when (select last_day from latest) >= current_date - 1 then (
      select count(*)
      from seq
      where grp = (select grp from seq where usage_date = (select last_day from latest))
    )
    else 0
  end
  into v_cont;

  v_meets := (coalesce(v_cont, 0) >= 14);

  insert into public.tester_app_usage_summary (tester_id, campaign_id, package_name, installed, distinct_days_used, continuous_days_used, last_usage_at, meets_usage_requirement)
  values (v_tester, p_campaign_id, v_campaign.package_name, true, v_days, coalesce(v_cont,0), now(), v_meets)
  on conflict (tester_id, campaign_id) do update set
    distinct_days_used = v_days,
    continuous_days_used = coalesce(v_cont,0),
    last_usage_at = now(),
    meets_usage_requirement = v_meets,
    updated_at = now();

  return jsonb_build_object(
    'campaign_id', p_campaign_id,
    'date', p_date,
    'days_used_distinct', v_days,
    'days_used_continuous', coalesce(v_cont,0),
    'meets_usage_requirement', v_meets
  );
end;
$$;

create or replace function public.get_tester_usage_status(p_campaign_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_tester uuid := public.require_tester();
  v_seat public.campaign_seats%rowtype;
  v_sum public.tester_app_usage_summary%rowtype;
  v_inst public.tester_app_installs%rowtype;
begin
  select * into v_seat
  from public.campaign_seats
  where campaign_id = p_campaign_id and tester_id = v_tester
    and state in ('joined', 'opted_in');
  if not found then
    raise exception 'Join this project to view usage status.';
  end if;

  select * into v_sum from public.tester_app_usage_summary where tester_id = v_tester and campaign_id = p_campaign_id;
  select * into v_inst from public.tester_app_installs where tester_id = v_tester and campaign_id = p_campaign_id;

  return jsonb_build_object(
    'campaign_id', p_campaign_id,
    'installed', coalesce(v_sum.installed, false),
    'first_install_at', coalesce(v_sum.first_install_at, v_inst.first_seen_installed_at),
    'last_seen_installed_at', v_inst.last_seen_installed_at,
    'uninstalled_at', v_inst.uninstalled_at,
    'distinct_days_used', coalesce(v_sum.distinct_days_used, 0),
    'continuous_days_used', coalesce(v_sum.continuous_days_used, 0),
    'meets_usage_requirement', coalesce(v_sum.meets_usage_requirement, false),
    'last_usage_at', v_sum.last_usage_at
  );
end;
$$;

revoke all on function public.report_app_install_status(uuid, boolean) from public;
revoke all on function public.report_app_usage_daily(uuid, date, bigint, integer) from public;
revoke all on function public.get_tester_usage_status(uuid) from public;
grant execute on function public.report_app_install_status(uuid, boolean) to authenticated;
grant execute on function public.report_app_usage_daily(uuid, date, bigint, integer) to authenticated;
grant execute on function public.get_tester_usage_status(uuid) to authenticated;

-- Extend tester_dashboard to include usage status
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
        'package_name', c.package_name,
        'group_email', g.email,
        'group_name', g.name,
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
        'created_at', r.created_at
      ) order by r.created_at desc)
      from public.bug_reports r
      join public.campaigns c on c.id = r.campaign_id
      where r.tester_id = v_tester
    ), '[]'::jsonb)
  );
end;
$$;

notify pgrst, 'reload schema';
