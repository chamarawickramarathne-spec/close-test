-- Live migration 013: developers no longer receive tester email addresses.
-- Developer campaign payloads keep tester display names, devices and region,
-- but never the tester's Google account address. Operations keeps its own
-- tester roster in admin_dashboard. Run once after 012.

create or replace function public.developer_campaign_json(p_campaign_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'id', c.id,
    'app_name', c.app_name,
    'package_name', c.package_name,
    'state', c.state::text,
    'group_email', g.email,
    'group_state', g.state::text,
    'group_attached_at', g.provisioned_at,
    'play_opt_in_url', coalesce(c.play_opt_in_url, ''),
    'required_testers', c.required_testers,
    'payment_state', c.payment_state::text,
    'payment_amount_cents', c.payment_amount_cents,
    'payment_reference', c.payment_reference,
    'paid_at', c.paid_at,
    'seats_used', coalesce(h.seats_used, 0),
    'opted_in', coalesce(h.opted_in, 0),
    'days_banked', coalesce(h.days_banked, 0),
    'meets_requirement', coalesce(h.meets_requirement, false),
    'eligible_on', h.eligible_on,
    'created_at', c.created_at,
    'started_at', c.started_at,
    'passed_at', c.passed_at,
    'seats', coalesce((
      select jsonb_agg(jsonb_build_object(
        'seat_number', s.seat_number,
        'state', s.state::text,
        'joined_at', s.joined_at,
        'opted_in_at', s.opted_in_at,
        'tester_name', t.display_name,
        'devices', to_jsonb(t.devices),
        'region', t.region
      ) order by s.seat_number)
      from public.campaign_seats s
      join public.testers t on t.id = s.tester_id
      where s.campaign_id = c.id
        and s.state in ('joined', 'opted_in')
    ), '[]'::jsonb),
    'reports', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id,
        'title', r.title,
        'body', r.body,
        'severity', r.severity::text,
        'status', r.status::text,
        'build_label', r.build_label,
        'device', r.device,
        'evidence_url', r.evidence_url,
        'created_at', r.created_at,
        'tester_name', t.display_name
      ) order by r.created_at desc)
      from public.bug_reports r
      join public.testers t on t.id = r.tester_id
      where r.campaign_id = c.id
    ), '[]'::jsonb)
  )
  from public.campaigns c
  left join public.google_groups g on g.id = c.group_id
  left join public.campaign_health h on h.campaign_id = c.id
  where c.id = p_campaign_id;
$$;

notify pgrst, 'reload schema';
