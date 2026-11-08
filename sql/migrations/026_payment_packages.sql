-- 026: payment packages.
-- Admin-defined packages carry the project fee and the tester payout.
-- A developer chooses an active package when creating a project, and the
-- campaign copies both amounts so later package edits cannot rewrite history.

create table if not exists public.payment_packages (
  id               uuid primary key default gen_random_uuid(),
  name             text not null check (length(btrim(name)) between 2 and 80),
  amount_cents     integer not null check (amount_cents between 100 and 1000000),
  tester_fee_cents integer not null check (tester_fee_cents between 1 and 1000000),
  is_active        boolean not null default true,
  created_by       uuid references auth.users (id) on delete set null,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create unique index if not exists payment_packages_name_key
  on public.payment_packages (lower(btrim(name)));

alter table public.campaigns
  add column if not exists payment_package_id uuid
    references public.payment_packages (id) on delete restrict,
  add column if not exists tester_payout_cents integer not null default 50
    check (tester_payout_cents between 1 and 1000000);

insert into public.payment_packages (name, amount_cents, tester_fee_cents)
select 'Standard', 1500, 50
where not exists (
  select 1 from public.payment_packages where lower(btrim(name)) = 'standard'
);

update public.campaigns c
set payment_package_id = pk.id
from public.payment_packages pk
where c.payment_package_id is null
  and lower(btrim(pk.name)) = 'standard';

drop function if exists public.create_campaign(text, text);

create or replace function public.create_campaign(
  p_app_name text,
  p_package_name text,
  p_payment_package_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_dev     uuid := public.require_developer();
  v_name    text := trim(coalesce(p_app_name, ''));
  v_package text := trim(coalesce(p_package_name, ''));
  v_pricing public.payment_packages%rowtype;
  v_id      uuid;
begin
  if length(v_name) < 2 or length(v_name) > 120 then
    raise exception 'App name must be between 2 and 120 characters.';
  end if;

  if v_package !~ '^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$' then
    raise exception 'Package name must look like com.company.app.';
  end if;

  select * into v_pricing from public.payment_packages
  where id = p_payment_package_id and is_active;

  if not found then
    raise exception 'Choose an active payment package.';
  end if;

  if exists (
    select 1 from public.campaigns
    where developer_id = v_dev and lower(package_name) = lower(v_package)
  ) then
    raise exception 'You already have a project for that package.';
  end if;

  insert into public.campaigns (
    developer_id,
    payment_package_id,
    app_name,
    package_name,
    payment_amount_cents,
    tester_payout_cents
  )
  values (
    v_dev,
    v_pricing.id,
    v_name,
    v_package,
    v_pricing.amount_cents,
    v_pricing.tester_fee_cents
  )
  returning id into v_id;

  perform public.write_audit(
    'campaign.created',
    v_name,
    jsonb_build_object(
      'campaign_id', v_id,
      'payment_package_id', v_pricing.id,
      'payment_package', v_pricing.name,
      'amount_cents', v_pricing.amount_cents,
      'tester_fee_cents', v_pricing.tester_fee_cents
    )
  );
  return public.developer_campaign_json(v_id);
end;
$$;

create or replace function public.save_payment_package(
  p_id uuid,
  p_name text,
  p_amount_cents integer,
  p_tester_fee_cents integer,
  p_is_active boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_admin uuid := public.require_admin();
  v_name  text := btrim(coalesce(p_name, ''));
  v_row   public.payment_packages%rowtype;
begin
  if length(v_name) < 2 or length(v_name) > 80 then
    raise exception 'Package name must be between 2 and 80 characters.';
  end if;

  if p_amount_cents is null or p_amount_cents < 100 or p_amount_cents > 1000000 then
    raise exception 'Project fee must be between $1.00 and $10,000.00.';
  end if;

  if p_tester_fee_cents is null or p_tester_fee_cents < 1 or p_tester_fee_cents > 1000000 then
    raise exception 'Tester fee must be between $0.01 and $10,000.00.';
  end if;

  if p_id is null then
    insert into public.payment_packages (name, amount_cents, tester_fee_cents, is_active, created_by)
    values (v_name, p_amount_cents, p_tester_fee_cents, coalesce(p_is_active, true), v_admin)
    returning * into v_row;
  else
    select * into v_row from public.payment_packages where id = p_id for update;
    if not found then
      raise exception 'That payment package no longer exists.';
    end if;

    if not coalesce(p_is_active, true)
       and v_row.is_active
       and not exists (
         select 1 from public.payment_packages
         where id <> v_row.id and is_active
       ) then
      raise exception 'Keep at least one active payment package.';
    end if;

    update public.payment_packages
    set name = v_name,
        amount_cents = p_amount_cents,
        tester_fee_cents = p_tester_fee_cents,
        is_active = coalesce(p_is_active, true),
        updated_at = now()
    where id = p_id
    returning * into v_row;
  end if;

  perform public.write_audit(
    'payment_package.saved',
    v_row.name,
    jsonb_build_object(
      'payment_package_id', v_row.id,
      'amount_cents', v_row.amount_cents,
      'tester_fee_cents', v_row.tester_fee_cents,
      'is_active', v_row.is_active
    )
  );

  return jsonb_build_object(
    'id', v_row.id,
    'name', v_row.name,
    'amount_cents', v_row.amount_cents,
    'tester_fee_cents', v_row.tester_fee_cents,
    'is_active', v_row.is_active
  );
exception
  when unique_violation then
    raise exception 'A payment package with that name already exists.';
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
        dropped_at = null,
        payout_amount_cents = v_campaign.tester_payout_cents
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

    insert into public.campaign_seats (
      campaign_id,
      tester_id,
      seat_number,
      state,
      joined_at,
      payout_amount_cents
    )
    values (
      p_campaign_id,
      v_tester,
      v_seat_number,
      'joined',
      now(),
      v_campaign.tester_payout_cents
    )
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

-- Rerunning this migration must not rename the wrapper onto itself.
do $$
begin
  if to_regprocedure('public.admin_dashboard_base()') is null
     and to_regprocedure('public.admin_dashboard()') is not null then
    alter function public.admin_dashboard() rename to admin_dashboard_base;
  end if;
end $$;

create or replace function public.admin_dashboard()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_body jsonb := public.admin_dashboard_base();
begin
  return jsonb_set(
    v_body,
    '{packages}',
    coalesce((
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
    ), '[]'::jsonb)
  );
end;
$$;

alter table public.payment_packages enable row level security;

revoke all on public.payment_packages from public, anon, authenticated;
revoke execute on function public.admin_dashboard_base() from public, anon, authenticated;
revoke execute on function public.create_campaign(text, text, uuid) from public, anon;
revoke execute on function public.save_payment_package(uuid, text, integer, integer, boolean)
  from public, anon;
revoke execute on function public.list_payment_packages() from public, anon;

grant execute on function public.create_campaign(text, text, uuid) to authenticated;
grant execute on function public.save_payment_package(uuid, text, integer, integer, boolean)
  to authenticated;
grant execute on function public.list_payment_packages() to authenticated;
grant execute on function public.admin_dashboard() to authenticated;

notify pgrst, 'reload schema';
