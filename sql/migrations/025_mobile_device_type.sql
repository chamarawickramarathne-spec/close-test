-- 025: the tester device type is captured by TesterLoop Mobile and stored on
-- the tester record. Desktop clients display it read-only instead of asking the
-- tester to type a device name.

alter table public.testers
  add column if not exists mobile_device_name text check (
    mobile_device_name is null
    or length(btrim(mobile_device_name)) between 1 and 120
  );

alter table public.testers
  add column if not exists mobile_device_seen_at timestamptz;

create or replace function public.record_tester_device(p_device_name text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_tester   uuid := public.require_tester();
  v_device   text := regexp_replace(btrim(coalesce(p_device_name, '')), '\s+', ' ', 'g');
  v_previous text;
  v_now      timestamptz := now();
begin
  if length(v_device) < 1 or length(v_device) > 120 then
    raise exception 'The device name must be between 1 and 120 characters.';
  end if;

  if v_device ~ '[[:cntrl:]]' then
    raise exception 'The device name contains invalid characters.';
  end if;

  select mobile_device_name
  into v_previous
  from public.testers
  where id = v_tester
  for update;

  update public.testers
  set mobile_device_name = v_device,
      mobile_device_seen_at = v_now
  where id = v_tester;

  if v_previous is distinct from v_device then
    perform public.write_audit(
      'tester.device_reported',
      v_device,
      jsonb_build_object('tester_id', v_tester)
    );
  end if;

  return jsonb_build_object(
    'device_name', v_device,
    'seen_at', v_now
  );
end;
$$;

revoke execute on function public.record_tester_device(text) from public, anon, authenticated;
grant execute on function public.record_tester_device(text) to authenticated;

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

notify pgrst, 'reload schema';
