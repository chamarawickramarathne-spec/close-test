-- 023: remove Google Group availability checking and automatic attach.
-- Payment still reserves the identity, and operations still creates the group,
-- confirms the settings and attaches the reserved address by hand.

do $$
begin
  if to_regprocedure('public.admin_dashboard_base()') is not null then
    drop function if exists public.admin_dashboard();
    alter function public.admin_dashboard_base() rename to admin_dashboard;
  end if;
end;
$$;

drop function if exists public.record_group_check(uuid, text, text);

drop trigger if exists campaigns_group_provision_state on public.campaigns;
drop function if exists public.sync_campaign_group_provision_state();

alter table public.campaigns
  drop column if exists group_provision_state,
  drop column if exists group_provision_checked_at,
  drop column if exists group_provision_error;

revoke execute on function public.admin_dashboard() from public, anon;
grant execute on function public.admin_dashboard() to authenticated;

notify pgrst, 'reload schema';
