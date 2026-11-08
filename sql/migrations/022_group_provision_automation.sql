-- 022: assisted Google Group provisioning. SUPERSEDED BY 023.
-- Kept for migration history. Existing projects should run 023 to remove the
-- automation. Fresh installs can skip 022.
-- The Apps Script web app checks the reserved address and confirms the group
-- after operations creates it. This migration adds the check state and a
-- trigger that resets it when the reserved identity changes.

alter table public.campaigns
  add column if not exists group_provision_state text not null default 'not_checked',
  add column if not exists group_provision_checked_at timestamptz,
  add column if not exists group_provision_error text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'campaigns_group_provision_state_check'
  ) then
    alter table public.campaigns
      add constraint campaigns_group_provision_state_check
      check (
        group_provision_state in (
          'not_checked', 'available', 'taken', 'unknown', 'failed', 'created'
        )
      );
  end if;
end;
$$;

create or replace function public.sync_campaign_group_provision_state()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'INSERT' then
    if new.reserved_group_email is not null then
      new.group_provision_state := 'not_checked';
      new.group_provision_checked_at := null;
      new.group_provision_error := null;
    end if;
    return new;
  end if;

  if new.group_id is not null and old.group_id is distinct from new.group_id then
    new.group_provision_state := 'created';
    new.group_provision_checked_at := now();
    new.group_provision_error := null;
    return new;
  end if;

  if new.reserved_group_email is distinct from old.reserved_group_email
     or new.reserved_group_url_name is distinct from old.reserved_group_url_name then
    new.group_provision_state := 'not_checked';
    new.group_provision_checked_at := null;
    new.group_provision_error := null;
  end if;

  return new;
end;
$$;

drop trigger if exists campaigns_group_provision_state on public.campaigns;

create trigger campaigns_group_provision_state
  before insert or update on public.campaigns
  for each row execute function public.sync_campaign_group_provision_state();

create or replace function public.record_group_check(
  p_campaign_id uuid,
  p_state text,
  p_error text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_admin    uuid := public.require_admin();
  v_state    text := lower(btrim(coalesce(p_state, '')));
  v_error    text := nullif(btrim(coalesce(p_error, '')), '');
  v_campaign public.campaigns%rowtype;
begin
  if v_state not in ('available', 'taken', 'unknown', 'failed') then
    raise exception 'Unknown group check state.';
  end if;

  select * into v_campaign
  from public.campaigns
  where id = p_campaign_id
  for update;

  if not found then
    raise exception 'That project no longer exists.';
  end if;
  if v_campaign.group_id is not null then
    raise exception 'This project already has an attached group.';
  end if;
  if v_campaign.payment_state <> 'paid' then
    raise exception 'Confirm the project fee before checking the group.';
  end if;
  if v_campaign.reserved_group_email is null then
    raise exception 'This project has no reserved group identity.';
  end if;

  update public.campaigns
  set group_provision_state = v_state,
      group_provision_checked_at = now(),
      group_provision_error = v_error
  where id = p_campaign_id;

  perform public.write_audit(
    'group.availability_checked',
    v_campaign.reserved_group_email,
    jsonb_build_object(
      'campaign_id', p_campaign_id,
      'admin_id', v_admin,
      'state', v_state,
      'error', v_error
    )
  );

  return jsonb_build_object(
    'campaign_id', p_campaign_id,
    'state', v_state,
    'checked_at', now(),
    'error', v_error
  );
end;
$$;

-- Keep the existing dashboard body and enrich its group queue. The base
-- function is renamed once so this migration also works on a fresh install
-- whose dashboard already returns the new fields.
do $$
begin
  if to_regprocedure('public.admin_dashboard_base()') is null then
    alter function public.admin_dashboard() rename to admin_dashboard_base;
  end if;
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
  v_payload     jsonb;
  v_group_setup jsonb;
begin
  v_payload := public.admin_dashboard_base();
  v_group_setup := coalesce(v_payload->'group_setup', '[]'::jsonb);

  v_group_setup := coalesce((
    select jsonb_agg(
      elem || jsonb_build_object(
        'group_provision_state', c.group_provision_state,
        'group_provision_checked_at', c.group_provision_checked_at,
        'group_provision_error', c.group_provision_error
      )
      order by c.group_identity_reserved_at nulls last, c.created_at
    )
    from jsonb_array_elements(v_group_setup) elem
    join public.campaigns c on c.id = (elem->>'campaign_id')::uuid
  ), '[]'::jsonb);

  return jsonb_set(v_payload, '{group_setup}', v_group_setup, true);
end;
$$;

revoke execute on function public.record_group_check(uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.record_group_check(uuid, text, text) to authenticated;

revoke execute on function public.admin_dashboard_base()
  from public, anon, authenticated;
grant execute on function public.admin_dashboard() to authenticated;

notify pgrst, 'reload schema';
