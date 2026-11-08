-- Live migration 012: USD 15 project fee.
-- A project becomes live only after operations attaches a Google Group and
-- confirms the project fee. Existing live campaigns are treated as paid.
-- Run once in the Supabase SQL editor after 008 through 011.

do $$
begin
  if not exists (select 1 from pg_type where typname = 'payment_state') then
    create type public.payment_state as enum ('unpaid', 'paid');
  end if;
end
$$;

alter table public.campaigns
  add column if not exists payment_state public.payment_state not null default 'unpaid',
  add column if not exists payment_amount_cents integer not null default 1500,
  add column if not exists payment_reference text,
  add column if not exists paid_at timestamptz,
  add column if not exists payment_confirmed_by uuid references auth.users (id) on delete set null;

update public.campaigns
set payment_state = 'paid',
    paid_at = coalesce(passed_at, started_at, created_at, now())
where payment_state = 'unpaid'
  and state in ('live', 'at_risk', 'passed');

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'campaigns_payment_amount_check') then
    alter table public.campaigns
      add constraint campaigns_payment_amount_check
      check (payment_amount_cents between 100 and 1000000);
  end if;

  if not exists (select 1 from pg_constraint where conname = 'campaigns_paid_at_check') then
    alter table public.campaigns
      add constraint campaigns_paid_at_check
      check (payment_state <> 'paid' or paid_at is not null);
  end if;
end
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
        'google_email', t.google_email,
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

create or replace function public.confirm_payment(p_campaign_id uuid, p_reference text default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_admin     uuid := public.require_admin();
  v_reference text := nullif(btrim(coalesce(p_reference, '')), '');
  v_campaign  public.campaigns%rowtype;
  v_paid_at   timestamptz;
begin
  if length(coalesce(v_reference, '')) > 120 then
    raise exception 'Keep the payment reference under 120 characters.';
  end if;

  select * into v_campaign from public.campaigns where id = p_campaign_id for update;
  if not found then
    raise exception 'That project no longer exists.';
  end if;
  if v_campaign.group_id is null then
    raise exception 'Attach the Google Group before recording a payment.';
  end if;
  if v_campaign.state in ('passed', 'cancelled') then
    raise exception 'This project is closed.';
  end if;
  if v_campaign.payment_state = 'paid' then
    raise exception 'This project fee is already marked paid.';
  end if;

  update public.campaigns
  set payment_state = 'paid',
      paid_at = now(),
      payment_reference = v_reference,
      payment_confirmed_by = v_admin
  where id = p_campaign_id
  returning paid_at into v_paid_at;

  perform public.write_audit(
    'payment.confirmed',
    v_campaign.app_name,
    jsonb_build_object(
      'campaign_id', p_campaign_id,
      'amount_cents', v_campaign.payment_amount_cents,
      'reference', v_reference
    )
  );

  return jsonb_build_object(
    'campaign_id', p_campaign_id,
    'payment_state', 'paid',
    'payment_amount_cents', v_campaign.payment_amount_cents,
    'payment_reference', v_reference,
    'paid_at', v_paid_at
  );
end;
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

grant execute on function public.update_developer_profile(text, text, text, text)
  to authenticated;
grant execute on function public.update_tester_profile(text, text, text, text[])
  to authenticated;
grant execute on function public.confirm_payment(uuid, text)
  to authenticated;

notify pgrst, 'reload schema';
