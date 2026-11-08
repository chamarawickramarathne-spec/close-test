-- Online project-fee payment through Lemon Squeezy.
--
-- The developer opens a hosted checkout created by the create-payment Edge
-- Function. Lemon Squeezy calls ls-webhook on order_created / order_refunded.
-- The webhook is the only writer that can mark a fee paid online; the amount is
-- always read from the campaign, never from the client.
--
-- Run after 034. Safe to rerun.

do $$
begin
  if to_regclass('public.campaigns') is null
     or to_regclass('public.payment_packages') is null
     or to_regclass('public.campaign_health') is null then
    raise exception 'Run migrations 001-034 before 035_online_payments.sql.';
  end if;
end $$;

alter table public.campaigns
  add column if not exists payment_paid_via text,
  add column if not exists payment_provider text,
  add column if not exists payment_provider_ref text;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'campaigns_payment_paid_via_check'
  ) then
    alter table public.campaigns
      add constraint campaigns_payment_paid_via_check
      check (payment_paid_via is null or payment_paid_via in ('manual', 'online'));
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'campaigns_payment_provider_check'
  ) then
    alter table public.campaigns
      add constraint campaigns_payment_provider_check
      check (payment_provider is null or payment_provider in ('lemonsqueezy'));
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'campaigns_payment_provider_ref_check'
  ) then
    alter table public.campaigns
      add constraint campaigns_payment_provider_ref_check
      check (payment_provider_ref is null or length(payment_provider_ref) <= 100);
  end if;
end $$;

update public.campaigns
set payment_paid_via = 'manual'
where payment_state = 'paid'
  and payment_paid_via is null;

create table if not exists public.payment_intents (
  id                   uuid primary key default gen_random_uuid(),
  campaign_id          uuid not null references public.campaigns (id) on delete cascade,
  developer_id         uuid not null references public.developers (id) on delete cascade,
  provider             text not null default 'lemonsqueezy'
    check (provider in ('lemonsqueezy')),
  provider_checkout_id text check (
    provider_checkout_id is null or length(provider_checkout_id) <= 200
  ),
  checkout_url         text check (
    checkout_url is null or length(checkout_url) <= 1000
  ),
  amount_cents         integer not null check (amount_cents between 100 and 1000000),
  currency             text not null default 'USD' check (currency = 'USD'),
  status               text not null default 'created'
    check (status in ('created', 'paid', 'expired', 'failed')),
  provider_order_id    text check (
    provider_order_id is null or length(provider_order_id) <= 100
  ),
  provider_subtotal_cents integer check (
    provider_subtotal_cents is null or provider_subtotal_cents >= 0
  ),
  provider_total_cents integer check (
    provider_total_cents is null or provider_total_cents >= 0
  ),
  is_test              boolean not null default false,
  expires_at           timestamptz,
  paid_at              timestamptz,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  constraint payment_intents_paid_check check (
    status <> 'paid' or paid_at is not null
  )
);

create unique index if not exists payment_intents_order_key
  on public.payment_intents (provider_order_id)
  where provider_order_id is not null;

create unique index if not exists payment_intents_open_campaign_key
  on public.payment_intents (campaign_id)
  where status = 'created';

create index if not exists payment_intents_campaign_idx
  on public.payment_intents (campaign_id, created_at desc);

alter table public.payment_intents enable row level security;

revoke all on public.payment_intents from public, anon, authenticated;

-- Developer-facing: start or reuse a checkout for their own unpaid project.
create or replace function public.prepare_payment_intent(p_campaign_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_dev      uuid := public.require_developer();
  v_campaign public.campaigns%rowtype;
  v_intent   public.payment_intents%rowtype;
  v_profile  public.profiles%rowtype;
  v_intent_id uuid;
begin
  select * into v_campaign
  from public.campaigns
  where id = p_campaign_id
  for update;

  if not found or v_campaign.developer_id <> v_dev then
    raise exception 'That project could not be found.';
  end if;
  if v_campaign.state not in ('pending', 'awaiting_link') then
    raise exception 'This project is not waiting for payment.';
  end if;
  if v_campaign.payment_state = 'paid' then
    raise exception 'This project fee is already paid.';
  end if;

  select * into v_intent
  from public.payment_intents
  where campaign_id = p_campaign_id
    and status = 'created'
  order by created_at desc
  limit 1
  for update;

  if found then
    if v_intent.checkout_url is not null
       and v_intent.expires_at is not null
       and v_intent.expires_at > now() then
      v_intent_id := v_intent.id;
    else
      if v_intent.created_at > now() - interval '10 seconds' then
        raise exception 'Wait a few seconds before opening the checkout again.';
      end if;
      update public.payment_intents
      set status = 'expired',
          updated_at = now()
      where id = v_intent.id;
    end if;
  end if;

  if v_intent_id is null then
    insert into public.payment_intents (
      campaign_id,
      developer_id,
      amount_cents,
      currency,
      expires_at
    )
    values (
      p_campaign_id,
      v_dev,
      v_campaign.payment_amount_cents,
      'USD',
      now() + interval '1 hour'
    )
    returning id into v_intent_id;

    select * into v_intent
    from public.payment_intents
    where id = v_intent_id;
  end if;

  select * into v_profile
  from public.profiles
  where id = (
    select d.auth_user_id from public.developers d where d.id = v_dev
  );

  return jsonb_build_object(
    'intent_id', v_intent.id,
    'campaign_id', p_campaign_id,
    'app_name', v_campaign.app_name,
    'amount_cents', v_intent.amount_cents,
    'currency', v_intent.currency,
    'reference', 'TL-' || upper(substr(replace(p_campaign_id::text, '-', ''), 1, 8)),
    'checkout_url', v_intent.checkout_url,
    'expires_at', v_intent.expires_at,
    'is_test', v_intent.is_test,
    'developer_email', v_profile.email,
    'developer_name', coalesce(v_profile.display_name, '')
  );
end;
$$;

-- Service role only: store the hosted checkout returned by Lemon Squeezy.
create or replace function public.attach_payment_checkout(
  p_intent_id uuid,
  p_checkout_id text,
  p_checkout_url text,
  p_expires_at timestamptz,
  p_is_test boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_intent public.payment_intents%rowtype;
begin
  if length(coalesce(p_checkout_id, '')) not between 1 and 200 then
    raise exception 'The checkout id is invalid.';
  end if;
  if length(coalesce(p_checkout_url, '')) not between 1 and 1000
     or p_checkout_url !~ '^https://[a-z0-9-]+[.]lemonsqueezy[.]com/checkout/[^[:space:]]+$' then
    raise exception 'The checkout link is not a Lemon Squeezy checkout URL.';
  end if;

  select * into v_intent
  from public.payment_intents
  where id = p_intent_id
  for update;

  if not found then
    raise exception 'That checkout no longer exists.';
  end if;
  if v_intent.status <> 'created' then
    return jsonb_build_object(
      'intent_id', v_intent.id,
      'status', v_intent.status,
      'checkout_url', v_intent.checkout_url
    );
  end if;

  update public.payment_intents
  set provider_checkout_id = p_checkout_id,
      checkout_url = p_checkout_url,
      expires_at = coalesce(p_expires_at, expires_at, now() + interval '1 hour'),
      is_test = coalesce(p_is_test, false),
      updated_at = now()
  where id = p_intent_id
  returning * into v_intent;

  return jsonb_build_object(
    'intent_id', v_intent.id,
    'status', v_intent.status,
    'checkout_url', v_intent.checkout_url,
    'expires_at', v_intent.expires_at,
    'is_test', v_intent.is_test
  );
end;
$$;

-- Service role only: the webhook records a paid order. Idempotent per order id.
create or replace function public.record_provider_payment(
  p_intent_id uuid,
  p_order_id text,
  p_subtotal_cents integer,
  p_total_cents integer,
  p_currency text,
  p_is_test boolean,
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_intent     public.payment_intents%rowtype;
  v_campaign   public.campaigns%rowtype;
  v_order_id   text := nullif(btrim(coalesce(p_order_id, '')), '');
  v_reservation jsonb := '{}'::jsonb;
begin
  if v_order_id is null or length(v_order_id) > 100 then
    raise exception 'The order id is invalid.';
  end if;

  select * into v_intent
  from public.payment_intents
  where id = p_intent_id
  for update;

  if not found then
    raise exception 'That checkout no longer exists.';
  end if;

  if v_intent.status = 'paid' or exists (
    select 1 from public.payment_intents pi
    where pi.provider_order_id = v_order_id
      and pi.status = 'paid'
  ) then
    return jsonb_build_object(
      'status', 'already_paid',
      'intent_id', v_intent.id,
      'campaign_id', v_intent.campaign_id
    );
  end if;

  select * into v_campaign
  from public.campaigns
  where id = v_intent.campaign_id
  for update;

  if not found then
    raise exception 'That project no longer exists.';
  end if;

  if coalesce(p_is_test, false) <> v_intent.is_test then
    update public.payment_intents
    set status = 'failed',
        provider_order_id = v_order_id,
        updated_at = now()
    where id = v_intent.id;

    perform public.write_audit(
      'payment.test_mode_mismatch',
      v_campaign.app_name,
      jsonb_build_object(
        'campaign_id', v_intent.campaign_id,
        'order_id', v_order_id,
        'checkout_is_test', v_intent.is_test,
        'order_is_test', coalesce(p_is_test, false)
      )
    );

    return jsonb_build_object(
      'status', 'test_mode_mismatch',
      'intent_id', v_intent.id,
      'campaign_id', v_intent.campaign_id
    );
  end if;

  if upper(coalesce(p_currency, '')) <> v_intent.currency
     or p_subtotal_cents is distinct from v_intent.amount_cents then
    update public.payment_intents
    set status = 'failed',
        provider_order_id = v_order_id,
        provider_subtotal_cents = p_subtotal_cents,
        provider_total_cents = p_total_cents,
        updated_at = now()
    where id = v_intent.id;

    perform public.write_audit(
      'payment.amount_mismatch',
      v_campaign.app_name,
      jsonb_build_object(
        'campaign_id', v_intent.campaign_id,
        'order_id', v_order_id,
        'expected_cents', v_intent.amount_cents,
        'received_subtotal_cents', p_subtotal_cents,
        'currency', p_currency
      )
    );

    return jsonb_build_object(
      'status', 'amount_mismatch',
      'intent_id', v_intent.id,
      'campaign_id', v_intent.campaign_id,
      'expected_cents', v_intent.amount_cents,
      'received_subtotal_cents', p_subtotal_cents
    );
  end if;

  if v_campaign.payment_state <> 'paid' then
    update public.campaigns
    set payment_state = 'paid',
        paid_at = now(),
        payment_reference = coalesce(
          payment_reference,
          'TL-' || upper(substr(replace(v_campaign.id::text, '-', ''), 1, 8))
        ),
        payment_confirmed_by = null,
        payment_paid_via = 'online',
        payment_provider = 'lemonsqueezy',
        payment_provider_ref = v_order_id
    where id = v_campaign.id
    returning * into v_campaign;

    if v_campaign.group_id is null then
      v_reservation := public.reserve_group_identity(v_campaign.id, false);
    end if;
  end if;

  update public.payment_intents
  set status = 'paid',
      paid_at = now(),
      provider_order_id = v_order_id,
      provider_subtotal_cents = p_subtotal_cents,
      provider_total_cents = p_total_cents,
      updated_at = now()
  where id = v_intent.id;

  perform public.write_audit(
    'payment.paid_online',
    v_campaign.app_name,
    jsonb_build_object(
      'campaign_id', v_campaign.id,
      'intent_id', v_intent.id,
      'order_id', v_order_id,
      'amount_cents', v_intent.amount_cents,
      'total_cents', p_total_cents,
      'is_test', coalesce(p_is_test, false),
      'reservation', v_reservation,
      'payload', coalesce(p_payload, '{}'::jsonb)
    )
  );

  return jsonb_build_object(
    'status', 'paid',
    'intent_id', v_intent.id,
    'campaign_id', v_campaign.id,
    'amount_cents', v_intent.amount_cents,
    'is_test', coalesce(p_is_test, false),
    'reservation', v_reservation
  );
end;
$$;

-- Service role only: refunds are recorded, never used to un-pay a project.
create or replace function public.record_provider_refund(
  p_order_id text,
  p_amount_cents integer,
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_order_id text := nullif(btrim(coalesce(p_order_id, '')), '');
  v_intent   public.payment_intents%rowtype;
  v_app      text;
begin
  if v_order_id is null or length(v_order_id) > 100 then
    raise exception 'The order id is invalid.';
  end if;

  select * into v_intent
  from public.payment_intents
  where provider_order_id = v_order_id
  limit 1;

  if not found then
    perform public.write_audit(
      'payment.refund_unknown_order',
      v_order_id,
      jsonb_build_object('order_id', v_order_id, 'amount_cents', p_amount_cents)
    );
    return jsonb_build_object('status', 'unknown_order', 'order_id', v_order_id);
  end if;

  select app_name into v_app
  from public.campaigns
  where id = v_intent.campaign_id;

  perform public.write_audit(
    'payment.refunded',
    coalesce(v_app, v_order_id),
    jsonb_build_object(
      'campaign_id', v_intent.campaign_id,
      'order_id', v_order_id,
      'amount_cents', p_amount_cents,
      'payload', coalesce(p_payload, '{}'::jsonb)
    )
  );

  return jsonb_build_object(
    'status', 'recorded',
    'campaign_id', v_intent.campaign_id,
    'order_id', v_order_id
  );
end;
$$;

-- Service role only: housekeeping for checkouts nobody completed.
create or replace function public.expire_stale_payment_intents()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_count integer;
begin
  update public.payment_intents
  set status = 'expired',
      updated_at = now()
  where status = 'created'
    and created_at < now() - interval '24 hours';

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- Operations fallback stays manual, and is now labelled as such.
create or replace function public.confirm_payment(p_campaign_id uuid, p_reference text default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_admin      uuid := public.require_admin();
  v_reference  text := nullif(btrim(coalesce(p_reference, '')), '');
  v_campaign   public.campaigns%rowtype;
  v_paid_at    timestamptz;
  v_reservation jsonb := '{}'::jsonb;
begin
  if length(coalesce(v_reference, '')) > 120 then
    raise exception 'Keep the payment reference under 120 characters.';
  end if;

  select * into v_campaign from public.campaigns where id = p_campaign_id for update;
  if not found then
    raise exception 'That project no longer exists.';
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
      payment_confirmed_by = v_admin,
      payment_paid_via = 'manual',
      payment_provider = null,
      payment_provider_ref = null
  where id = p_campaign_id
  returning paid_at into v_paid_at;

  update public.payment_intents
  set status = 'expired',
      updated_at = now()
  where campaign_id = p_campaign_id
    and status = 'created';

  if v_campaign.group_id is null then
    v_reservation := public.reserve_group_identity(p_campaign_id, false);
  end if;

  perform public.write_audit(
    'payment.confirmed',
    v_campaign.app_name,
    jsonb_build_object(
      'campaign_id', p_campaign_id,
      'amount_cents', v_campaign.payment_amount_cents,
      'reference', v_reference,
      'paid_via', 'manual',
      'reservation', v_reservation
    )
  );

  return jsonb_build_object(
    'campaign_id', p_campaign_id,
    'payment_state', 'paid',
    'payment_amount_cents', v_campaign.payment_amount_cents,
    'payment_reference', v_reference,
    'payment_paid_via', 'manual',
    'paid_at', v_paid_at
  ) || v_reservation;
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
    'payment_paid_via', c.payment_paid_via,
    'payment_provider', c.payment_provider,
    'payment_provider_ref', c.payment_provider_ref,
    'payment_checkout_url', (
      select pi.checkout_url
      from public.payment_intents pi
      where pi.campaign_id = c.id
        and pi.status = 'created'
      order by pi.created_at desc
      limit 1
    ),
    'payment_intent_expires_at', (
      select pi.expires_at
      from public.payment_intents pi
      where pi.campaign_id = c.id
        and pi.status = 'created'
      order by pi.created_at desc
      limit 1
    ),
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
  v_health public.campaign_health%rowtype;
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

  select * into v_health
  from public.campaign_health
  where campaign_id = p_campaign_id;

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
      'payment_paid_via', v_campaign.payment_paid_via,
      'payment_provider', v_campaign.payment_provider,
      'payment_provider_ref', v_campaign.payment_provider_ref,
      'paid_at', v_campaign.paid_at,
      'group_email', v_group.email,
      'group_name', v_group.name,
      'group_display_name', v_group.display_name,
      'group_state', v_group.state::text,
      'group_provisioned_at', v_group.provisioned_at,
      'group_settings_confirmed_at', v_group.settings_confirmed_at,
      'seats_used', coalesce(v_health.seats_used, 0),
      'seats_free', greatest(15 - v_testers_used, 0),
      'testers_used', v_testers_used,
      'opted_in', coalesce(v_health.opted_in, 0),
      'days_banked', coalesce(v_health.days_banked, 0),
      'meets_requirement', coalesce(v_health.meets_requirement, false),
      'eligible_on', v_health.eligible_on,
      'clock_started_at', v_health.threshold_opt_in_at,
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

revoke execute on function public.prepare_payment_intent(uuid) from public, anon;
grant execute on function public.prepare_payment_intent(uuid) to authenticated;

revoke execute on function public.attach_payment_checkout(uuid, text, text, timestamptz, boolean)
  from public, anon, authenticated;
grant execute on function public.attach_payment_checkout(uuid, text, text, timestamptz, boolean)
  to service_role;

revoke execute on function public.record_provider_payment(uuid, text, integer, integer, text, boolean, jsonb)
  from public, anon, authenticated;
grant execute on function public.record_provider_payment(uuid, text, integer, integer, text, boolean, jsonb)
  to service_role;

revoke execute on function public.record_provider_refund(text, integer, jsonb)
  from public, anon, authenticated;
grant execute on function public.record_provider_refund(text, integer, jsonb)
  to service_role;

revoke execute on function public.expire_stale_payment_intents()
  from public, anon, authenticated;
grant execute on function public.expire_stale_payment_intents()
  to service_role;

notify pgrst, 'reload schema';
