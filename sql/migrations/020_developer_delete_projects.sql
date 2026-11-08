-- 020: developers can delete their own projects, but a project is locked from
-- editing or deletion for 14 days after the first confirmed opt-in. The lock
-- survives an opt-out because first_opt_in_at is stored on the campaign.
-- A project with already-paid tester payouts cannot be deleted.

-- Run once after 019.

alter table public.campaigns
  add column if not exists first_opt_in_at timestamptz;

update public.campaigns c
set first_opt_in_at = m.first_at
from (
  select campaign_id, min(coalesce(opt_in_verified_at, opted_in_at)) as first_at
  from public.campaign_seats
  where coalesce(opt_in_verified_at, opted_in_at) is not null
  group by campaign_id
) m
where c.id = m.campaign_id
  and c.first_opt_in_at is null;

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
    'group_name', g.name,
    'group_state', g.state::text,
    'group_attached_at', g.provisioned_at,
    'play_opt_in_url', coalesce(c.play_opt_in_url, ''),
    'required_testers', c.required_testers,
    'payment_state', c.payment_state::text,
    'payment_amount_cents', c.payment_amount_cents,
    'payment_reference', c.payment_reference,
    'paid_at', c.paid_at,
    'seats_used', coalesce(h.seats_used, 0),
    'testers_used', (
      select count(*) from public.campaign_seats s
      where s.campaign_id = c.id
    ),
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
    'first_opt_in_at', c.first_opt_in_at,
    'delete_locked', (
      c.first_opt_in_at is not null
      and c.state <> 'passed'
      and now() < c.first_opt_in_at + interval '14 days'
    ),
    'delete_unlocks_at', case
      when c.first_opt_in_at is null then null
      else c.first_opt_in_at + interval '14 days'
    end,
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

create or replace function public.delete_campaign(p_campaign_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_dev      uuid := public.require_developer();
  v_campaign public.campaigns%rowtype;
  v_app      text;
  v_testers  integer;
  v_paid     integer;
begin
  select * into v_campaign from public.campaigns where id = p_campaign_id for update;
  if not found or v_campaign.developer_id <> v_dev then
    raise exception 'That project could not be found.';
  end if;

  if v_campaign.first_opt_in_at is not null
     and v_campaign.state <> 'passed'
     and now() < v_campaign.first_opt_in_at + interval '14 days' then
    raise exception 'This project cannot be edited or deleted until 14 days after the first confirmed opt-in (%s).',
      to_char(v_campaign.first_opt_in_at + interval '14 days', 'DD Mon YYYY');
  end if;

  if exists (
    select 1 from public.campaign_seats
    where campaign_id = p_campaign_id and payout_state = 'paid'
  ) then
    raise exception 'This project has recorded tester payouts and cannot be deleted.';
  end if;

  v_app := v_campaign.app_name;
  select count(*) into v_testers
  from public.campaign_seats where campaign_id = p_campaign_id;
  select count(*) into v_paid
  from public.campaign_seats
  where campaign_id = p_campaign_id and payout_state = 'paid';

  delete from public.campaigns where id = p_campaign_id;

  perform public.write_audit(
    'campaign.deleted',
    v_app,
    jsonb_build_object(
      'campaign_id', p_campaign_id,
      'testers_used', v_testers,
      'paid_payouts', v_paid
    )
  );

  return jsonb_build_object('id', p_campaign_id, 'deleted', true);
end;
$$;

revoke execute on function public.delete_campaign(uuid) from public, anon, authenticated;

grant execute on function public.delete_campaign(uuid) to authenticated;

notify pgrst, 'reload schema';
