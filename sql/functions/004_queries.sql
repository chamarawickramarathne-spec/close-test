-- Read models. The client calls these RPCs instead of selecting tables.

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

create or replace function public.developer_dashboard()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_dev uuid := public.require_developer();
begin
  return jsonb_build_object(
    'developer', (
      select jsonb_build_object(
        'id', d.id,
        'display_name', coalesce(p.display_name, ''),
        'company_name', d.company_name,
        'contact_email', d.contact_email,
        'google_email', d.google_email,
        'created_at', d.created_at
      )
      from public.developers d
      left join public.profiles p on p.id = d.auth_user_id
      where d.id = v_dev
    ),
    'campaigns', coalesce((
      select jsonb_agg(public.developer_campaign_json(c.id) order by c.created_at desc)
      from public.campaigns c
      where c.developer_id = v_dev
    ), '[]'::jsonb)
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
        'days', case
          when s.opted_in_at is null then 0
          else floor(extract(epoch from (now() - s.opted_in_at)) / 86400)::int
        end,
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
    'group_setup', coalesce((
      select jsonb_agg(jsonb_build_object(
        'campaign_id', c.id,
        'app_name', c.app_name,
        'developer', d.company_name,
        'package_name', c.package_name,
        'state', c.state::text,
        'reserved_group_email', c.reserved_group_email,
        'reserved_group_url_name', c.reserved_group_url_name,
        'reserved_group_display_name', c.reserved_group_display_name,
        'group_sequence', c.group_sequence,
        'group_identity_reserved_at', c.group_identity_reserved_at,
        'payment_reference', c.payment_reference,
        'paid_at', c.paid_at,
        'created_at', c.created_at
      ) order by c.group_identity_reserved_at nulls last, c.created_at)
      from public.campaigns c
      join public.developers d on d.id = c.developer_id
      where c.state in ('pending', 'awaiting_link')
        and c.group_id is null
        and c.payment_state = 'paid'
        and c.reserved_group_email is not null
    ), '[]'::jsonb),
    'groups', coalesce((
      select jsonb_agg(jsonb_build_object(
        'email', g.email,
        'name', g.name,
        'display_name', g.display_name,
        'developer', d.company_name,
        'state', g.state::text,
        'provisioned_at', g.provisioned_at,
        'settings_confirmed_at', g.settings_confirmed_at,
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
      ) order by c.created_at)
      from public.campaigns c
      join public.developers d on d.id = c.developer_id
      left join public.google_groups g on g.id = c.group_id
      where c.state in ('pending', 'awaiting_link')
        and c.payment_state = 'unpaid'
    ), '[]'::jsonb),
    'packages', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', pk.id,
        'name', pk.name,
        'amount_cents', pk.amount_cents,
        'tester_fee_cents', pk.tester_fee_cents,
        'is_active', pk.is_active,
        'campaigns_used', (select count(*) from public.campaigns c where c.payment_package_id = pk.id),
        'created_at', pk.created_at,
        'updated_at', pk.updated_at
      ) order by pk.is_active desc, pk.name)
      from public.payment_packages pk
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

create or replace function public.list_payment_packages()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then
    raise exception 'Sign in to load payment packages.';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', pk.id,
      'name', pk.name,
      'amount_cents', pk.amount_cents,
      'tester_fee_cents', pk.tester_fee_cents
    ) order by pk.amount_cents, pk.name)
    from public.payment_packages pk
    where pk.is_active
  ), '[]'::jsonb);
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
      'seats_used', coalesce(h.seats_used, 0),
      'seats_free', greatest(15 - v_testers_used, 0),
      'testers_used', v_testers_used,
      'opted_in', coalesce(h.opted_in, 0),
      'days_banked', coalesce(h.days_banked, 0),
      'meets_requirement', coalesce(h.meets_requirement, false),
      'eligible_on', h.eligible_on,
      'clock_started_at', h.threshold_opt_in_at,
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

create or replace function public.admin_report_detail(p_report_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_admin uuid := public.require_admin();
  v_report public.bug_reports%rowtype;
  v_campaign public.campaigns%rowtype;
  v_tester public.testers%rowtype;
  v_developer text;
  v_email text;
  v_current jsonb;
begin
  select * into v_report
  from public.bug_reports
  where id = p_report_id;

  if v_report.id is null then
    raise exception 'Report not found.';
  end if;

  select * into v_campaign
  from public.campaigns
  where id = v_report.campaign_id;

  select * into v_tester
  from public.testers
  where id = v_report.tester_id;

  select d.company_name, p.email
  into v_developer, v_email
  from public.developers d
  left join public.profiles p on p.id = v_tester.auth_user_id
  where d.id = v_campaign.developer_id;

  select jsonb_build_object(
    'package_name', us.package_name,
    'installed', us.installed,
    'distinct_days_used', us.distinct_days_used,
    'continuous_days_used', us.continuous_days_used,
    'meets_usage_requirement', us.meets_usage_requirement,
    'last_usage_at', us.last_usage_at,
    'first_install_at', us.first_install_at
  )
  into v_current
  from public.tester_app_usage_summary us
  where us.tester_id = v_report.tester_id
    and us.campaign_id = v_report.campaign_id;

  return jsonb_build_object(
    'report', jsonb_build_object(
      'id', v_report.id,
      'severity', v_report.severity::text,
      'status', v_report.status::text,
      'title', v_report.title,
      'body', v_report.body,
      'build_label', v_report.build_label,
      'device', v_report.device,
      'evidence_url', v_report.evidence_url,
      'created_at', v_report.created_at,
      'updated_at', v_report.updated_at
    ),
    'campaign', jsonb_build_object(
      'id', v_campaign.id,
      'app_name', v_campaign.app_name,
      'package_name', v_campaign.package_name,
      'state', v_campaign.state::text,
      'developer', v_developer
    ),
    'tester', jsonb_build_object(
      'id', v_tester.id,
      'display_name', v_tester.display_name,
      'email', v_email,
      'google_email', v_tester.google_email,
      'region', v_tester.region,
      'devices', to_jsonb(v_tester.devices),
      'mobile_device_name', v_tester.mobile_device_name
    ),
    'usage_snapshot', case
      when v_report.usage_snapshot = '{}'::jsonb then null
      else v_report.usage_snapshot
    end,
    'usage_captured_at', v_report.usage_captured_at,
    'install_history', v_report.install_history,
    'install_history_captured_at', v_report.install_history_captured_at,
    'install_window_start', v_report.install_window_start,
    'install_window_end', v_report.install_window_end,
    'current_usage', v_current
  );
end;
$$;

create or replace function public.admin_developer_detail(p_developer_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_admin uuid := public.require_admin();
  v_dev public.developers%rowtype;
begin
  select * into v_dev from public.developers where id = p_developer_id;
  if v_dev.id is null then
    raise exception 'Developer not found.';
  end if;

  return jsonb_build_object(
    'developer', jsonb_build_object(
      'id', v_dev.id,
      'company_name', v_dev.company_name,
      'contact_email', v_dev.contact_email,
      'google_email', v_dev.google_email,
      'display_name', (
        select p.display_name from public.profiles p where p.id = v_dev.auth_user_id
      ),
      'created_at', v_dev.created_at
    ),
    'totals', jsonb_build_object(
      'projects', (select count(*) from public.campaigns c where c.developer_id = p_developer_id),
      'live', (select count(*) from public.campaigns c
               where c.developer_id = p_developer_id and c.state in ('live', 'at_risk')),
      'passed', (select count(*) from public.campaigns c
                 where c.developer_id = p_developer_id and c.state = 'passed'),
      'testers_used', (select count(distinct s.tester_id)
                       from public.campaign_seats s
                       join public.campaigns c on c.id = s.campaign_id
                       where c.developer_id = p_developer_id),
      'active_seats', (select count(*)
                       from public.campaign_seats s
                       join public.campaigns c on c.id = s.campaign_id
                       where c.developer_id = p_developer_id
                         and s.state in ('joined', 'opted_in')),
      'reports', (select count(*)
                  from public.bug_reports r
                  join public.campaigns c on c.id = r.campaign_id
                  where c.developer_id = p_developer_id),
      'project_fees_paid_cents', (select coalesce(sum(c.payment_amount_cents), 0)
                                  from public.campaigns c
                                  where c.developer_id = p_developer_id
                                    and c.payment_state = 'paid'),
      'project_fees_due_cents', (select coalesce(sum(c.payment_amount_cents), 0)
                                 from public.campaigns c
                                 where c.developer_id = p_developer_id
                                   and c.payment_state = 'unpaid'
                                   and c.group_id is not null
                                   and c.state <> 'cancelled'),
      'tester_payouts_paid_cents', (select coalesce(sum(s.payout_amount_cents), 0)
                                    from public.campaign_seats s
                                    join public.campaigns c on c.id = s.campaign_id
                                    where c.developer_id = p_developer_id
                                      and s.payout_state = 'paid'),
      'tester_payouts_due_cents', (select coalesce(sum(s.payout_amount_cents), 0)
                                   from public.campaign_seats s
                                   join public.campaigns c on c.id = s.campaign_id
                                   where c.developer_id = p_developer_id
                                     and c.state = 'passed'
                                     and s.payout_state = 'unpaid'
                                     and exists (
                                       select 1 from public.bug_reports r
                                       where r.campaign_id = s.campaign_id
                                         and r.tester_id = s.tester_id
                                     ))
    ),
    'campaigns', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', c.id,
        'app_name', c.app_name,
        'package_name', c.package_name,
        'state', c.state::text,
        'payment_state', c.payment_state::text,
        'payment_amount_cents', c.payment_amount_cents,
        'payment_reference', c.payment_reference,
        'paid_at', c.paid_at,
        'seats_used', coalesce(h.seats_used, 0),
        'testers_used', (select count(*) from public.campaign_seats s where s.campaign_id = c.id),
        'opted_in', coalesce(h.opted_in, 0),
        'created_at', c.created_at
      ) order by c.created_at desc)
      from public.campaigns c
      left join public.campaign_health h on h.campaign_id = c.id
      where c.developer_id = p_developer_id
    ), '[]'::jsonb),
    'groups', coalesce((
      select jsonb_agg(jsonb_build_object(
        'email', g.email,
        'name', g.name,
        'state', g.state::text,
        'provisioned_at', g.provisioned_at,
        'created_at', g.created_at
      ) order by g.created_at desc)
      from public.google_groups g
      where g.developer_id = p_developer_id
    ), '[]'::jsonb),
    'testers', coalesce((
      select jsonb_agg(jsonb_build_object(
        'tester_id', x.tester_id,
        'display_name', x.display_name,
        'google_email', x.google_email,
        'campaigns', x.campaign_count,
        'active_seats', x.active_seats,
        'reports', x.report_count,
        'due_cents', x.due_cents,
        'paid_cents', x.paid_cents
      ) order by x.display_name)
      from (
        select t.id as tester_id,
               t.display_name,
               t.google_email,
               count(distinct s.campaign_id) as campaign_count,
               count(*) filter (where s.state in ('joined', 'opted_in')) as active_seats,
               (select count(*)
                from public.bug_reports r
                join public.campaigns rc on rc.id = r.campaign_id
                where r.tester_id = t.id and rc.developer_id = p_developer_id) as report_count,
               coalesce(sum(case
                 when c.state = 'passed'
                   and s.payout_state = 'unpaid'
                   and exists (
                     select 1 from public.bug_reports r
                     where r.campaign_id = s.campaign_id and r.tester_id = t.id
                   )
                 then s.payout_amount_cents else 0 end), 0) as due_cents,
               coalesce(sum(case
                 when s.payout_state = 'paid' then s.payout_amount_cents else 0 end), 0) as paid_cents
        from public.campaign_seats s
        join public.campaigns c on c.id = s.campaign_id
        join public.testers t on t.id = s.tester_id
        where c.developer_id = p_developer_id
        group by t.id, t.display_name, t.google_email
      ) x
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
        where a.detail->>'campaign_id' in (
            select c.id::text from public.campaigns c where c.developer_id = p_developer_id
          )
          or a.target in (
            select c.app_name from public.campaigns c where c.developer_id = p_developer_id
            union all
            select c.package_name from public.campaigns c where c.developer_id = p_developer_id
            union all
            select v_dev.company_name
            union all
            select v_dev.contact_email
            union all
            select v_dev.google_email
            union all
            select v_dev.id::text
          )
          or (a.detail ? 'company_name' and a.detail->>'company_name' = v_dev.company_name)
        order by a.created_at desc
        limit 50
      ) a
    ), '[]'::jsonb)
  );
end;
$$;
