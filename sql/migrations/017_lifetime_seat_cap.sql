-- 017: a campaign may use at most 15 distinct testers over its lifetime.

-- Every tester is paid, so a dropped seat must not open a 16th paid tester.

-- Only the same tester may rejoin a dropped seat. A failed Google Group

-- check releases the seat so the tester can fix membership and rejoin.

-- Run once after 016.



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
        dropped_at = null
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

    insert into public.campaign_seats (campaign_id, tester_id, seat_number, state, joined_at)
    values (p_campaign_id, v_tester, v_seat_number, 'joined', now())
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

-- Called only by verify-opt-in (service_role) after a failed group check.

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

create or replace function public.admin_dashboard()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_admin uuid := public.require_admin();
begin
  return jsonb_build_object(
    'counts', jsonb_build_object(
      'developers', (select count(*) from public.developers),
      'pending', (select count(*) from public.campaigns where state = 'pending'),
      'active', (select count(*) from public.campaigns where state in ('live', 'at_risk')),
      'testers', (select count(*) from public.testers),
      'groups', (select count(*) from public.google_groups)
    ),
    'pending', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', c.id,
        'app_name', c.app_name,
        'developer', d.company_name,
        'package_name', c.package_name,
        'created_at', c.created_at
      ) order by c.created_at)
      from public.campaigns c
      join public.developers d on d.id = c.developer_id
      where c.state = 'pending'
    ), '[]'::jsonb),
    'groups', coalesce((
      select jsonb_agg(jsonb_build_object(
        'email', g.email,
        'name', g.name,
        'developer', d.company_name,
        'state', g.state::text,
        'provisioned_at', g.provisioned_at,
        'members', null
      ) order by g.created_at desc)
      from public.google_groups g
      join public.developers d on d.id = g.developer_id
    ), '[]'::jsonb),
    'campaigns', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', c.id,
        'app_name', c.app_name,
        'developer', d.company_name,
        'package_name', c.package_name,
        'state', c.state::text,
        'required_testers', c.required_testers,
        'payment_state', c.payment_state::text,
        'payment_amount_cents', c.payment_amount_cents,
        'payment_reference', c.payment_reference,
        'paid_at', c.paid_at,
        'seats_used', coalesce(h.seats_used, 0),
        'testers_used', (select count(*) from public.campaign_seats s where s.campaign_id = c.id),
        'opted_in', coalesce(h.opted_in, 0)
      ) order by c.created_at desc)
      from public.campaigns c
      join public.developers d on d.id = c.developer_id
      left join public.campaign_health h on h.campaign_id = c.id
    ), '[]'::jsonb),
    'developers', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', d.id,
        'company_name', d.company_name,
        'contact_email', d.contact_email,
        'google_email', d.google_email,
        'campaign_count', coalesce(cc.total, 0),
        'live_count', coalesce(cc.live, 0),
        'created_at', d.created_at
      ) order by d.created_at desc)
      from public.developers d
      left join (
        select developer_id,
               count(*) as total,
               count(*) filter (where state in ('live', 'at_risk')) as live
        from public.campaigns
        group by developer_id
      ) cc on cc.developer_id = d.id
    ), '[]'::jsonb),
    'testers', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', t.id,
        'display_name', t.display_name,
        'email', p.email,
        'google_email', t.google_email,
        'region', t.region,
        'reliability', t.reliability,
        'is_active', t.is_active,
        'joined_count', coalesce(j.joined_count, 0),
        'created_at', t.created_at
      ) order by t.created_at desc)
      from public.testers t
      left join public.profiles p on p.id = t.auth_user_id
      left join (
        select tester_id, count(*) as joined_count
        from public.campaign_seats
        where state in ('joined', 'opted_in')
        group by tester_id
      ) j on j.tester_id = t.id
    ), '[]'::jsonb),
    'feedback', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id,
        'app_name', c.app_name,
        'developer', d.company_name,
        'tester', t.display_name,
        'severity', r.severity::text,
        'status', r.status::text,
        'title', r.title,
        'created_at', r.created_at
      ) order by r.created_at desc)
      from public.bug_reports r
      join public.campaigns c on c.id = r.campaign_id
      join public.developers d on d.id = c.developer_id
      join public.testers t on t.id = r.tester_id
    ), '[]'::jsonb),
    'profile', jsonb_build_object(
      'display_name', (select display_name from public.profiles where id = v_admin),
      'email', (select email from public.profiles where id = v_admin),
      'note', (select note from public.admins where auth_user_id = v_admin)
    ),
    'payments', coalesce((
      select jsonb_agg(jsonb_build_object(
        'campaign_id', c.id,
        'app_name', c.app_name,
        'developer', d.company_name,
        'package_name', c.package_name,
        'amount_cents', c.payment_amount_cents,
        'group_email', g.email,
        'group_name', g.name,
        'group_attached_at', g.provisioned_at,
        'created_at', c.created_at
      ) order by g.provisioned_at nulls last, c.created_at)
      from public.campaigns c
      join public.developers d on d.id = c.developer_id
      left join public.google_groups g on g.id = c.group_id
      where c.state = 'awaiting_link'
        and c.payment_state = 'unpaid'
        and c.group_id is not null
    ), '[]'::jsonb),
    'audit', coalesce((
      select jsonb_agg(jsonb_build_object(
        'created_at', a.created_at,
        'actor_label', a.actor_label,
        'action', a.action,
        'target', a.target
      ) order by a.created_at desc)
      from (
        select created_at, actor_label, action, target
        from public.audit_log
        order by created_at desc
        limit 100
      ) a
    ), '[]'::jsonb)
  );
end;
$$;

grant execute on function public.join_campaign(uuid) to authenticated;



revoke execute on function public.release_unverified_seat(uuid, uuid) from public, anon, authenticated;

grant execute on function public.release_unverified_seat(uuid, uuid) to service_role;



notify pgrst, 'reload schema';
