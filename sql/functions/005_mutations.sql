-- Campaign lifecycle mutations. Each one validates the signed-in role and
-- writes an audit row in the same transaction.

create or replace function public.write_audit(p_action text, p_target text, p_detail jsonb default '{}'::jsonb)
returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  insert into public.audit_log (actor_id, actor_role, actor_label, action, target, detail)
  select
    auth.uid(),
    coalesce(p.role::text, 'system'),
    coalesce(p.display_name, 'Unknown'),
    p_action,
    p_target,
    coalesce(p_detail, '{}'::jsonb)
  from (select 1) x
  left join public.profiles p on p.id = auth.uid();
$$;

create or replace function public.refresh_campaign_state(p_campaign_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_state    public.campaign_state;
  v_started  timestamptz;
  v_required smallint;
  v_opted    integer;
  v_meets    boolean;
begin
  select c.state, c.started_at, c.required_testers,
         coalesce(h.opted_in, 0), coalesce(h.meets_requirement, false)
  into v_state, v_started, v_required, v_opted, v_meets
  from public.campaigns c
  left join public.campaign_health h on h.campaign_id = c.id
  where c.id = p_campaign_id;

  if not found or v_state not in ('live', 'at_risk') then
    return;
  end if;

  if v_meets then
    update public.campaigns
    set state = 'passed', passed_at = coalesce(passed_at, now())
    where id = p_campaign_id;
  elsif v_opted < v_required
        and v_started is not null
        and v_started <= now() - interval '7 days' then
    update public.campaigns set state = 'at_risk' where id = p_campaign_id;
  elsif v_state = 'at_risk' and v_opted >= v_required then
    update public.campaigns set state = 'live' where id = p_campaign_id;
  end if;
end;
$$;

create or replace function public.refresh_campaign_states()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row record;
begin
  if public.current_role_name() is null then
    raise exception 'Sign in with a TesterLoop account first.';
  end if;

  for v_row in
    select id from public.campaigns where state in ('live', 'at_risk')
  loop
    perform public.refresh_campaign_state(v_row.id);
  end loop;

  return jsonb_build_object('ok', true);
end;
$$;

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

create or replace function public.delete_payment_package(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row  public.payment_packages%rowtype;
  v_used integer;
begin
  perform public.require_admin();

  if p_id is null then
    raise exception 'Choose a payment package to delete.';
  end if;

  select * into v_row from public.payment_packages where id = p_id for update;
  if not found then
    raise exception 'That payment package no longer exists.';
  end if;

  select count(*) into v_used
  from public.campaigns
  where payment_package_id = p_id;

  if v_used > 0 then
    raise exception 'This package is used by % project(s). Deactivate it instead so project history stays intact.', v_used;
  end if;

  if v_row.is_active and not exists (
    select 1 from public.payment_packages
    where id <> p_id and is_active
  ) then
    raise exception 'Keep at least one active payment package.';
  end if;

  delete from public.payment_packages where id = p_id;

  perform public.write_audit(
    'payment_package.deleted',
    v_row.name,
    jsonb_build_object(
      'payment_package_id', v_row.id,
      'amount_cents', v_row.amount_cents,
      'tester_fee_cents', v_row.tester_fee_cents,
      'is_active', v_row.is_active
    )
  );

  return jsonb_build_object('deleted', true, 'id', v_row.id, 'name', v_row.name);
end;
$$;

create or replace function public.reserve_group_identity(
  p_campaign_id uuid,
  p_force_new boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_campaign    public.campaigns%rowtype;
  v_developer   public.developers%rowtype;
  v_app_token   text;
  v_company_token text;
  v_sequence    integer;
  v_suffix      text;
  v_local       text;
  v_email       text;
  v_display_base text;
  v_display     text;
  v_reserved_at timestamptz := now();
  v_old_email   text;
  v_old_name    text;
  v_old_display text;
begin
  select * into v_campaign from public.campaigns where id = p_campaign_id for update;
  if not found then
    raise exception 'That project no longer exists.';
  end if;

  select * into v_developer from public.developers
  where id = v_campaign.developer_id
  for update;

  if v_campaign.group_id is not null then
    raise exception 'This project already has an attached group.';
  end if;
  if v_campaign.state not in ('pending', 'awaiting_link') then
    raise exception 'Only a project waiting for a group can reserve a group identity.';
  end if;
  if v_campaign.payment_state <> 'paid' then
    raise exception 'Confirm the project fee before reserving a group identity.';
  end if;

  if v_campaign.reserved_group_email is not null and not p_force_new then
    return jsonb_build_object(
      'campaign_id', v_campaign.id,
      'group_sequence', v_campaign.group_sequence,
      'reserved_group_email', v_campaign.reserved_group_email,
      'reserved_group_url_name', v_campaign.reserved_group_url_name,
      'reserved_group_display_name', v_campaign.reserved_group_display_name,
      'group_identity_reserved_at', v_campaign.group_identity_reserved_at
    );
  end if;

  v_old_email := v_campaign.reserved_group_email;
  v_old_name := v_campaign.reserved_group_url_name;
  v_old_display := v_campaign.reserved_group_display_name;

  v_app_token := btrim(
    left(btrim(regexp_replace(lower(v_campaign.app_name), '[^a-z0-9]+', '-', 'g'), '-'), 23),
    '-'
  );
  if v_app_token = '' then
    v_app_token := 'app';
  end if;

  v_company_token := btrim(
    left(btrim(regexp_replace(lower(v_developer.company_name), '[^a-z0-9]+', '-', 'g'), '-'), 23),
    '-'
  );
  if v_company_token = '' then
    v_company_token := 'company';
  end if;

  v_sequence := greatest(
    v_developer.group_sequence_counter,
    coalesce((
      select max(c.group_sequence)
      from public.campaigns c
      where c.developer_id = v_campaign.developer_id
    ), 0)
  );

  loop
    v_sequence := v_sequence + 1;
    if v_sequence > 999 then
      raise exception 'This developer has used every group number. Contact support.';
    end if;

    v_suffix := lpad(v_sequence::text, 3, '0');
    v_local := v_app_token || '_' || v_company_token || '_testteam_' || v_suffix;
    v_email := v_local || '@googlegroups.com';

    v_display_base := btrim(regexp_replace(
      v_campaign.app_name || ' ' || v_developer.company_name,
      '\s+', ' ', 'g'
    ));
    if length(v_display_base) > 73 - length(v_suffix) - 1 then
      v_display_base := btrim(left(v_display_base, 73 - length(v_suffix) - 1));
    end if;
    v_display := v_display_base || ' ' || v_suffix;

    exit when not exists (
      select 1 from public.google_groups g
      where g.email = v_email or g.name = v_local
    ) and not exists (
      select 1 from public.campaigns c
      where c.id <> p_campaign_id
        and (c.reserved_group_email = v_email or c.reserved_group_url_name = v_local)
    );
  end loop;

  update public.developers
  set group_sequence_counter = v_sequence
  where id = v_developer.id;

  update public.campaigns
  set group_sequence = v_sequence,
      reserved_group_email = v_email,
      reserved_group_url_name = v_local,
      reserved_group_display_name = v_display,
      group_identity_reserved_at = v_reserved_at
  where id = p_campaign_id;

  perform public.write_audit(
    case when v_old_email is null then 'group.identity_reserved' else 'group.identity_rotated' end,
    v_campaign.app_name,
    jsonb_build_object(
      'campaign_id', p_campaign_id,
      'group_sequence', v_sequence,
      'reserved_group_email', v_email,
      'reserved_group_url_name', v_local,
      'reserved_group_display_name', v_display,
      'previous_group_email', v_old_email,
      'previous_group_url_name', v_old_name,
      'previous_group_display_name', v_old_display
    )
  );

  return jsonb_build_object(
    'campaign_id', p_campaign_id,
    'group_sequence', v_sequence,
    'reserved_group_email', v_email,
    'reserved_group_url_name', v_local,
    'reserved_group_display_name', v_display,
    'group_identity_reserved_at', v_reserved_at
  );
end;
$$;

create or replace function public.rotate_group_identity(p_campaign_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_campaign public.campaigns%rowtype;
begin
  perform public.require_admin();

  select * into v_campaign from public.campaigns where id = p_campaign_id for update;
  if not found then
    raise exception 'That project no longer exists.';
  end if;
  if v_campaign.group_id is not null then
    raise exception 'The group is already attached, so its identity cannot be changed.';
  end if;
  if v_campaign.payment_state <> 'paid' then
    raise exception 'Confirm the project fee before issuing a new group number.';
  end if;
  if v_campaign.state not in ('pending', 'awaiting_link') then
    raise exception 'This project is not waiting for a group.';
  end if;

  return public.reserve_group_identity(p_campaign_id, true);
end;
$$;

create or replace function public.attach_group(
  p_campaign_id uuid,
  p_group_email text,
  p_group_name text,
  p_group_display_name text,
  p_settings_confirmed boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_admin    uuid := public.require_admin();
  v_email    text := lower(trim(coalesce(p_group_email, '')));
  v_name     text := lower(trim(coalesce(p_group_name, '')));
  v_display  text := btrim(coalesce(p_group_display_name, ''));
  v_campaign public.campaigns%rowtype;
  v_group    public.google_groups%rowtype;
begin
  if v_email !~ '^[a-z0-9][a-z0-9._-]{0,62}@googlegroups[.]com$' then
    raise exception 'Use the reserved @googlegroups.com address exactly.';
  end if;
  if v_name !~ '^[a-z0-9]([a-z0-9._-]{0,198}[a-z0-9])?$' then
    raise exception 'Enter the Google Groups URL name (letters, numbers, dots, underscores, hyphens).';
  end if;
  if length(v_display) < 1 or length(v_display) > 73 then
    raise exception 'The group display name must be between 1 and 73 characters.';
  end if;
  if not coalesce(p_settings_confirmed, false) then
    raise exception 'Confirm all five Google Group settings before attaching the group.';
  end if;

  select * into v_campaign from public.campaigns where id = p_campaign_id for update;
  if not found then
    raise exception 'That project no longer exists.';
  end if;
  if v_campaign.group_id is not null or v_campaign.state not in ('pending', 'awaiting_link') then
    raise exception 'This project already has a group or is no longer waiting for one.';
  end if;
  if v_campaign.payment_state <> 'paid' then
    raise exception 'Confirm the project fee before attaching the group.';
  end if;
  if v_campaign.reserved_group_email is null
     or v_campaign.reserved_group_display_name is null
     or v_campaign.reserved_group_url_name is null then
    raise exception 'This project has no reserved group identity. Record the project fee first.';
  end if;
  if v_email <> v_campaign.reserved_group_email then
    raise exception 'Use the reserved group address exactly: %', v_campaign.reserved_group_email;
  end if;
  if v_display <> v_campaign.reserved_group_display_name then
    raise exception 'Use the reserved display name exactly: %', v_campaign.reserved_group_display_name;
  end if;
  if exists (select 1 from public.google_groups g where g.email = v_email) then
    raise exception 'That group address is already attached to another project.';
  end if;
  if exists (select 1 from public.google_groups g where g.name = v_name) then
    raise exception 'That group URL name is already used by another project.';
  end if;

  insert into public.google_groups (
    developer_id,
    email,
    name,
    display_name,
    state,
    provisioned_at,
    settings_confirmed_at,
    settings_confirmed_by
  )
  values (
    v_campaign.developer_id,
    v_email,
    v_name,
    v_display,
    'manual',
    now(),
    now(),
    v_admin
  )
  returning * into v_group;

  update public.campaigns
  set group_id = v_group.id, state = 'awaiting_link'
  where id = p_campaign_id;

  perform public.write_audit(
    'group.settings_confirmed',
    v_email,
    jsonb_build_object(
      'campaign_id', p_campaign_id,
      'admin_id', v_admin,
      'display_name', v_display,
      'visibility', 'anyone_on_web',
      'join', 'anyone_on_web',
      'modify_details', 'group_managers',
      'view_conversations', 'group_managers',
      'view_members', 'group_owners'
    )
  );

  perform public.write_audit(
    'group.attached',
    v_email,
    jsonb_build_object(
      'campaign_id', p_campaign_id,
      'admin_id', v_admin,
      'group_name', v_group.name,
      'display_name', v_group.display_name,
      'settings_confirmed', true
    )
  );

  return jsonb_build_object(
    'id', v_group.id,
    'email', v_group.email,
    'name', v_group.name,
    'display_name', v_group.display_name,
    'state', v_group.state::text,
    'provisioned_at', v_group.provisioned_at,
    'settings_confirmed_at', v_group.settings_confirmed_at
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

-- Temporary free-access activation. A developer can start a project without the
-- $15 fee while payment is disabled. The project is marked paid with amount zero,
-- reserves the group identity and can continue to group attachment and the Play
-- link. The change is audited so a later manual review can find free projects.
create or replace function public.claim_free_access(p_campaign_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_developer   uuid := public.require_developer();
  v_campaign    public.campaigns%rowtype;
  v_paid_at     timestamptz;
  v_reservation jsonb := '{}'::jsonb;
begin
  select * into v_campaign
  from public.campaigns
  where id = p_campaign_id
  for update;

  if not found or v_campaign.developer_id <> v_developer then
    raise exception 'That project could not be found.';
  end if;
  if v_campaign.state not in ('pending', 'awaiting_link') then
    raise exception 'This project is not waiting for activation.';
  end if;
  if v_campaign.payment_state = 'paid' then
    raise exception 'This project is already active.';
  end if;

  update public.campaigns
  set payment_state = 'paid',
      paid_at = now(),
      payment_amount_cents = 0,
      payment_reference = null,
      payment_confirmed_by = null,
      payment_paid_via = 'free',
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
    'payment.free_access',
    v_campaign.app_name,
    jsonb_build_object(
      'campaign_id', p_campaign_id,
      'original_amount_cents', v_campaign.payment_amount_cents,
      'reservation', v_reservation
    )
  );

  return jsonb_build_object(
    'campaign_id', p_campaign_id,
    'payment_state', 'paid',
    'payment_amount_cents', 0,
    'payment_paid_via', 'free',
    'paid_at', v_paid_at
  );
end;
$$;

-- Online payment intents. The developer opens a hosted Lemon Squeezy checkout;
-- only the webhook (service_role) may mark the fee paid. The amount always comes
-- from the campaign, never from the client.
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
  if exists (
    select 1 from public.campaign_seats s
    where s.campaign_id = p_campaign_id
  ) then
    raise exception 'The closed-test link is locked because testers have already joined this project.';
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

create or replace function public.delete_campaign(p_campaign_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_dev      uuid := public.require_developer();
  v_campaign public.campaigns%rowtype;
  v_app      text;
  v_testers  integer;
  v_paid     integer;
begin
  select * into v_campaign from public.campaigns where id = p_campaign_id for update;
  if not found or v_campaign.developer_id <> v_dev then
    raise exception 'That project could not be found.';
  end if;

  if v_campaign.first_opt_in_at is not null
     and v_campaign.state <> 'passed'
     and now() < v_campaign.first_opt_in_at + interval '14 days' then
    raise exception 'This project cannot be edited or deleted until 14 days after the first confirmed opt-in (%s).',
      to_char(v_campaign.first_opt_in_at + interval '14 days', 'DD Mon YYYY');
  end if;

  if exists (
    select 1 from public.campaign_seats
    where campaign_id = p_campaign_id and payout_state = 'paid'
  ) then
    raise exception 'This project has recorded tester payouts and cannot be deleted.';
  end if;

  v_app := v_campaign.app_name;
  select count(*) into v_testers
  from public.campaign_seats where campaign_id = p_campaign_id;
  select count(*) into v_paid
  from public.campaign_seats
  where campaign_id = p_campaign_id and payout_state = 'paid';

  delete from public.campaigns where id = p_campaign_id;

  perform public.write_audit(
    'campaign.deleted',
    v_app,
    jsonb_build_object(
      'campaign_id', p_campaign_id,
      'testers_used', v_testers,
      'paid_payouts', v_paid
    )
  );

  return jsonb_build_object('id', p_campaign_id, 'deleted', true);
end;
$$;

create or replace function public.set_report_status(p_report_id uuid, p_status text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_dev    uuid := public.current_developer_id();
  v_status public.report_status;
  v_report public.bug_reports%rowtype;
begin
  if p_status not in ('open', 'triaged', 'fixed', 'closed') then
    raise exception 'Unknown report status.';
  end if;
  v_status := p_status::public.report_status;

  select * into v_report from public.bug_reports where id = p_report_id for update;
  if not found then
    raise exception 'That report no longer exists.';
  end if;

  if not public.is_admin() and not exists (
    select 1 from public.campaigns c
    where c.id = v_report.campaign_id and c.developer_id = v_dev
  ) then
    raise exception 'That report belongs to another developer.';
  end if;

  update public.bug_reports
  set status = v_status
  where id = p_report_id;

  perform public.write_audit(
    'report.status_changed',
    v_report.title,
    jsonb_build_object('report_id', p_report_id, 'status', p_status)
  );

  return jsonb_build_object('id', p_report_id, 'status', p_status);
end;
$$;

create or replace function public.update_admin_profile(p_display_name text, p_note text default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_admin uuid := public.require_admin();
  v_name  text := btrim(coalesce(p_display_name, ''));
  v_note  text := nullif(btrim(coalesce(p_note, '')), '');
  v_email text;
begin
  if length(v_name) < 2 or length(v_name) > 120 then
    raise exception 'Display name must be between 2 and 120 characters.';
  end if;

  if length(coalesce(v_note, '')) > 500 then
    raise exception 'Keep the admin note under 500 characters.';
  end if;

  update public.profiles
  set display_name = v_name
  where id = v_admin
  returning email into v_email;

  if not found then
    raise exception 'Admin profile not found.';
  end if;

  update public.admins
  set note = v_note
  where auth_user_id = v_admin;

  if not found then
    insert into public.admins (auth_user_id, note) values (v_admin, v_note);
  end if;

  perform public.write_audit(
    'admin.profile_updated',
    'admin',
    jsonb_build_object('admin_id', v_admin)
  );

  return jsonb_build_object(
    'display_name', v_name,
    'email', v_email,
    'note', v_note
  );
end;
$$;

create or replace function public.update_developer_profile(
  p_display_name text,
  p_company_name text,
  p_contact_email text,
  p_google_email text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_dev     uuid := public.require_developer();
  v_name    text := btrim(coalesce(p_display_name, ''));
  v_company text := btrim(coalesce(p_company_name, ''));
  v_contact text := lower(btrim(coalesce(p_contact_email, '')));
  v_google  text := lower(btrim(coalesce(p_google_email, '')));
  v_email   text;
begin
  if length(v_name) < 2 or length(v_name) > 120 then
    raise exception 'Display name must be between 2 and 120 characters.';
  end if;

  if length(v_company) < 2 or length(v_company) > 120 then
    raise exception 'Company name must be between 2 and 120 characters.';
  end if;

  if v_contact !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Enter a valid contact email address.';
  end if;

  if v_google !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Enter a valid Google account email address.';
  end if;

  update public.profiles
  set display_name = v_name
  where id = (select auth_user_id from public.developers where id = v_dev)
  returning email into v_email;

  if v_email is null then
    raise exception 'Developer profile not found.';
  end if;

  update public.developers
  set company_name = v_company,
      contact_email = v_contact,
      google_email = v_google
  where id = v_dev;

  perform public.write_audit(
    'developer.profile_updated',
    v_dev::text,
    jsonb_build_object('company_name', v_company)
  );

  return jsonb_build_object(
    'display_name', v_name,
    'company_name', v_company,
    'contact_email', v_contact,
    'google_email', v_google
  );
end;
$$;

create or replace function public.update_tester_profile(
  p_display_name text,
  p_google_email text,
  p_region text default null,
  p_devices text[] default '{}'
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_tester  uuid := public.require_tester();
  v_name    text := btrim(coalesce(p_display_name, ''));
  v_google  text := lower(btrim(coalesce(p_google_email, '')));
  v_region  text := nullif(btrim(coalesce(p_region, '')), '');
  v_devices text[] := coalesce(p_devices, '{}');
  v_current_google text;
begin
  if length(v_name) < 2 or length(v_name) > 120 then
    raise exception 'Display name must be between 2 and 120 characters.';
  end if;

  if v_google !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Enter a valid Google account email address.';
  end if;

  if length(coalesce(v_region, '')) > 120 then
    raise exception 'Keep the region under 120 characters.';
  end if;

  if array_length(v_devices, 1) > 10 then
    raise exception 'List up to 10 devices.';
  end if;

  if exists (
    select 1 from unnest(v_devices) as d(item)
    where length(btrim(d.item)) = 0 or length(btrim(d.item)) > 80
  ) then
    raise exception 'Each device must be between 1 and 80 characters.';
  end if;

  select array_agg(btrim(d.item))
  into v_devices
  from unnest(v_devices) as d(item);

  v_devices := coalesce(v_devices, '{}');

  if exists (
    select 1 from public.testers
    where lower(google_email) = v_google
      and id <> v_tester
  ) then
    raise exception 'That Google account is already linked to another tester.';
  end if;

  select google_email into v_current_google
  from public.testers
  where id = v_tester;

  if v_google <> v_current_google and exists (
    select 1 from public.campaign_seats
    where tester_id = v_tester and state = 'opted_in'
  ) then
    raise exception 'Opt out of your active projects before changing your Google account email.';
  end if;

  update public.profiles
  set display_name = v_name
  where id = (select auth_user_id from public.testers where id = v_tester);

  begin
    update public.testers
    set display_name = v_name,
        google_email = v_google,
        region = v_region,
        devices = v_devices
    where id = v_tester;
  exception
    when unique_violation then
      raise exception 'That Google account is already linked to another tester.';
  end;

  perform public.write_audit(
    'tester.profile_updated',
    v_tester::text,
    jsonb_build_object('region', v_region, 'devices', v_devices)
  );

  return jsonb_build_object(
    'display_name', v_name,
    'google_email', v_google,
    'region', v_region,
    'devices', to_jsonb(v_devices)
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
