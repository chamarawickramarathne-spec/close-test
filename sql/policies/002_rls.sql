-- TesterLoop row level security.
-- Authorisation lives in the database. The desktop client only holds the
-- publishable key, so table grants are removed and every read/write goes
-- through a checked RPC.

create or replace function public.current_role_name()
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select p.role::text
  from public.profiles p
  where p.id = auth.uid()
    and p.status = 'active';
$$;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.admins a
    join public.profiles p on p.id = a.auth_user_id
    where a.auth_user_id = auth.uid()
      and p.status = 'active'
  );
$$;

create or replace function public.current_developer_id()
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select d.id
  from public.developers d
  join public.profiles p on p.id = d.auth_user_id
  where d.auth_user_id = auth.uid()
    and p.status = 'active';
$$;

create or replace function public.current_tester_id()
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select t.id
  from public.testers t
  join public.profiles p on p.id = t.auth_user_id
  where t.auth_user_id = auth.uid()
    and p.status = 'active';
$$;

alter table public.profiles       enable row level security;
alter table public.admins         enable row level security;
alter table public.developers     enable row level security;
alter table public.testers        enable row level security;
alter table public.payment_packages enable row level security;
alter table public.google_groups  enable row level security;
alter table public.campaigns      enable row level security;
alter table public.campaign_seats enable row level security;
alter table public.payment_intents enable row level security;
alter table public.account_activations enable row level security;
alter table public.bug_reports    enable row level security;
alter table public.tester_app_install_daily enable row level security;
alter table public.audit_log      enable row level security;

create policy install_daily_self on public.tester_app_install_daily
  for select using (tester_id = public.current_tester_id());

create policy install_daily_admin on public.tester_app_install_daily
  for select using (public.is_admin());

create policy profile_reads_self on public.profiles
  for select using (id = auth.uid() or public.is_admin());

create policy admin_reads_self on public.admins
  for select using (auth_user_id = auth.uid() or public.is_admin());

create policy developer_reads_self on public.developers
  for select using (auth_user_id = auth.uid() or public.is_admin());

create policy tester_reads_self on public.testers
  for select using (auth_user_id = auth.uid() or public.is_admin());

create policy group_owner_reads on public.google_groups
  for select using (developer_id = public.current_developer_id() or public.is_admin());

create policy campaign_owner_reads on public.campaigns
  for select using (
    developer_id = public.current_developer_id()
    or public.is_admin()
    or (
      state in ('live', 'at_risk')
      and public.current_tester_id() is not null
    )
  );

create policy seat_stakeholder_reads on public.campaign_seats
  for select using (
    tester_id = public.current_tester_id()
    or public.is_admin()
    or exists (
      select 1
      from public.campaigns c
      where c.id = campaign_seats.campaign_id
        and c.developer_id = public.current_developer_id()
    )
  );

create policy report_stakeholder_reads on public.bug_reports
  for select using (
    tester_id = public.current_tester_id()
    or public.is_admin()
    or exists (
      select 1
      from public.campaigns c
      where c.id = bug_reports.campaign_id
        and c.developer_id = public.current_developer_id()
    )
  );

create policy audit_admin_reads on public.audit_log
  for select using (public.is_admin());

-- No direct table or sequence access from the client roles. RPC functions
-- below own the only grants that are handed back to authenticated users.
revoke all on public.profiles       from anon, authenticated;
revoke all on public.admins         from anon, authenticated;
revoke all on public.developers     from anon, authenticated;
revoke all on public.testers        from anon, authenticated;
revoke all on public.payment_packages from anon, authenticated;
revoke all on public.google_groups  from anon, authenticated;
revoke all on public.campaigns      from anon, authenticated;
revoke all on public.campaign_seats from anon, authenticated;
revoke all on public.payment_intents from anon, authenticated;
revoke all on public.account_activations from public, anon, authenticated;
grant select, insert, update on public.account_activations to service_role;
revoke all on public.bug_reports    from anon, authenticated;
revoke all on public.tester_app_install_daily from anon, authenticated;
revoke all on public.audit_log      from anon, authenticated;
revoke all on public.campaign_health from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;

alter default privileges in schema public
  revoke execute on functions from public, anon, authenticated;
