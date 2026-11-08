-- TesterLoop greenfield schema. Run first against a fresh Supabase project.

create extension if not exists "pgcrypto";

create type public.app_role as enum ('developer', 'tester', 'admin');
create type public.campaign_state as enum ('draft', 'pending', 'awaiting_link', 'live', 'at_risk', 'passed', 'cancelled');
create type public.seat_state as enum ('joined', 'opted_in', 'dropped');
create type public.group_state as enum ('manual', 'orphaned', 'revoked');
create type public.report_severity as enum ('blocker', 'major', 'minor', 'cosmetic');
create type public.report_status as enum ('open', 'triaged', 'fixed', 'closed');
create type public.payment_state as enum ('unpaid', 'paid');

create table public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  role         public.app_role not null,
  display_name text not null,
  email        text not null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create table public.admins (
  auth_user_id uuid primary key references auth.users (id) on delete cascade,
  note         text,
  created_at   timestamptz not null default now()
);

create table public.developers (
  id            uuid primary key default gen_random_uuid(),
  auth_user_id  uuid unique references auth.users (id) on delete set null,
  company_name  text not null check (length(trim(company_name)) between 2 and 120),
  contact_email text not null,
  google_email  text not null,
  group_sequence_counter integer not null default 0
    check (group_sequence_counter between 0 and 999),
  created_at    timestamptz not null default now()
);

create table public.testers (
  id           uuid primary key default gen_random_uuid(),
  auth_user_id uuid unique references auth.users (id) on delete set null,
  display_name text not null check (length(trim(display_name)) between 2 and 120),
  google_email text not null unique,
  devices      text[] not null default '{}',
  mobile_device_name text check (
    mobile_device_name is null
    or length(btrim(mobile_device_name)) between 1 and 120
  ),
  mobile_device_seen_at timestamptz,
  region       text,
  reliability  numeric(4, 2) not null default 0 check (reliability between 0 and 100),
  is_active    boolean not null default true,
  created_at   timestamptz not null default now()
);

create table public.google_groups (
  id             uuid primary key default gen_random_uuid(),
  developer_id   uuid not null references public.developers (id) on delete cascade,
  email          text not null unique check (email = lower(email)),
  name           text not null check (
    name = lower(name)
    and name ~ '^[a-z0-9]([a-z0-9._-]{0,198}[a-z0-9])?$'
  ),
  display_name   text not null
    check (length(btrim(display_name)) between 1 and 73),
  state          public.group_state not null default 'manual',
  provisioned_at timestamptz,
  last_checked_at timestamptz,
  settings_confirmed_at timestamptz,
  settings_confirmed_by uuid references auth.users (id) on delete set null,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create table public.payment_packages (
  id               uuid primary key default gen_random_uuid(),
  name             text not null check (length(btrim(name)) between 2 and 80),
  amount_cents     integer not null check (amount_cents between 100 and 1000000),
  tester_fee_cents integer not null check (tester_fee_cents between 1 and 1000000),
  is_active        boolean not null default true,
  created_by       uuid references auth.users (id) on delete set null,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create unique index payment_packages_name_key
  on public.payment_packages (lower(btrim(name)));

create table public.campaigns (
  id               uuid primary key default gen_random_uuid(),
  developer_id     uuid not null references public.developers (id) on delete cascade,
  group_id         uuid unique references public.google_groups (id) on delete restrict,
  payment_package_id uuid references public.payment_packages (id) on delete restrict,
  app_name         text not null check (length(trim(app_name)) between 2 and 120),
  package_name     text not null,
  play_opt_in_url  text,
  state            public.campaign_state not null default 'pending',
  required_testers smallint not null default 12 check (required_testers between 1 and 15),
  payment_state    public.payment_state not null default 'unpaid',
  payment_amount_cents integer not null default 1500
    check (payment_amount_cents between 100 and 1000000),
  tester_payout_cents integer not null default 50
    check (tester_payout_cents between 1 and 1000000),
  payment_reference text,
  paid_at          timestamptz,
  payment_confirmed_by uuid references auth.users (id) on delete set null,
  payment_paid_via text check (
    payment_paid_via is null or payment_paid_via in ('manual', 'online')
  ),
  payment_provider text check (
    payment_provider is null or payment_provider in ('lemonsqueezy')
  ),
  payment_provider_ref text check (
    payment_provider_ref is null or length(payment_provider_ref) <= 100
  ),
  group_sequence   smallint check (group_sequence between 1 and 999),
  reserved_group_email text check (
    reserved_group_email is null
    or (
      reserved_group_email = lower(reserved_group_email)
      and reserved_group_email ~ '^[a-z0-9][a-z0-9._-]{0,62}@googlegroups[.]com$'
    )
  ),
  reserved_group_url_name text check (
    reserved_group_url_name is null
    or reserved_group_url_name ~ '^[a-z0-9]([a-z0-9._-]{0,198}[a-z0-9])?$'
  ),
  reserved_group_display_name text check (
    reserved_group_display_name is null
    or length(btrim(reserved_group_display_name)) between 1 and 73
  ),
  group_identity_reserved_at timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  started_at       timestamptz,
  first_opt_in_at  timestamptz,
  passed_at        timestamptz,
  cancelled_at     timestamptz,
  unique (developer_id, package_name),
  constraint campaigns_group_identity_reservation_check check (
    (
      group_sequence is null
      and reserved_group_email is null
      and reserved_group_url_name is null
      and reserved_group_display_name is null
      and group_identity_reserved_at is null
    )
    or (
      group_sequence is not null
      and reserved_group_email is not null
      and reserved_group_url_name is not null
      and reserved_group_display_name is not null
      and group_identity_reserved_at is not null
    )
  ),
  check (state = 'pending' or group_id is not null),
  check (state not in ('live', 'at_risk', 'passed') or play_opt_in_url is not null),
  check (state <> 'passed' or passed_at is not null),
  check (payment_state <> 'paid' or paid_at is not null)
);

create table public.campaign_seats (
  id           uuid primary key default gen_random_uuid(),
  campaign_id  uuid not null references public.campaigns (id) on delete cascade,
  tester_id    uuid not null references public.testers (id) on delete cascade,
  seat_number  smallint not null check (seat_number between 1 and 15),
  state        public.seat_state not null default 'joined',
  joined_at    timestamptz,
  opted_in_at  timestamptz,
  opt_in_verified_at timestamptz,
  opt_in_verification text
    check (opt_in_verification is null or opt_in_verification = 'google_group'),
  dropped_at   timestamptz,
  payout_amount_cents integer not null default 50
    check (payout_amount_cents between 1 and 1000000),
  payout_state public.payment_state not null default 'unpaid',
  payout_reference text,
  paid_at      timestamptz,
  paid_by      uuid references auth.users (id) on delete set null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (campaign_id, tester_id),
  check (payout_state <> 'paid' or paid_at is not null)
);

create unique index campaign_seats_active_seat
  on public.campaign_seats (campaign_id, seat_number)
  where state in ('joined', 'opted_in');

create unique index campaigns_developer_group_sequence
  on public.campaigns (developer_id, group_sequence)
  where group_sequence is not null;

create unique index campaigns_reserved_group_email_key
  on public.campaigns (reserved_group_email)
  where reserved_group_email is not null;

create unique index campaigns_reserved_group_url_name_key
  on public.campaigns (reserved_group_url_name)
  where reserved_group_url_name is not null;

create index campaign_seats_active_tester
  on public.campaign_seats (tester_id)
  where state in ('joined', 'opted_in');

create table public.payment_intents (
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

create unique index payment_intents_order_key
  on public.payment_intents (provider_order_id)
  where provider_order_id is not null;

create unique index payment_intents_open_campaign_key
  on public.payment_intents (campaign_id)
  where status = 'created';

create index payment_intents_campaign_idx
  on public.payment_intents (campaign_id, created_at desc);

create table public.tester_app_install_daily (
  id           uuid primary key default gen_random_uuid(),
  tester_id    uuid not null references public.testers (id) on delete cascade,
  campaign_id  uuid not null references public.campaigns (id) on delete cascade,
  package_name text not null,
  status_date  date not null,
  installed    boolean not null,
  source       text not null default 'mobile_daily'
    check (source in ('mobile_daily', 'mobile_manual', 'desktop')),
  checked_at   timestamptz not null default now(),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (tester_id, campaign_id, status_date)
);

create index tester_app_install_daily_campaign_idx
  on public.tester_app_install_daily (campaign_id, status_date);

create table public.bug_reports (
  id           uuid primary key default gen_random_uuid(),
  campaign_id  uuid not null references public.campaigns (id) on delete cascade,
  tester_id    uuid not null references public.testers (id) on delete cascade,
  severity     public.report_severity not null,
  title        text not null check (length(trim(title)) >= 4),
  body         text not null check (length(trim(body)) >= 1),
  build_label  text,
  device       text,
  evidence_url text,
  usage_snapshot   jsonb not null default '{}'::jsonb,
  usage_captured_at timestamptz,
  install_history  jsonb not null default '[]'::jsonb,
  install_history_captured_at timestamptz,
  install_window_start date,
  install_window_end date,
  status       public.report_status not null default 'open',
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create table public.audit_log (
  id          bigint generated always as identity primary key,
  actor_id    uuid references auth.users (id) on delete set null,
  actor_role  text not null,
  actor_label text not null,
  action      text not null,
  target      text,
  detail      jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now()
);

create index campaigns_state_idx on public.campaigns (state);
create index campaigns_developer_idx on public.campaigns (developer_id);
create unique index campaigns_developer_package_ci
  on public.campaigns (developer_id, lower(package_name));
create unique index testers_google_email_ci
  on public.testers (lower(google_email));
create index google_groups_developer_idx on public.google_groups (developer_id);
create index bug_reports_campaign_idx on public.bug_reports (campaign_id, created_at desc);
create index audit_log_created_idx on public.audit_log (created_at desc);

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_touch before update on public.profiles
  for each row execute function public.touch_updated_at();
create trigger google_groups_touch before update on public.google_groups
  for each row execute function public.touch_updated_at();
create trigger campaigns_touch before update on public.campaigns
  for each row execute function public.touch_updated_at();
create trigger campaign_seats_touch before update on public.campaign_seats
  for each row execute function public.touch_updated_at();
create trigger bug_reports_touch before update on public.bug_reports
  for each row execute function public.touch_updated_at();
create trigger tester_app_install_daily_touch before update on public.tester_app_install_daily
  for each row execute function public.touch_updated_at();

-- The 12th-oldest active opt-in is the threshold: when it is 14 days old,
-- twelve testers have each been opted in for at least fourteen days.
create or replace view public.campaign_health
with (security_invoker = true) as
with active as (
  select
    s.campaign_id,
    count(*) filter (where s.state in ('joined', 'opted_in')) as seats_used,
    count(*) filter (where s.state = 'opted_in') as opted_in,
    array_agg(s.opted_in_at order by s.opted_in_at)
      filter (where s.state = 'opted_in' and s.opted_in_at is not null) as opt_ins
  from public.campaign_seats s
  group by s.campaign_id
)
select
  c.id as campaign_id,
  c.required_testers,
  coalesce(a.seats_used, 0)::int as seats_used,
  coalesce(a.opted_in, 0)::int as opted_in,
  case
    when coalesce(a.opted_in, 0) >= c.required_testers
    then a.opt_ins[c.required_testers]
    else null
  end as threshold_opt_in_at,
  case
    when coalesce(a.opted_in, 0) >= c.required_testers
     and a.opt_ins[c.required_testers] <= now() - interval '14 days'
    then true
    else false
  end as meets_requirement,
  case
    when coalesce(a.opted_in, 0) >= c.required_testers
     and a.opt_ins[c.required_testers] is not null
    then floor(extract(epoch from (now() - a.opt_ins[c.required_testers])) / 86400)::int
    else 0
  end as days_banked,
  case
    when coalesce(a.opted_in, 0) >= c.required_testers
    then a.opt_ins[c.required_testers] + interval '14 days'
    else null
  end as eligible_on
from public.campaigns c
left join active a on a.campaign_id = c.id;
