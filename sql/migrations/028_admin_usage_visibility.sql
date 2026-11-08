-- Migration 028: expose tester mobile usage summaries to TesterLoop Admin.

do $$
begin
  if to_regclass('public.tester_app_usage_summary') is null then
    raise exception 'Run migration 019_tester_app_usage.sql before 028_admin_usage_visibility.sql.';
  end if;
end;
$$;

create or replace function public.admin_tester_detail(p_tester_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_admin uuid := public.require_admin();
begin
  if not exists (select 1 from public.testers where id = p_tester_id) then
    raise exception 'Tester not found.';
  end if;

  return jsonb_build_object(
    'usage_available', true,
    'tester', (
      select jsonb_build_object(
        'id', t.id,
        'display_name', t.display_name,
        'email', p.email,
        'google_email', t.google_email,
        'region', t.region,
        'devices', to_jsonb(t.devices),
        'reliability', t.reliability,
        'is_active', t.is_active,
        'created_at', t.created_at
      )
      from public.testers t
      left join public.profiles p on p.id = t.auth_user_id
      where t.id = p_tester_id
    ),
    'totals', (
      select jsonb_build_object(
        'projects', count(*),
        'active_seats', count(*) filter (where s.state in ('joined', 'opted_in')),
        'reports', (select count(*) from public.bug_reports r where r.tester_id = p_tester_id),
        'eligible_count', count(*) filter (
          where c.state = 'passed'
            and exists (
              select 1 from public.bug_reports r
              where r.campaign_id = s.campaign_id and r.tester_id = s.tester_id
            )
        ),
        'eligible_cents', coalesce(sum(case
          when c.state = 'passed'
            and exists (
              select 1 from public.bug_reports r
              where r.campaign_id = s.campaign_id and r.tester_id = s.tester_id
            )
          then s.payout_amount_cents else 0 end), 0),
        'due_cents', coalesce(sum(case
          when c.state = 'passed'
            and s.payout_state = 'unpaid'
            and exists (
              select 1 from public.bug_reports r
              where r.campaign_id = s.campaign_id and r.tester_id = s.tester_id
            )
          then s.payout_amount_cents else 0 end), 0),
        'paid_cents', coalesce(sum(case
          when s.payout_state = 'paid' then s.payout_amount_cents else 0 end), 0)
      )
      from public.campaign_seats s
      join public.campaigns c on c.id = s.campaign_id
      where s.tester_id = p_tester_id
    ),
    'campaigns', coalesce((
      select jsonb_agg(jsonb_build_object(
        'seat_id', s.id,
        'campaign_id', c.id,
        'app_name', c.app_name,
        'developer', d.company_name,
        'package_name', c.package_name,
        'campaign_state', c.state::text,
        'seat_state', s.state::text,
        'seat_number', s.seat_number,
        'joined_at', s.joined_at,
        'opted_in_at', s.opted_in_at,
        'opt_in_verified_at', s.opt_in_verified_at,
        'report_count', (
          select count(*) from public.bug_reports r
          where r.campaign_id = s.campaign_id and r.tester_id = s.tester_id
        ),
        'last_report_at', (
          select max(r.created_at) from public.bug_reports r
          where r.campaign_id = s.campaign_id and r.tester_id = s.tester_id
        ),
        'fee_cents', s.payout_amount_cents,
        'eligible', (
          c.state = 'passed'
          and exists (
            select 1 from public.bug_reports r
            where r.campaign_id = s.campaign_id and r.tester_id = s.tester_id
          )
        ),
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
          where us.tester_id = s.tester_id
            and us.campaign_id = s.campaign_id
        )
      ) order by c.created_at desc)
      from public.campaign_seats s
      join public.campaigns c on c.id = s.campaign_id
      join public.developers d on d.id = c.developer_id
      where s.tester_id = p_tester_id
    ), '[]'::jsonb)
  );
end;
$$;

revoke execute on function public.admin_tester_detail(uuid) from public, anon;
grant execute on function public.admin_tester_detail(uuid) to authenticated;

notify pgrst, 'reload schema';
