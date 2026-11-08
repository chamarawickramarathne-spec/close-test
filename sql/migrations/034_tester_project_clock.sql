-- The tester 14-day clock is the project clock, not each tester's own opt-in age.
-- A project clock starts only after required_testers (12) have confirmed opt-in;
-- campaign_health.threshold_opt_in_at is the 12th opt-in and days_banked is the
-- days since that moment (0 until the threshold is reached).
do $$
begin
  if to_regclass('public.campaign_health') is null then
    raise exception 'Run sql/schema/001_init.sql before 034_tester_project_clock.sql.';
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
        'days', coalesce(ch.days_banked, 0),
        'clock_started_at', ch.threshold_opt_in_at,
        'confirmed_testers', coalesce(ch.opted_in, 0),
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
      left join public.campaign_health ch on ch.campaign_id = c.id
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

revoke all on function public.tester_dashboard() from public, anon, authenticated;
grant execute on function public.tester_dashboard() to authenticated;

notify pgrst, 'reload schema';
