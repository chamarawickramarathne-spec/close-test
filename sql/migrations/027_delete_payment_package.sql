-- 027: delete unused payment packages.
-- A package that has been copied onto a campaign is immutable history, so it
-- can only be deactivated. An unused package may be deleted, but at least one
-- active package must remain so developers can still create projects.

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

revoke execute on function public.delete_payment_package(uuid)
  from public, anon, authenticated;
grant execute on function public.delete_payment_package(uuid) to authenticated;

notify pgrst, 'reload schema';
