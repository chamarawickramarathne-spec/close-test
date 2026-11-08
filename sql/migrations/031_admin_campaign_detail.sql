-- Admin project detail: roster, reports, usage and project audit for one close test project.
do $$
begin
  if to_regclass('public.tester_app_usage_summary') is null then
    raise exception 'Run migration 019_tester_app_usage.sql before 031_admin_campaign_detail.sql.';
  end if;
end;
$$;
create or replace function public.admin_campaign_detail(p_campaign_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_admin uuid := public.require_admin();
  v_campaign public.campaigns%rowtype;
  v_developer public.developers%rowtype;
  v_package text;
  v_group public.google_groups%rowtype;
  v_testers_used int;
  v_health public.campaign_health%rowtype;
begin
  select * into v_campaign
  from public.campaigns
  where id = p_campaign_id;

  if v_campaign.id is null then
    raise exception 'Project not found.';
  end if;

  select * into v_developer
  from public.developers
  where id = v_campaign.developer_id;

  select name into v_package
  from public.payment_packages
  where id = v_campaign.payment_package_id;

  if v_campaign.group_id is not null then
    select * into v_group
    from public.google_groups
    where id = v_campaign.group_id;
  end if;

  select count(*) into v_testers_used
  from public.campaign_seats s
  where s.campaign_id = p_campaign_id;

  select * into v_health
  from public.campaign_health
  where campaign_id = p_campaign_id;

  return jsonb_build_object(
    'usage_available', true,
    'campaign', jsonb_build_object(
      'id', v_campaign.id,
      'app_name', v_campaign.app_name,
      'package_name', v_campaign.package_name,
      'developer', v_developer.company_name,
      'developer_contact', v_developer.contact_email,
      'developer_google', v_developer.google_email,
      'state', v_campaign.state::text,
      'play_opt_in_url', coalesce(v_campaign.play_opt_in_url, ''),
      'required_testers', v_campaign.required_testers,
      'payment_package', v_package,
      'payment_state', v_campaign.payment_state::text,
      'payment_amount_cents', v_campaign.payment_amount_cents,
      'tester_payout_cents', v_campaign.tester_payout_cents,
      'payment_reference', v_campaign.payment_reference,
      'paid_at', v_campaign.paid_at,
      'group_email', v_group.email,
      'group_name', v_group.name,
      'group_display_name', v_group.display_name,
      'group_state', v_group.state::text,
      'group_provisioned_at', v_group.provisioned_at,
      'group_settings_confirmed_at', v_group.settings_confirmed_at,
      'seats_used', coalesce(v_health.seats_used, 0),
      'seats_free', greatest(15 - v_testers_used, 0),
      'testers_used', v_testers_used,
      'opted_in', coalesce(v_health.opted_in, 0),
      'days_banked', coalesce(v_health.days_banked, 0),
      'meets_requirement', coalesce(v_health.meets_requirement, false),
      'eligible_on', v_health.eligible_on,
      'clock_started_at', v_health.threshold_opt_in_at,
      'first_opt_in_at', v_campaign.first_opt_in_at,
      'started_at', v_campaign.started_at,
      'passed_at', v_campaign.passed_at,
      'cancelled_at', v_campaign.cancelled_at,
      'created_at', v_campaign.created_at
    ),
    'totals', (
      select jsonb_build_object(
        'testers_used', count(*),
        'seats_used', count(*) filter (where s.state in ('joined', 'opted_in')),
        'joined', count(*) filter (where s.state = 'joined'),
        'opted_in', count(*) filter (where s.state = 'opted_in'),
        'verified_opt_in', count(*) filter (
          where s.state in ('joined', 'opted_in') and s.opt_in_verified_at is not null
        ),
        'dropped', count(*) filter (where s.state = 'dropped'),
        'reports', (
          select count(*) from public.bug_reports r where r.campaign_id = p_campaign_id
        ),
        'reporters', (
          select count(distinct r.tester_id) from public.bug_reports r
          where r.campaign_id = p_campaign_id
        ),
        'open_reports', (
          select count(*) from public.bug_reports r
          where r.campaign_id = p_campaign_id and r.status in ('open', 'triaged')
        ),
        'usage_reported', count(*) filter (
          where s.state in ('joined', 'opted_in')
            and exists (
              select 1 from public.tester_app_usage_summary us
              where us.tester_id = s.tester_id and us.campaign_id = s.campaign_id
            )
        ),
        'usage_met', count(*) filter (
          where s.state in ('joined', 'opted_in')
            and exists (
              select 1 from public.tester_app_usage_summary us
              where us.tester_id = s.tester_id
                and us.campaign_id = s.campaign_id
                and us.meets_usage_requirement
            )
        ),
        'payouts_eligible_cents', coalesce(sum(case
          when v_campaign.state = 'passed'
            and exists (
              select 1 from public.bug_reports r
              where r.campaign_id = s.campaign_id and r.tester_id = s.tester_id
            )
          then s.payout_amount_cents else 0 end), 0),
        'payouts_due_cents', coalesce(sum(case
          when v_campaign.state = 'passed'
            and s.payout_state = 'unpaid'
            and exists (
              select 1 from public.bug_reports r
              where r.campaign_id = s.campaign_id and r.tester_id = s.tester_id
            )
          then s.payout_amount_cents else 0 end), 0),
        'payouts_paid_cents', coalesce(sum(case
          when s.payout_state = 'paid' then s.payout_amount_cents else 0 end), 0)
      )
      from public.campaign_seats s
      where s.campaign_id = p_campaign_id
    ),
    'testers', coalesce((
      select jsonb_agg(jsonb_build_object(
        'tester_id', s.tester_id,
        'display_name', t.display_name,
        'google_email', t.google_email,
        'region', t.region,
        'seat_number', s.seat_number,
        'state', s.state::text,
        'joined_at', s.joined_at,
        'opted_in_at', s.opted_in_at,
        'opt_in_verified_at', s.opt_in_verified_at,
        'dropped_at', s.dropped_at,
        'report_count', (
          select count(*) from public.bug_reports r
          where r.campaign_id = s.campaign_id and r.tester_id = s.tester_id
        ),
        'last_report_at', (
          select max(r.created_at) from public.bug_reports r
          where r.campaign_id = s.campaign_id and r.tester_id = s.tester_id
        ),
        'payout_amount_cents', s.payout_amount_cents,
        'payout_state', s.payout_state::text,
        'payout_reference', s.payout_reference,
        'paid_at', s.paid_at,
        'usage', (
          select jsonb_build_object(
            'installed', us.installed,
            'distinct_days_used', us.distinct_days_used,
            'continuous_days_used', us.continuous_days_used,
            'meets_usage_requirement', us.meets_usage_requirement,
            'last_usage_at', us.last_usage_at,
            'first_install_at', us.first_install_at
          )
          from public.tester_app_usage_summary us
          where us.tester_id = s.tester_id and us.campaign_id = s.campaign_id
        )
      ) order by s.seat_number)
      from public.campaign_seats s
      join public.testers t on t.id = s.tester_id
      where s.campaign_id = p_campaign_id
    ), '[]'::jsonb),
    'reports', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id,
        'tester_id', r.tester_id,
        'tester_name', t.display_name,
        'severity', r.severity::text,
        'status', r.status::text,
        'title', r.title,
        'body', r.body,
        'build_label', r.build_label,
        'device', r.device,
        'evidence_url', r.evidence_url,
        'created_at', r.created_at,
        'updated_at', r.updated_at,
        'usage_snapshot', case
          when r.usage_snapshot = '{}'::jsonb then null
          else r.usage_snapshot
        end,
        'usage_captured_at', r.usage_captured_at
      ) order by r.created_at desc)
      from public.bug_reports r
      join public.testers t on t.id = r.tester_id
      where r.campaign_id = p_campaign_id
    ), '[]'::jsonb),
    'audit', coalesce((
      select jsonb_agg(jsonb_build_object(
        'created_at', a.created_at,
        'actor_label', a.actor_label,
        'action', a.action,
        'target', a.target
      ) order by a.created_at desc)
      from (
        select a.created_at, a.actor_label, a.action, a.target
        from public.audit_log a
        where a.detail->>'campaign_id' = p_campaign_id::text
        order by a.created_at desc
        limit 50
      ) a
    ), '[]'::jsonb)
  );
end;
$$;

revoke execute on function public.admin_campaign_detail(uuid) from public, anon;
grant execute on function public.admin_campaign_detail(uuid) to authenticated;

notify pgrst, 'reload schema';