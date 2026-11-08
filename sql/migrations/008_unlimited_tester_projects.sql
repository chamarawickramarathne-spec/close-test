-- Removes the per-tester project budget. Testers may join any number of
-- campaigns; each campaign still has a hard 15-seat cap.

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
  where campaign_id = p_campaign_id and state in ('joined', 'opted_in');

  if exists (
    select 1 from public.campaign_seats
    where campaign_id = p_campaign_id
      and tester_id = v_tester
      and state in ('joined', 'opted_in')
  ) then
    raise exception 'You are already in this project.';
  end if;

  if v_used >= 15 then
    raise exception 'All 15 seats in this group are taken.';
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
      raise exception 'All 15 seats in this group are taken.';
    end if;

    update public.campaign_seats
    set seat_number = v_seat_number,
        state = 'joined',
        joined_at = now(),
        opted_in_at = null,
        dropped_at = null
    where id = v_seat.id
    returning * into v_seat;
  else
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
      raise exception 'All 15 seats in this group are taken.';
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
        'play_opt_in_url', coalesce(c.play_opt_in_url, ''),
        'seat_number', s.seat_number,
        'state', s.state::text,
        'opted_in_at', s.opted_in_at,
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
        'seats_free', 15 - coalesce(h.seats_used, 0),
        'required_testers', c.required_testers
      ) order by c.started_at desc nulls last, c.created_at desc)
      from public.campaigns c
      left join public.google_groups g on g.id = c.group_id
      left join public.campaign_health h on h.campaign_id = c.id
      where c.state in ('live', 'at_risk')
        and c.play_opt_in_url is not null
        and not exists (
          select 1
          from public.campaign_seats s
          where s.campaign_id = c.id
            and s.tester_id = v_tester
            and s.state in ('joined', 'opted_in')
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

alter table public.testers drop column if exists max_seats;

notify pgrst, 'reload schema';
