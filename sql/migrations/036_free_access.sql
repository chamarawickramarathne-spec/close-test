-- Free access activation.
--
-- Payment is temporarily disabled. A developer can activate a project without
-- the project fee; the campaign is marked paid with a zero amount, records
-- payment_paid_via = 'free', reserves the group identity and can continue to
-- group attachment and the Play link. Operations can still see the original
-- package fee on the package and the project history.
--
-- Run this after 035_online_payments.sql.

alter table public.campaigns
  drop constraint if exists campaigns_payment_amount_check;

alter table public.campaigns
  add constraint campaigns_payment_amount_check
  check (payment_amount_cents between 0 and 1000000);

alter table public.campaigns
  drop constraint if exists campaigns_payment_paid_via_check;

alter table public.campaigns
  add constraint campaigns_payment_paid_via_check
  check (payment_paid_via is null or payment_paid_via in ('manual', 'online', 'free'));

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

revoke execute on function public.claim_free_access(uuid) from public, anon;
grant execute on function public.claim_free_access(uuid) to authenticated;

notify pgrst, 'reload schema';
