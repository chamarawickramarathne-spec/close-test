-- Create the first operations account. The auth user must exist first:
--   Dashboard -> Authentication -> Users -> Add user -> admin@testerloop.dev
-- Then run:
--   select public.bootstrap_admin('admin@testerloop.dev');

create or replace function public.bootstrap_admin(p_email text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_auth    uuid;
  v_email   text;
  v_profile public.profiles%rowtype;
  v_name    text;
begin
  if session_user not in ('postgres', 'supabase_admin') then
    raise exception 'bootstrap_admin can only be run from the Supabase Dashboard.';
  end if;

  select id, lower(email)
  into v_auth, v_email
  from auth.users
  where lower(email) = lower(trim(p_email));

  if v_auth is null then
    raise exception 'Create the auth user in Supabase first, then run bootstrap_admin.';
  end if;

  select * into v_profile from public.profiles where id = v_auth;
  if v_profile.id is not null and v_profile.role <> 'admin' then
    raise exception 'That account already has the % role.', v_profile.role;
  end if;

  if v_profile.id is null then
    v_name := split_part(v_email, '@', 1);
    insert into public.profiles (id, role, display_name, email)
    values (v_auth, 'admin', v_name, v_email);
  end if;

  insert into public.admins (auth_user_id, note)
  values (v_auth, 'Bootstrapped from the Supabase Dashboard')
  on conflict (auth_user_id) do nothing;

  insert into public.audit_log (actor_id, actor_role, actor_label, action, target)
  values (v_auth, 'admin', v_email, 'admin.bootstrapped', v_email);

  return jsonb_build_object(
    'user_id', v_auth,
    'email', v_email,
    'role', 'admin'
  );
end;
$$;

revoke execute on all functions in schema public from public, anon, authenticated;

grant execute on function public.whoami() to authenticated;
grant execute on function public.ensure_account_role(text) to authenticated;
grant execute on function public.claim_profile() to authenticated;
grant execute on function public.refresh_campaign_states() to authenticated;
grant execute on function public.developer_dashboard() to authenticated;
grant execute on function public.tester_dashboard() to authenticated;
grant execute on function public.admin_dashboard() to authenticated;
grant execute on function public.admin_tester_detail(uuid) to authenticated;
grant execute on function public.admin_developer_detail(uuid) to authenticated;
grant execute on function public.admin_report_detail(uuid) to authenticated;
grant execute on function public.admin_campaign_detail(uuid) to authenticated;
grant execute on function public.confirm_tester_payout(uuid, uuid, text) to authenticated;
grant execute on function public.update_admin_profile(text, text) to authenticated;
grant execute on function public.update_developer_profile(text, text, text, text) to authenticated;
grant execute on function public.update_tester_profile(text, text, text, text[]) to authenticated;
grant execute on function public.create_campaign(text, text, uuid) to authenticated;
grant execute on function public.list_payment_packages() to authenticated;
grant execute on function public.save_payment_package(uuid, text, integer, integer, boolean) to authenticated;
grant execute on function public.delete_payment_package(uuid) to authenticated;
grant execute on function public.delete_campaign(uuid) to authenticated;
grant execute on function public.attach_group(uuid, text, text, text, boolean) to authenticated;
grant execute on function public.rotate_group_identity(uuid) to authenticated;
grant execute on function public.confirm_payment(uuid, text) to authenticated;
grant execute on function public.prepare_payment_intent(uuid) to authenticated;
grant execute on function public.save_play_link(uuid, text) to authenticated;
grant execute on function public.set_report_status(uuid, text) to authenticated;
grant execute on function public.join_campaign(uuid) to authenticated;
grant execute on function public.set_opt_in(uuid, boolean) to authenticated;
revoke execute on function public.record_tester_device(text) from public, anon;
grant execute on function public.record_tester_device(text) to authenticated;
grant execute on function public.file_report(uuid, text, text, text, text, text, text) to authenticated;
grant execute on function public.report_app_install_status(uuid, boolean) to authenticated;
grant execute on function public.report_app_install_daily(uuid, date, boolean, text) to authenticated;
grant execute on function public.report_app_usage_daily(uuid, date, bigint, integer) to authenticated;
grant execute on function public.get_tester_usage_status(uuid) to authenticated;

revoke execute on function public.record_verified_opt_in(uuid, uuid) from public, anon, authenticated;
grant execute on function public.record_verified_opt_in(uuid, uuid) to service_role;

revoke execute on function public.release_unverified_seat(uuid, uuid) from public, anon, authenticated;
grant execute on function public.release_unverified_seat(uuid, uuid) to service_role;

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

revoke execute on function public.bootstrap_admin(text) from public, anon, authenticated;

notify pgrst, 'reload schema';
