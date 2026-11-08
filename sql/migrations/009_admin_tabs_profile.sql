-- Admin tabs and admin profile. Run once against a live 001-008 project.
-- Replaces admin_dashboard() with developers, testers, feedback, package names
-- and the signed-in admin's profile, then adds update_admin_profile().

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
    'groups', coalesce((
      select jsonb_agg(jsonb_build_object(
        'email', g.email,
        'developer', d.company_name,
        'state', g.state::text,
        'provisioned_at', g.provisioned_at,
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
        'seats_used', coalesce(h.seats_used, 0),
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

revoke execute on function public.admin_dashboard() from public, anon;
revoke execute on function public.update_admin_profile(text, text) from public, anon;

grant execute on function public.admin_dashboard() to authenticated;
grant execute on function public.update_admin_profile(text, text) to authenticated;

notify pgrst, 'reload schema';
