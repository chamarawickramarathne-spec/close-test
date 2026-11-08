-- Tester payouts and per-tester / per-developer admin detail.
-- Run after 017.

alter table public.campaign_seats
  add column if not exists payout_amount_cents integer not null default 50
    check (payout_amount_cents between 1 and 1000000);

alter table public.campaign_seats
  add column if not exists payout_state public.payment_state not null default 'unpaid';

alter table public.campaign_seats
  add column if not exists payout_reference text;

alter table public.campaign_seats
  add column if not exists paid_at timestamptz;

alter table public.campaign_seats
  add column if not exists paid_by uuid references auth.users (id) on delete set null;

alter table public.campaign_seats
  drop constraint if exists campaign_seats_payout_paid_check;

alter table public.campaign_seats
  add constraint campaign_seats_payout_paid_check
  check (payout_state <> 'paid' or paid_at is not null);
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
        'paid_at', s.paid_at
      ) order by c.created_at desc)
      from public.campaign_seats s
      join public.campaigns c on c.id = s.campaign_id
      join public.developers d on d.id = c.developer_id
      where s.tester_id = p_tester_id
    ), '[]'::jsonb)
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

create or replace function public.confirm_tester_payout(
  p_campaign_id uuid,
  p_tester_id uuid,
  p_reference text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_admin uuid := public.require_admin();
  v_seat_id uuid;
  v_payout_state public.payment_state;
  v_amount integer;
  v_app text;
  v_campaign_state public.campaign_state;
  v_tester_name text;
  v_reports integer;
  v_ref text;
begin
  select s.id, s.payout_state, s.payout_amount_cents
  into v_seat_id, v_payout_state, v_amount
  from public.campaign_seats s
  where s.campaign_id = p_campaign_id and s.tester_id = p_tester_id
  for update;

  if v_seat_id is null then
    raise exception 'That tester does not hold a seat on this project.';
  end if;

  if v_payout_state = 'paid' then
    raise exception 'That tester payout is already recorded.';
  end if;

  select c.app_name, c.state
  into v_app, v_campaign_state
  from public.campaigns c
  where c.id = p_campaign_id;

  if v_campaign_state <> 'passed' then
    raise exception 'Tester payouts open only after the project passes.';
  end if;

  select count(*)
  into v_reports
  from public.bug_reports r
  where r.campaign_id = p_campaign_id and r.tester_id = p_tester_id;

  if v_reports = 0 then
    raise exception 'That tester has not filed a report on this project.';
  end if;

  select t.display_name into v_tester_name
  from public.testers t
  where t.id = p_tester_id;

  v_ref := nullif(trim(coalesce(p_reference, '')), '');
  if v_ref is null then
    v_ref := 'TP-' || upper(substr(replace(v_seat_id::text, '-', ''), 1, 8));
  end if;

  if length(v_ref) > 80 then
    raise exception 'Keep the payout reference under 80 characters.';
  end if;

  update public.campaign_seats
  set payout_state = 'paid',
      payout_reference = v_ref,
      paid_at = now(),
      paid_by = auth.uid()
  where id = v_seat_id;

  perform public.write_audit(
    'tester_payout.confirmed',
    v_app || ' - ' || v_tester_name,
    jsonb_build_object(
      'campaign_id', p_campaign_id,
      'tester_id', p_tester_id,
      'seat_id', v_seat_id,
      'amount_cents', v_amount,
      'reference', v_ref
    )
  );

  return jsonb_build_object(
    'campaign_id', p_campaign_id,
    'tester_id', p_tester_id,
    'payout_state', 'paid',
    'payout_reference', v_ref,
    'paid_at', now()
  );
end;
$$;
revoke execute on function public.admin_tester_detail(uuid) from public, anon;
revoke execute on function public.admin_developer_detail(uuid) from public, anon;
revoke execute on function public.confirm_tester_payout(uuid, uuid, text) from public, anon;

grant execute on function public.admin_tester_detail(uuid) to authenticated;
grant execute on function public.admin_developer_detail(uuid) to authenticated;
grant execute on function public.confirm_tester_payout(uuid, uuid, text) to authenticated;

notify pgrst, 'reload schema';
