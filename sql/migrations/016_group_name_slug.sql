-- 016: store the Google Group URL slug alongside the group address.

alter table public.google_groups
  add column if not exists name text;

update public.google_groups
set name = coalesce(
  nullif(trim(both '._-' from regexp_replace(lower(split_part(email, '@', 1)), '[^a-z0-9._-]', '-', 'g')), ''),
  'group-' || left(id::text, 8)
)
where name is null or btrim(name) = '';

alter table public.google_groups
  alter column name set not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'google_groups_name_check'
  ) then
    alter table public.google_groups
      add constraint google_groups_name_check
      check (
        name = lower(name)
        and name ~ '^[a-z0-9]([a-z0-9._-]{0,198}[a-z0-9])?$'
      );
  end if;
end;
$$;

drop function if exists public.attach_group(uuid, text);

create or replace function public.attach_group(p_campaign_id uuid, p_group_email text, p_group_name text default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_admin  uuid := public.require_admin();
  v_email  text := lower(trim(coalesce(p_group_email, '')));
  v_name   text := lower(trim(coalesce(p_group_name, '')));
  v_campaign public.campaigns%rowtype;
  v_group  public.google_groups%rowtype;
begin
  if v_email !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Enter the group address as name@googlegroups.com.';
  end if;

  if v_name = '' then
    v_name := split_part(v_email, '@', 1);
  end if;

  if v_name !~ '^[a-z0-9]([a-z0-9._-]{0,198}[a-z0-9])?$' then
    raise exception 'Enter the Google Groups URL slug (letters, numbers, dots, underscores, hyphens).';
  end if;

  select * into v_campaign from public.campaigns where id = p_campaign_id for update;
  if not found then
    raise exception 'That project no longer exists.';
  end if;
  if v_campaign.state <> 'pending' or v_campaign.group_id is not null then
    raise exception 'This project already has a group or is no longer pending.';
  end if;
  if exists (select 1 from public.google_groups where email = v_email) then
    raise exception 'That group address is already attached to another project.';
  end if;

  insert into public.google_groups (developer_id, email, name, state, provisioned_at)
  values (v_campaign.developer_id, v_email, v_name, 'manual', now())
  returning * into v_group;

  update public.campaigns
  set group_id = v_group.id, state = 'awaiting_link'
  where id = p_campaign_id;

  perform public.write_audit(
    'group.attached',
    v_email,
    jsonb_build_object('campaign_id', p_campaign_id, 'admin_id', v_admin, 'group_name', v_group.name)
  );

  return jsonb_build_object(
    'id', v_group.id,
    'email', v_group.email,
    'name', v_group.name,
    'state', v_group.state::text,
    'provisioned_at', v_group.provisioned_at
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

revoke execute on function public.attach_group(uuid, text, text) from public, anon, authenticated;
grant execute on function public.attach_group(uuid, text, text) to authenticated;

notify pgrst, 'reload schema';
