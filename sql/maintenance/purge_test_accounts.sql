-- TesterLoop test-account purge.
-- Removes the three documented QA accounts and every row that belongs to them.
--
-- Run in the Supabase SQL Editor as the postgres role.
-- Run Step 1 first and check the preview. Then run Step 2.
--
-- Targeted accounts (explicit list, no pattern matching):
--   qa.smoke.1101231128@example.com   (tester)
--   qa.nav.developer.1102@example.com (developer, project "Nav QA App")
--   qa.optout.e43aa5a4ee@example.com  (tester, 9629c566-2651-453a-bafc-770e091b6112)
--
-- Everything related means: auth users, profiles, developer/tester rows, their
-- campaigns, Google Group rows, seats, bug reports, mobile install/usage rows
-- (cascaded through seats), and audit rows that mention those ids or accounts.

-- ===========================================================================
-- Step 1 - preview (read only, changes nothing)
-- ===========================================================================

drop table if exists _purge_auth;
create temp table _purge_auth as
select u.id as auth_id, lower(u.email) as email
from auth.users u
where lower(u.email) in (
  'qa.smoke.1101231128@example.com',
  'qa.nav.developer.1102@example.com',
  'qa.optout.e43aa5a4ee@example.com'
);

insert into _purge_auth (auth_id, email)
select p.id, lower(p.email)
from public.profiles p
where lower(p.email) in (
    'qa.smoke.1101231128@example.com',
    'qa.nav.developer.1102@example.com',
    'qa.optout.e43aa5a4ee@example.com'
  )
  and not exists (select 1 from _purge_auth a where a.auth_id = p.id);

drop table if exists _purge_dev;
create temp table _purge_dev as
select d.id
from public.developers d
where d.auth_user_id in (select auth_id from _purge_auth)
   or lower(d.contact_email) in (
        'qa.smoke.1101231128@example.com',
        'qa.nav.developer.1102@example.com',
        'qa.optout.e43aa5a4ee@example.com'
      )
   or lower(d.google_email) in (
        'qa.smoke.1101231128@example.com',
        'qa.nav.developer.1102@example.com',
        'qa.optout.e43aa5a4ee@example.com'
      );

drop table if exists _purge_tester;
create temp table _purge_tester as
select t.id
from public.testers t
where t.auth_user_id in (select auth_id from _purge_auth)
   or lower(t.google_email) in (
        'qa.smoke.1101231128@example.com',
        'qa.nav.developer.1102@example.com',
        'qa.optout.e43aa5a4ee@example.com'
      )
   or t.id = '9629c566-2651-453a-bafc-770e091b6112';

drop table if exists _purge_campaign;
create temp table _purge_campaign as
select c.id, c.app_name
from public.campaigns c
where c.developer_id in (select id from _purge_dev);

drop table if exists _purge_report;
create temp table _purge_report as
select r.id
from public.bug_reports r
where r.campaign_id in (select id from _purge_campaign)
   or r.tester_id in (select id from _purge_tester);

select 'auth users' as kind, count(*) as rows from _purge_auth
union all select 'profiles', count(*) from public.profiles
  where id in (select auth_id from _purge_auth)
union all select 'developers', count(*) from _purge_dev
union all select 'testers', count(*) from _purge_tester
union all select 'campaigns', count(*) from _purge_campaign
union all select 'groups', count(*) from public.google_groups
  where developer_id in (select id from _purge_dev)
union all select 'seats', count(*) from public.campaign_seats
  where campaign_id in (select id from _purge_campaign)
     or tester_id in (select id from _purge_tester)
union all select 'bug reports', count(*) from _purge_report
union all select 'audit rows', count(*) from public.audit_log a
  where a.actor_id in (select auth_id from _purge_auth)
     or a.target in (select id::text from _purge_dev)
     or a.target in (select id::text from _purge_tester)
     or a.target in (select app_name from _purge_campaign)
     or a.detail->>'campaign_id' in (select id::text from _purge_campaign)
     or a.detail->>'tester_id' in (select id::text from _purge_tester)
     or a.detail->>'report_id' in (select id::text from _purge_report)
     or a.detail->>'admin_id' in (select auth_id::text from _purge_auth);

select * from _purge_auth order by email;
select id, company_name, contact_email, google_email
from public.developers where id in (select id from _purge_dev);
select id, display_name, google_email
from public.testers where id in (select id from _purge_tester);
select id, app_name, package_name, state
from public.campaigns where id in (select id from _purge_campaign);

-- ===========================================================================
-- Step 2 - delete (single transaction; rolls back on any error)
-- ===========================================================================
-- Run Step 1 first. Step 2 reuses the temp tables from the same session.
-- If the editor starts a new session, run Step 1 again immediately before this.

begin;

delete from public.bug_reports r
where r.id in (select id from _purge_report);

delete from public.campaign_seats s
where s.campaign_id in (select id from _purge_campaign)
   or s.tester_id in (select id from _purge_tester);

delete from public.campaigns c
where c.id in (select id from _purge_campaign);

delete from public.google_groups g
where g.developer_id in (select id from _purge_dev);

delete from public.testers t
where t.id in (select id from _purge_tester);

delete from public.developers d
where d.id in (select id from _purge_dev);

delete from public.audit_log a
where a.actor_id in (select auth_id from _purge_auth)
   or a.target in (select id::text from _purge_dev)
   or a.target in (select id::text from _purge_tester)
   or a.target in (select app_name from _purge_campaign)
   or a.detail->>'campaign_id' in (select id::text from _purge_campaign)
   or a.detail->>'tester_id' in (select id::text from _purge_tester)
   or a.detail->>'report_id' in (select id::text from _purge_report)
   or a.detail->>'admin_id' in (select auth_id::text from _purge_auth);

delete from public.profiles p
where p.id in (select auth_id from _purge_auth);

delete from public.admins a
where a.auth_user_id in (select auth_id from _purge_auth);

delete from auth.users u
where u.id in (select auth_id from _purge_auth);

commit;

-- ===========================================================================
-- Step 3 - verify (all counts must be 0)
-- ===========================================================================

select 'auth users' as kind, count(*) as remaining
from auth.users
where lower(email) in (
    'qa.smoke.1101231128@example.com',
    'qa.nav.developer.1102@example.com',
    'qa.optout.e43aa5a4ee@example.com'
  )
union all select 'profiles', count(*) from public.profiles
  where lower(email) in (
    'qa.smoke.1101231128@example.com',
    'qa.nav.developer.1102@example.com',
    'qa.optout.e43aa5a4ee@example.com'
  )
union all select 'developers', count(*) from public.developers
  where lower(contact_email) in (
    'qa.smoke.1101231128@example.com',
    'qa.nav.developer.1102@example.com',
    'qa.optout.e43aa5a4ee@example.com'
  )
union all select 'testers', count(*) from public.testers
  where lower(google_email) in (
    'qa.smoke.1101231128@example.com',
    'qa.nav.developer.1102@example.com',
    'qa.optout.e43aa5a4ee@example.com'
  )
   or id = '9629c566-2651-453a-bafc-770e091b6112';

drop table if exists _purge_report;
drop table if exists _purge_campaign;
drop table if exists _purge_tester;
drop table if exists _purge_dev;
drop table if exists _purge_auth;

notify pgrst, 'reload schema';
