-- Accept both Google Play closed-test links and Play Store details links.
-- Example: https://play.google.com/store/apps/details?id=lk.photostudiomanager

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

revoke execute on function public.save_play_link(uuid, text) from public, anon;
grant execute on function public.save_play_link(uuid, text) to authenticated;

notify pgrst, 'reload schema';
