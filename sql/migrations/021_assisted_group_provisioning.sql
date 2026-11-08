-- 021: reserve a manual Google Group identity before operations creates it.
-- Payments now come first: confirming the fee reserves an exact email, display
-- name and per-developer sequence. Operations then creates the group by hand,
-- confirms its settings and attaches the exact reserved identity.

alter table public.developers
  add column if not exists group_sequence_counter integer not null default 0;

alter table public.campaigns
  add column if not exists group_sequence smallint,
  add column if not exists reserved_group_email text,
  add column if not exists reserved_group_url_name text,
  add column if not exists reserved_group_display_name text,
  add column if not exists group_identity_reserved_at timestamptz;

alter table public.google_groups
  add column if not exists display_name text,
  add column if not exists settings_confirmed_at timestamptz,
  add column if not exists settings_confirmed_by uuid references auth.users (id) on delete set null;

update public.google_groups
set display_name = coalesce(nullif(btrim(display_name), ''), btrim(left(name, 73)))
where display_name is null or btrim(display_name) = '';

alter table public.google_groups
  alter column display_name set not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'developers_group_sequence_counter_check'
  ) then
    alter table public.developers
      add constraint developers_group_sequence_counter_check
      check (group_sequence_counter between 0 and 999);
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'campaigns_group_sequence_check'
  ) then
    alter table public.campaigns
      add constraint campaigns_group_sequence_check
      check (group_sequence is null or group_sequence between 1 and 999);
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'campaigns_reserved_group_email_check'
  ) then
    alter table public.campaigns
      add constraint campaigns_reserved_group_email_check
      check (
        reserved_group_email is null
        or (
          reserved_group_email = lower(reserved_group_email)
          and reserved_group_email ~ '^[a-z0-9][a-z0-9._-]{0,62}@googlegroups[.]com$'
        )
      );
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'campaigns_reserved_group_url_name_check'
  ) then
    alter table public.campaigns
      add constraint campaigns_reserved_group_url_name_check
      check (
        reserved_group_url_name is null
        or reserved_group_url_name ~ '^[a-z0-9]([a-z0-9._-]{0,198}[a-z0-9])?$'
      );
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'campaigns_reserved_group_display_name_check'
  ) then
    alter table public.campaigns
      add constraint campaigns_reserved_group_display_name_check
      check (
        reserved_group_display_name is null
        or length(btrim(reserved_group_display_name)) between 1 and 73
      );
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'campaigns_group_identity_reservation_check'
  ) then
    alter table public.campaigns
      add constraint campaigns_group_identity_reservation_check
      check (
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
      );
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'google_groups_display_name_check'
  ) then
    alter table public.google_groups
      add constraint google_groups_display_name_check
      check (length(btrim(display_name)) between 1 and 73);
  end if;
end;
$$;

create unique index if not exists campaigns_developer_group_sequence
  on public.campaigns (developer_id, group_sequence)
  where group_sequence is not null;

create unique index if not exists campaigns_reserved_group_email_key
  on public.campaigns (reserved_group_email)
  where reserved_group_email is not null;

create unique index if not exists campaigns_reserved_group_url_name_key
  on public.campaigns (reserved_group_url_name)
  where reserved_group_url_name is not null;

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

drop function if exists public.attach_group(uuid, text, text);

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
      payment_confirmed_by = v_admin
  where id = p_campaign_id
  returning paid_at into v_paid_at;

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
      'reservation', v_reservation
    )
  );

  return jsonb_build_object(
    'campaign_id', p_campaign_id,
    'payment_state', 'paid',
    'payment_amount_cents', v_campaign.payment_amount_cents,
    'payment_reference', v_reference,
    'paid_at', v_paid_at
  ) || v_reservation;
end;
$$;

do $$
declare
  v_campaign uuid;
begin
  for v_campaign in
    select c.id
    from public.campaigns c
    where c.payment_state = 'paid'
      and c.group_id is null
      and c.state in ('pending', 'awaiting_link')
      and c.reserved_group_email is null
    order by c.created_at
  loop
    perform public.reserve_group_identity(v_campaign, false);
  end loop;
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

revoke execute on function public.reserve_group_identity(uuid, boolean)
  from public, anon, authenticated;
revoke execute on function public.rotate_group_identity(uuid)
  from public, anon, authenticated;
revoke execute on function public.attach_group(uuid, text, text, text, boolean)
  from public, anon, authenticated;
revoke execute on function public.confirm_payment(uuid, text)
  from public, anon, authenticated;

grant execute on function public.rotate_group_identity(uuid) to authenticated;
grant execute on function public.attach_group(uuid, text, text, text, boolean) to authenticated;
grant execute on function public.confirm_payment(uuid, text) to authenticated;

notify pgrst, 'reload schema';
