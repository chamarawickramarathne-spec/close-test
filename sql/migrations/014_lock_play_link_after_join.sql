-- Live migration 014: lock the closed-test link once a tester has joined, add
-- the per-tester report flag to the roster, and expose the 12th opt-in date.
-- A developer may save or change the Play link while no tester has joined.
-- After the first seat exists, the link is final so testers cannot be pointed
-- at a different app or test. Run once after 013.

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
    'has_joined_testers', exists(
      select 1 from public.campaign_seats s
      where s.campaign_id = c.id
    ),
    'opted_in', coalesce(h.opted_in, 0),
    'days_banked', coalesce(h.days_banked, 0),
    'meets_requirement', coalesce(h.meets_requirement, false),
    'eligible_on', h.eligible_on,
    'created_at', c.created_at,
    'started_at', c.started_at,
    'clock_started_at', h.threshold_opt_in_at,
    'passed_at', c.passed_at,
    'seats', coalesce((
      select jsonb_agg(jsonb_build_object(
        'seat_number', s.seat_number,
        'state', s.state::text,
        'joined_at', s.joined_at,
        'opted_in_at', s.opted_in_at,
        'tester_name', t.display_name,
        'devices', to_jsonb(t.devices),
        'region', t.region,
        'has_report', exists(
          select 1 from public.bug_reports r
          where r.campaign_id = c.id and r.tester_id = s.tester_id
        )
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

create or replace function public.save_play_link(p_campaign_id uuid, p_url text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_dev      uuid := public.require_developer();
  v_url      text := trim(coalesce(p_url, ''));
  v_campaign public.campaigns%rowtype;
begin
  if length(v_url) > 500
     or v_url !~ '^https://play\.google\.com/(apps/testing/[A-Za-z0-9._-]+|store/apps/details\?id=[A-Za-z0-9._-]+(&[^[:space:]]*)?)$' then
    raise exception 'The link must be a Google Play testing link or store details link.';
  end if;

  select * into v_campaign from public.campaigns where id = p_campaign_id for update;
  if not found or v_campaign.developer_id <> v_dev then
    raise exception 'That project could not be found.';
  end if;
  if exists (
    select 1 from public.campaign_seats s
    where s.campaign_id = p_campaign_id
  ) then
    raise exception 'The closed-test link is locked because testers have already joined this project.';
  end if;
  if v_campaign.group_id is null then
    raise exception 'A closed-test link can only be saved once a group is attached.';
  end if;
  if v_campaign.payment_state <> 'paid' then
    raise exception 'This project needs the $15 fee confirmed before it can go live.';
  end if;
  if v_campaign.state not in ('awaiting_link', 'live', 'at_risk') then
    raise exception 'This project is not accepting a testing link.';
  end if;

  update public.campaigns
  set play_opt_in_url = v_url,
      state = case when state = 'awaiting_link' then 'live'::public.campaign_state else state end,
      started_at = coalesce(started_at, now())
  where id = p_campaign_id;

  perform public.write_audit(
    'campaign.link_saved',
    v_campaign.app_name,
    jsonb_build_object('campaign_id', p_campaign_id)
  );

  perform public.refresh_campaign_state(p_campaign_id);
  return public.developer_campaign_json(p_campaign_id);
end;
$$;

grant execute on function public.save_play_link(uuid, text) to authenticated;

notify pgrst, 'reload schema';
