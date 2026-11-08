# AGENTS_PLAN.md - TesterLoop

Implementation plan and progress tracker. Updated after every work session.

## Product summary

Two Windows desktop applications share one Supabase backend. TesterLoop gives
developers and testers their own workspace; TesterLoop Admin gives operations the
project queue, payment confirmation, reserved group identities, manual group
attach and audit trail. The product takes a developer's project, collects the $15
fee, reserves its exact Google Group identity, has operations create the group by
hand, supplies testers, and tracks the 12-tester / 14-continuous-day rule that
Play requires before production access is granted. A tester may join any number
of projects; each campaign may use at most 15 distinct testers over its lifetime
because every tester is paid, and a failed Google Group check releases that seat.
A paid project keeps its reserved address, display name and per-developer
sequence until operations attaches the group; the Play link cannot go live until
the group is attached and the fee is recorded. A tester-only Android app joins
projects, confirms Google Group opt-in, reports issues and records per-campaign
install and daily usage evidence.

## Fixed constraints discovered before coding

| Constraint | Source | Impact |
|---|---|---|
| Play requires 12 testers opted in 14 continuous days | Play Console Help, checked 2026-11-01 | Seat maths: 12 required + 3 spares = 15 |
| Since 2026 Play also checks testers actually used the app | Play policy coverage, checked 2026-11-01 | Product must capture real evidence, not just opt-ins |
| Consumer @googlegroups.com groups have no API; Google refuses automated sign-in | Google Workspace docs and observed refusal, checked 2026-11-01 | Group creation is a manual operations task; a Workspace domain only matters for future automation |
| Play Console exposes no tester opt-in API | Play Console Help, checked 2026-11-01 | Opt-in is confirmed by a Google Group membership check, never presented as a Play Console read |
| Electron 44 removed ia32 builds | Electron breaking changes, checked 2026-11-01 | Framework choice: WPF on .NET 8 |

## Phase 1 - Foundation

- [x] Application `AGENTS.md`
- [x] `AGENTS_PLAN.md`
- [x] Solution and WPF shell
- [x] Design tokens (colour, type, spacing)
- [x] Developer and tester views in TesterLoop; admin view in TesterLoop Admin
- [x] Postgres schema with 15-seat cap constraint
- [x] RLS policies and RPC-only table access
- [x] Edge Function draft for future Workspace provisioning (not deployed)
- [x] Manual operations flow: pending queue, group address attach, Play link, tester join
- [x] x86 + x64 publish pipeline (`scripts/publish.ps1`)
- [x] Release publish produced for both architectures, architectures verified
- [x] Project relocated to `E:\AIprojects\Safety App\Close Testers`
- [x] Inno Setup script (`installer/TesterLoop.iss`) for both architectures
- [x] Brand assets in `media/` (1024 logo, 512/256/114 icons, .ico)
- [x] `medial_support.txt`
- [x] Git repository initialised on `main`
- [x] Real Supabase auth: sign-in, open signup and OTP reset screens
- [x] Live developer, tester and admin dashboards backed by Supabase RPCs
- [x] 0.4.2 published for x86 + x64, both installers compiled
- [x] Schema preflight before signup and `claim_profile` self-heal
- [x] Single email identity for sign-in and the Play tester list
- [x] Application opens maximized
- [x] Tester signup crash fixed by making display-only `Run` bindings one-way
- [x] SQL `001`-`007` deployed; RPCs verified present (`401` for anonymous calls)
- [x] Tester signup, tester workspace and sign-in verified end to end
- [x] Testers may join unlimited campaigns; each campaign keeps its 15-seat cap
- [x] `sql/migrations/008_unlimited_tester_projects.sql` prepared for the live schema
- [x] 0.4.3 published for x86 + x64, both installers compiled
- [x] Split main app and operations app; shared Supabase/theme library extracted
- [x] Separate admin app with operations-only sign-in and no public signup
- [x] 0.5.0 published for x86 + x64 for both apps, four installers compiled
- [x] Admin app expanded to seven tabs: Operations, Campaigns, Developers,
  Testers, Feedback, Audit Trail, Profile
- [x] Editable admin profile (display name and note) via `update_admin_profile`
- [x] Tester feedback, developer accounts and tester accounts in admin dashboard
- [x] Play link validation accepts both testing and store-details URLs
- [x] 0.5.1 published for x86 + x64 for both apps, four installers compiled
- [x] Admin `Clients` tab renamed to `Testers` across view, view-model and shell
- [x] Empty-tab database-upgrade notice added for missing `009` payload keys
- [x] 0.5.2 published for x86 + x64 for both apps, four installers compiled
- [x] Shell header shows the signed-in role as `DEVELOPER` / `TESTER` / `OPERATIONS`
- [x] Developer `YOUR PROJECTS` lists active projects only; passed/cancelled hidden
- [x] `NEW PROJECT` card moved above `YOUR PROJECTS`
- [x] Developer and tester self-service profile editing via new RPCs
- [x] 0.5.3 published for x86 + x64 for both apps, four installers compiled
- [x] Both sign-in screens remember the last successful email (no password/token)
- [x] 0.5.4 published for x86 + x64 for both apps, four installers compiled
- [x] Project fee, payment confirmation and 0.6.0 packaged for both apps
- [x] Developer roster hides tester email addresses; 0.6.1 packaged for both apps
- [x] Verified opt-in: Google Group membership check via Apps Script and the
  `verify-opt-in` Edge Function; `set_opt_in(true)` rejected for clients
- [x] `sql/migrations/015_verified_opt_in.sql` prepared for the live schema
- [x] 0.7.0 published for x86 + x64 for both apps, four installers compiled
- [x] Group URL name stored per group, passed to the tester join page and the
  Apps Script checker; `016_group_name_slug.sql` prepared
- [x] 0.7.1 published for x86 + x64 for both apps, four installers compiled
- [x] Lifetime 15-tester cap per campaign, including dropped seats
- [x] Failed Google Group check releases the seat so the tester can rejoin
- [x] `verify-opt-in` Edge Function deployed; gateway JWT verification confirmed
- [ ] Owner applies SQL `008` -> `009` -> `010` -> `011` -> `012` -> `013` ->
  `014` -> `015` -> `016` -> `017` -> `018` -> `019` -> `020` -> `021` -> `023`
  -> `024` -> `025` -> `026` -> `027` -> `028` to the live Supabase project,
  skipping superseded `022`; `028` requires `019`
- [ ] Live admin sign-in and dashboard verified with an operations account
- [ ] Add `{{ .Token }}` to the Reset Password email template
- [ ] End-to-end reset, join/opt-in, report and admin attach tests
- [ ] First commit and GitHub release
- [ ] Installers executed end to end on a clean machine
- [ ] Code-signing certificate for the installers
- [x] Both architectures launch and render the login view
- [ ] Pixel-level design review by the owner
- [ ] SMTP for reliable auth email

## Phase 2 - Optional automated Google integration (not required for the manual flow)

- [ ] Owner supplies Workspace domain (only if automation is bought)
- [ ] Service account + domain-wide delegation
- [ ] Replace the manual group flow with an authenticated Workspace provisioner
- [ ] Reconcile job on a schedule
- [ ] Orphaned-group sweep at 30 days

## Phase 3 - Tester operations

- [ ] Tester reputation (completed campaigns, report quality)
- [ ] Auto-replacement when a tester opts out
- [ ] Campaign risk alerts ("3 seats empty, 4 days at risk")
- [ ] Screenshot and crash-log capture in bug reports

## Phase 4 - Commercial

- [ ] Billing
- [ ] Invite gate or developer approval before signup
- [x] Marketing assets in `media/`
- [ ] Release automation on GitHub

## Open questions for the owner

1. Company / product name - currently `TesterLoop`, placeholder.
2. Google Workspace domain - required before Phase 2 can start.
3. x86 still required, or x64 only? Both are being built until told otherwise.
4. Should open signup stay free for both developers and testers, or should one
   side become invite-only before public release?

## 0.4.2 release status

Completed:
- Supabase auth, open signup and OTP reset wired into the WPF client.
- SQL schema, RLS, RPC dashboards and mutations deployed and reachable.
- Demo directory, in-memory workspace and seeded role data removed.
- Signup preflight stops account creation when the schema is missing, with a
  plain-language message instead of `PGRST202`.
- `claim_profile` repairs auth users that have no TesterLoop profile.
- Signup uses one email for both sign-in and the Play tester list; the separate
  Google email field is gone.
- The window opens maximized at `1536x824` on the test display.
- Tester signup crash fixed: `Run.Text` is two-way by default, so all display-only
  `Run` bindings now use `Mode=OneWay`.
- Version `0.4.2` built for x86 and x64; both installers compiled.
- Static SQL review fixed admin-user creation, rejoin seat collisions,
  case-insensitive package duplicates and function execution grants.
- Duplicate tester Google emails are rejected and uniquely indexed; refresh
  requires a valid role; network timeouts and bad JSON become inline errors;
  sign-out always returns to login.
- Release build 0 warnings / 0 errors; all C# files under 300 lines.
- x86/x64 binaries and installers version-checked; PE machines `0x14C` and
  `0x8664`.
- End-to-end: tester account created through the UI, tester workspace rendered,
  and the same account signed in on both x86 and x64 without a crash.
- Disposable smoke account `qa.smoke.1101231128@example.com` exists in Supabase;
  delete it from the Dashboard when convenient.

Pending:
- Owner must include `{{ .Token }}` in the Reset Password email template.
- First admin must be created in Dashboard, then bootstrapped.
- Reset, join/opt-in, report and admin attach flows still need verification.
- Installers have not been executed on a clean machine.
- SMTP, signup gate/billing and code signing remain open.

## 0.4.3 release status

Completed:
- Removed the per-tester project budget. A tester can join any number of
  campaigns; `join_campaign` still locks each campaign and rejects the 16th seat.
- Removed `testers.max_seats` from the greenfield schema and the tester dashboard.
- Added `sql/migrations/008_unlimited_tester_projects.sql` to replace
  `join_campaign`, replace `tester_dashboard`, drop the unused column and reload
  the PostgREST schema cache on the already-deployed project.
- Replaced the tester `SEAT BUDGET` card with `PROJECTS JOINED` and a clear
  "No limit on projects" caption.
- Removed the `MaxSeats` client field and its view-model plumbing.
- Updated `AGENTS.md`, this plan and `medial_support.txt`; version is `0.4.3`.
- Release build 0 warnings / 0 errors; x86 and x64 publish and installers
  compiled.
- Both published executables start and stay responsive on the login view.

Pending:
- Owner must run `sql/migrations/008_unlimited_tester_projects.sql` against the
  live Supabase project before the new join rule is active in production.
- The tester workspace has not been live-verified in 0.4.3 because that requires
  a tester sign-in after the migration. The old dashboard still returns
  `max_seats` until the migration runs; the new client ignores it.
- Installers have still not been executed on a clean machine and remain unsigned.

## 0.6.1 release status

Completed:
- Developer roster no longer shows tester email addresses; only display name,
  device, seat, state and opt-in date are shown.
- `developer_campaign_json` no longer returns tester `google_email` to the
  developer client, and `DeveloperSeatDto` / `RosterRow` no longer carry it.
- Added `sql/migrations/013_hide_tester_emails.sql` for the live project.
- TesterLoop Admin still shows tester emails for operations membership checks.
- Release build 0 warnings / 0 errors. Four executables and four installers
  compiled at version `0.6.1`; all four executables start and stay responsive.

Pending:
- Owner must run `sql/migrations/013_hide_tester_emails.sql` after `012`. Until
  then the live RPC still sends tester emails in the JSON, although the `0.6.1`
  client no longer displays them.
- Live developer roster not re-checked after `013`.
- Installers remain unsigned and have not been executed on a clean machine.

## 0.6.0 release status

Completed:
- Added a $15 per-project fee. The fee is stored on the campaign as
  `payment_state`, `payment_amount_cents`, `payment_reference`, `paid_at` and
  `payment_confirmed_by`.
- Developer project view shows a PROJECT FEE card with the amount, the
  `TL-XXXXXXXX` payment reference and the current status. Creating a project
  explains that the fee is due after the group is attached.
- Developer Play link saving is blocked until operations confirms the payment.
  The check runs in the client and in `save_play_link`; a tampered client cannot
  bypass it.
- Admin Operations now has a payments queue; staff can confirm a payment with an
  optional reference. The admin campaign table shows PAYMENT status per project.
- New RPC `confirm_payment(uuid, text)` is admin-only, writes a
  `payment.confirmed` audit row and is granted only to `authenticated`.
- Added `sql/migrations/012_project_payments.sql` for the live project. It adds
  the payment columns, backfills live/at-risk/passed campaigns as paid, replaces
  `developer_campaign_json`, `admin_dashboard` and `save_play_link`, adds
  `confirm_payment`, and reloads the PostgREST schema cache.
- Version bumped to `0.6.0` in both apps, both installers and the shared config.
- Payment view-model code was split into `DeveloperViewModel.Payments.cs` and
  `AdminViewModel.Payments.cs`; project creation moved to
  `DeveloperViewModel.Projects.cs`. Every C# file is under 300 lines.
- Release build 0 warnings / 0 errors. All four executables and four installers
  were produced at version `0.6.0`; all four executables start and stay responsive.

Pending:
- Owner must run `008` -> `009` -> `010` -> `011` -> `012` in the Supabase SQL
  editor. Until `012` runs, the live dashboard has no payment fields and the
  developer payment card stays in its unpaid state.
- Live payment confirmation and link gating have not been tested against the live
  database; they need `012` and a developer plus operations account.
- The new payment card and payments queue have not been inspected through UI
  Automation.
- Installers remain unsigned and have not been executed on a clean machine.

## 0.5.5 release status

Completed:
- Added a shared left-rail navigation model. `TesterLoop.Shared` exposes
  `NavigationItem`; the shared `ShellView` rail renders the signed-in account's
  menu between the brand and the account card.
- Developer menu: Workspace, Completed projects, Profile.
- Tester menu: Tester bench, Profile.
- Admin menu replaced the tab strip: Operations, Campaigns, Developers, Testers,
  Feedback, Audit Trail, Profile.
- Developer and tester workspaces were split into page views behind a headerless
  `TabControl`; profile editing is now its own page with Save and Discard, not an
  inline card toggled from the workspace header.
- Developer campaigns are split into active and completed collections. The
  Completed projects page lists passed and cancelled projects; the workspace keeps
  pending, awaiting-link, live and at-risk projects.
- Removed the sample Play link hints and the "Use suggested" shortcut from the
  closed-test link card. The card now shows one neutral instruction.
- Version bumped to `0.5.5`.

Pending:
- Owner must still run `008`, `009`, `010`, then `011` against the live Supabase
  project, then create the operations auth user and run `bootstrap_admin`.
- Admin menu rendering and the tester menu need live accounts; the new developer
  menu and profile/completed pages were verified by UI Automation.
- Installers have still not been executed on a clean machine and remain unsigned.

## 0.5.3 release status

Completed:
- Shared shell header now shows a role badge: `DEVELOPER`, `TESTER` or
  `OPERATIONS`, next to the signed-in email.
- Developer `YOUR PROJECTS` filters out `passed` and `cancelled`; pending and
  awaiting-link projects stay visible so a new project is never hidden.
- `NEW PROJECT` now sits above `YOUR PROJECTS` in the developer column.
- Developer profile editing: display name, company/studio, contact email and
  Google account email.
- Tester profile editing: display name, Google account email, region and up to
  10 comma-separated devices.
- `developer_dashboard()` returns `display_name`; new `update_developer_profile`
  and `update_tester_profile` RPCs validate input and write audit rows.
- Added `sql/migrations/011_profile_editing.sql`.
- Release build 0 warnings / 0 errors. Four executables and four installers
  compiled at version `0.5.3`; all four executables start and stay responsive.

Pending:
- Owner must run `008`, `009`, `010`, then `011` against the live Supabase
  project, then create the operations auth user and run `bootstrap_admin`.
- Live profile save, role badges and the active-project filter are not yet
  verified.
- Installers have still not been executed on a clean machine and remain unsigned.

## 0.5.4 release status

Completed:
- Both apps remember the last successful sign-in email and prefill it next time.
- Stored per app in `%LOCALAPPDATA%\TesterLoop`; only the email is written, never
  the password or Supabase tokens.
- A rejected admin sign-in in TesterLoop does not overwrite the remembered
  developer/tester email.
- Release build 0 warnings / 0 errors. Four executables and four installers
  compiled at version `0.5.4`; UI Automation confirmed the prefill on the
  published x64 app.

Pending:
- Owner must run `008`, `009`, `010`, then `011` against the live Supabase
  project, then create the operations auth user and run `bootstrap_admin`.
- Live sign-in memory and the admin app still need working accounts.
- Installers have still not been executed on a clean machine and remain unsigned.


## 0.5.0 release status

Completed:
- Split the product into `TesterLoop` for developers/testers and
  `TesterLoop Admin` for operations staff.
- Extracted shared Supabase transport, DTOs, account models, commands, theme and
  `ShellView` into `TesterLoop.Shared`.
- Removed the admin workspace from the main app; admin accounts are refused there.
- Added an operations-only admin sign-in with no public signup and a role check
  that rejects developer/tester accounts.
- Added separate admin installers with stable names
  `TesterLoop-Admin-Setup-x86.exe` and `TesterLoop-Admin-Setup-x64.exe`.
- Updated both build scripts to publish and package both apps for x86 and x64.
- Release build 0 warnings / 0 errors; four executables and four installers
  compiled at version `0.5.0`.
- All four executables start and stay responsive. Admin sign-in screen verified
  by UI Automation, including its empty-credentials error.

Pending:
- Live admin sign-in and dashboard need an operations account.
- Main-app rejection of a live admin account needs an operations account.
- Migration `008`, installer clean-machine tests and code signing remain open.

## 0.5.1 release status

Completed:
- TesterLoop Admin now has seven tabs: Operations, Campaigns, Developers,
  Clients (testers), Feedback, Audit Trail and Profile.
- Admin tab data comes from one extended `admin_dashboard()` call; campaign
  package names, developer accounts, tester accounts, feedback and the admin
  profile are included.
- The admin Profile tab saves display name and an operations note through the
  new `update_admin_profile` RPC; the shell header refreshes after save.
- Play link validation is shared by the client and SQL and accepts both
  `https://play.google.com/apps/testing/<package>` and
  `https://play.google.com/store/apps/details?id=<package>`.
- Added `sql/migrations/009_admin_tabs_profile.sql` and
  `sql/migrations/010_play_link_validation.sql`.
- Release build 0 warnings / 0 errors. Play validator harness passed 13/13;
  the seven-tab `AdminView` loaded without XAML or binding-path errors.
- Four executables and four installers compiled at version `0.5.1`; all four
  executables start and stay responsive.

Pending:
- Owner must run `008`, then `009`, then `010`, against the live Supabase
  project.
- Owner must create the operations auth user and run `bootstrap_admin` before
  the admin dashboard or profile save can be tested live.
- Live admin tabs/profile and the store-details link are not yet verified.
- Installers have still not been executed on a clean machine and remain unsigned.

## 0.5.2 release status

Completed:
- Admin `Clients` tab renamed to `Testers`: `AdminTestersView`, `TesterRow`,
  `Testers`, `TesterTabLabel` and `HasTesters`.
- `AdminViewModel.LoadAsync` now reports a database-upgrade notice when the live
  `admin_dashboard()` payload lacks `developers`, `testers` or `profile`, instead
  of silently rendering empty tabs.
- Confirmed the reported store-details rejection text comes from a pre-`010`
  client/database; current code accepts both Play link forms.
- Release build 0 warnings / 0 errors. Four executables and four installers
  compiled at version `0.5.2`; all four executables start and stay responsive.

Pending:
- Owner must run `008`, then `009`, then `010`, then create the operations auth
  user and run `bootstrap_admin`.
- Live Developers/Testers tabs, profile save and the store-details link are not
  yet verified.
- Installers have still not been executed on a clean machine and remain unsigned.

## Deviations from original plan

- Modification 007 replaced automatic group creation with the owner's manual
  flow: developer creates a project, staff create the group in groups.google.com
  and attach the address. The provisioning code and SQL stay as a draft for a
  future Workspace domain.
- Modification 008 replaced the local demo accounts and seeded workspace with
  real Supabase authentication and RPC-backed data.
- Modification 009 removed the separate Google email field; the sign-in email is
  the Play tester address. It also added a signup schema preflight and
  `claim_profile` repair because the live project still had no deployed schema.
- Modification 010 fixed the tester signup crash by forcing every display-only
  `Run` binding to `Mode=OneWay`; `Run.Text` is two-way by default in WPF.
- Modification 011 removed the per-tester `max_seats` budget. The original design
  capped a tester at 15 active campaigns; the owner clarified that only each
  campaign is capped at 15 testers.
- Original brief assumed a web system with browser UIs. Owner switched to a
  Windows desktop application with Supabase; plan rewritten accordingly.
- The project now lives in `E:\AIprojects\Safety App\Close Testers` per the owner's
  instruction; the task-workspace copy is kept only as a backup.
- Inno Setup 6 is available at `E:\AIprojects\AI Agent\InnoSetup\ISCC.exe`; both
  installers compile successfully.
- Modification 012 split the single desktop app into `TesterLoop` and
  `TesterLoop Admin` sharing `TesterLoop.Shared`. The owner requested a separate
  admin application; a live admin UI still requires an authenticated admin
  session because RLS and RPC grants enforce it server-side.
- Modification 013 expanded TesterLoop Admin into seven tabs and added an
  editable admin profile. The profile RPC remains admin-only and the signed-in
  email is not editable, so the identity used for authorisation cannot drift.
- Modification 015 added role badges, an active-project filter, card reordering
  and self-service developer/tester profiles. Demo/account email addresses stay
  read-only on the auth record; the editable Google email is stored per role.
- Modification 018 added a $15 per-project fee. The owner chose manual operations
  confirmation rather than an in-app card checkout, so the fee gates activation
  through `save_play_link` and does not add a new campaign state.
- Modification 019 removed tester email addresses from the developer workspace.
  Operations keeps the full tester roster in TesterLoop Admin because group
  membership checks need it; developers only need a name, device and seat state.

## 0.6.2 release status

Completed:
- Admin Operations card renamed from `ACTIVE` to `ACTIVE PROJECTS`.
- Admin `Campaigns` navigation, page title, tab header, operations card and
  supporting copy renamed to `Close Test Projects`.
- Version bumped to `0.6.2`; Release build 0 warnings / 0 errors.
- Four executables and four installers compiled at version `0.6.2`; all four
  executables start and stay responsive.

Pending:
- Owner must run `008` -> `009` -> `010` -> `011` -> `012` -> `013` against the
  live Supabase project.
- Live admin tabs, payments, profile save and developer roster remain unverified
  against the live database.
- Installers have still not been executed on a clean machine and remain unsigned.

## 0.6.3 release status

Completed:
- Developer closed-test link locks once any tester seat exists; the SQL
  `save_play_link` enforces it and the link card becomes read-only.
- Developer roster shows `Reported` / `No report` per active tester.
- Developer detail adds `STARTED`, showing the 12th opt-in date or `Not started`
  until at least 12 testers are actively opted in.
- Added `014_lock_play_link_after_join.sql` with `has_joined_testers`,
  `has_report` and `clock_started_at`.
- Version bumped to `0.6.3`; Release build 0 warnings / 0 errors.
- Four executables and four installers compiled at version `0.6.3`; all four
  executables start and stay responsive.

Pending:
- Owner must run `014` after `008` -> `009` -> `010` -> `011` -> `012` -> `013`.
- Live link lock, roster report column and `STARTED` date are not yet verified
  against the live database.
- Installers have still not been executed on a clean machine and remain unsigned.

## 0.6.4 release status

Completed:
- Pressing Join records the seat and opens the campaign Google Group page derived
  from the group address (`https://groups.google.com/g/<group-name>`).
- Added `GroupLink` validation and `LinkLauncher.TryOpenGroup`; only
  `groups.google.com` pages built from a valid group address can be launched.
- Joined projects expose a `Google Group` button to reopen the same page.
- `GroupLink` harness passed 15/15 valid and malformed addresses.
- Version bumped to `0.6.4`; Release build 0 warnings / 0 errors.
- Four executables and four installers compiled at version `0.6.4`; all four
  executables start and stay responsive.

Pending:
- Live Join-to-browser hand-off and the `Google Group` button are not verified
  because no live tester account was used this round.
- Owner must still run `008` -> `009` -> `010` -> `011` -> `012` -> `013` ->
  `014` against the live Supabase project.
- Installers have still not been executed on a clean machine and remain unsigned.

## 0.7.1 release status

Completed:
- Each `google_groups` row now carries a URL name used for `groups.google.com/g/<name>`.
- Operations must supply both the group address and the group URL name when
  attaching a group. The admin UI validates the slug and shows the full group URL.
- Tester join and the `Google Group` button open the stored group slug; if no
  valid name exists the action refuses and asks for operations.
- `developer_campaign_json`, `tester_dashboard`, `admin_dashboard` return
  `group_name`. The 3-argument `attach_group` validates and stores it.
- `verify-opt-in` sends `{secret, group, name, email}` to the Apps Script
  checker; `Code.gs` accepts and echoes `name` (membership still checked by
  address). Added `sql/migrations/016_group_name_slug.sql` for the live project.
- Version bumped to `0.7.1`; Release build 0 warnings / 0 errors.
- Four executables published (`0.7.1.0`) and four installers compiled
  (product `0.7.1`); all four executables start and stay responsive.

Pending:
- Owner must run `016` after `015` in the Supabase SQL editor and redeploy the
  Apps Script web app if desired (the updated checker is backward compatible).
- The admin group-name field, tester join using the stored slug and the
  Edge/Apps Script name passthrough have not been verified live.
- Installers remain unsigned and have not been executed on a clean machine.

## Deviations in 0.7.1

- Membership lookup remains address-based because `GroupsApp` has no name-based
  lookup; the slug is only for the web link and a consistency signal. A wrong
  slug will still open a Google page that may not exist, but the app no longer
  guesses it from the email.

## 0.7.0 release status

Completed:
- Opt-in is now verified, not attested. Pressing `Confirm opt-in` calls the
  `verify-opt-in` Edge Function, which asks a Google Apps Script web app whether
  the tester's Google address is an active member of the campaign group.
- `set_opt_in(true)` refuses client calls; only `record_verified_opt_in`
  (service_role only) can mark a seat `opted_in` and record
  `opt_in_verified_at` / `opt_in_verification = 'google_group'`.
- Opt-out still works for authenticated clients and clears the verification.
- Tester rows show `Opted in - verified`, `Opted in - unverified` (legacy seats)
  or `Joined - confirm opt-in`, with an explanatory note.
- Changing the tester Google email is blocked while any seat is opted in.
- Added `google-apps-script/group-check/` (Code.gs, appsscript.json, README),
  `supabase/functions/verify-opt-in/index.ts` and
  `sql/migrations/015_verified_opt_in.sql`.
- Version bumped to `0.7.0`; Release build 0 warnings / 0 errors.
- Four executables published (`0.7.0.0`) and four installers compiled
  (product `0.7.0`); all four executables start and stay responsive.

Pending:
- Owner must deploy `Code.gs` as a web app (Execute as Me, Anyone), set its
  `SHARED_SECRET` script property, create the `GROUP_CHECK_URL` and
  `GROUP_CHECK_SECRET` Edge secrets, deploy `verify-opt-in`, then run `015`
  after `014`.
- The Apps Script check, Edge Function round-trip and verified opt-in UI have not
  been tested live.
- No per-user rate limit on the Edge Function; each new confirmation spends one
  Apps Script execution.
- Installers remain unsigned and have not been executed on a clean machine.

## Deviations in 0.7.0

- Modification 023 changed domain rule 4 and rule 5. Consumer groups still have no
  Admin SDK management API and are still `manual sync`, but direct membership can
  now be read one address at a time through the Apps Script `GroupsApp` service.
  Opt-in is therefore confirmed by a membership check rather than tester
  attestation; it is still never presented as a Play Console read.
- Existing `opted_in` seats are not retro-verified. They stay usable and are
  labelled `Opted in - unverified` until the tester confirms through the new path,
  because the app has no record of a past Google Group check.

## 0.7.2 release status

Completed:
- A campaign may use at most 15 distinct testers over its lifetime, because every
  tester is paid. `join_campaign` counts every seat row (including dropped ones) and
  refuses a 16th distinct tester under the campaign lock. Only the same tester may
  rejoin their own dropped seat, and that rejoin clears any stale verification.
- `tester_dashboard.available` now uses the lifetime count for `seats_free` and no
  longer advertises a project that already used all 15 testers.
- `developer_campaign_json` and `admin_dashboard` return `testers_used`. The
  developer screens keep active seats (`seats_used`) for the TESTERS metric, seat
  map, project list and open-slot caption, and show the paid lifetime count in the
  seat summary and completed projects. Admin shows the paid roster size.
- `developer_campaign_json`/admin copy and labels now say TESTERS, and the
  developer requirement text explains the lifetime limit.
- Any failed Apps Script membership check (`inactive`, checker error or an
  unavailable checker) now calls the new service-role-only
  `release_unverified_seat` RPC. The seat is dropped, its opt-in fields are
  cleared, `seat.released_unverified` is audited and the campaign state is
  refreshed, so the tester can fix access and join again. Only failures before
  the check runs (missing secret or configuration) leave the seat intact.
- The tester client reloads the dashboard after a failed Confirm opt-in and keeps
  the server message, including a rejoin prompt when release succeeded. Opting out
  also removes the row from MY CAMPAIGNS immediately.
- Added `sql/migrations/017_lifetime_seat_cap.sql` (join, release, three read
  models, grants, schema reload) and updated the greenfield SQL and `007` grants.
- Version bumped to `0.7.2`.

Pending:
- Owner must run `017` after `016` in the Supabase SQL editor.
- Owner must redeploy `verify-opt-in` from the Dashboard editor so the release on
  a failed check is active; secrets are already configured.
- The lifetime cap, release-on-inactive and the testers-used labels have not been
  verified against live accounts and the updated database.
- Installers remain unsigned and have not been executed on a clean machine.

## 0.8.0 release status

Completed:
- Tester payout ledger. A seat earns a fixed $0.50 when its campaign is `passed`
  and that tester filed at least one report. Any seat state counts, including
  dropped. Fees are stored per seat (`payout_amount_cents`) so a rate change does
  not rewrite history.
- `campaign_seats` gained payout state, reference, paid timestamp and confirming
  admin. A table check requires `paid_at` whenever the state is `paid`.
- `confirm_tester_payout` records a payout once per seat with a reference and a
  `tester_payout.confirmed` audit row; it refuses a missing seat, an already-paid
  payout, a campaign that has not passed and a tester with no report.
- `admin_tester_detail` returns the tester profile, project/report/payout totals
  and every seat with report count, fee, eligibility and payout fields.
- `admin_developer_detail` returns the developer profile, project and payment
  totals, tester payout totals, projects, groups, tester aggregates and up to 50
  scoped audit entries.
- TesterLoop Admin now opens a tester payout page or a developer account page from
  the list, with `Back`. The tester page has a reference field and a `Mark paid`
  action on each eligible project.
- Added `sql/migrations/018_tester_payouts.sql` and updated the greenfield SQL and
  `007` grants.
- Added `TesterFeeCents` / `TesterFeeLabel` and bumped every app/installer artefact
  to `0.8.0`.

Pending:
- Owner must run `017` then `018` in the Supabase SQL editor.
- Owner must redeploy `verify-opt-in` after `017` so failed checks release seats.
- Payout confirmation, the developer detail page and the new admin pages have not
  been verified against live accounts; `018` has not been executed locally.
- Installers remain unsigned and have not been run end to end.

## 0.8.1 release status

Completed:
- Reduced the admin tester and developer detail pages to a compact scale: 14px
  wrapping summary metrics, 9.5px section/table labels, 11px project names and
  10px / 9.5px table cells. The payout action button is 10.5px.
- Bumped every app and installer artefact to `0.8.1`.

Pending:
- Owner must still run `017` then `018` in Supabase and redeploy `verify-opt-in`.
- The compact layout has not been viewed against live admin detail data.
- Installers remain unsigned and have not been run end to end.

### Android 0.2.0 superseded (historical)

- [x] Android tester app scaffolded with parity features and install/usage tracking
- [x] Migration 019_tester_app_usage.sql created for install/usage tables and RPCs
- [x] Restored `LoginVm`; login, signup and splash enforce the tester role
- [x] Signup sends `data.role = "tester"` and the Google email to the auth trigger
- [x] Session store supports clearing tokens without losing the remembered email
- [x] Migration 019 uses `is_admin()`, is idempotent, revokes table access, limits
  usage dates to today/yesterday, and anchors the 14-day run to the latest day
- [x] Added the Android RPC grants to `007` so a bootstrap rerun keeps them
- [x] Usage worker reads real foreground milliseconds from `UsageEvents` and now
  syncs install status plus yesterday/today; install reporting still runs when
  usage access is missing; periodic and immediate work scheduled
- [x] Campaign package name is passed to the detail screen and the field is
  read-only when the campaign provides it
- [x] Manifest disables backup, excludes cloud/device-transfer extraction, and adds
  the launcher icon
- [x] AGP `8.12.0`, Gradle `8.14.3`, SDK `36`, Android version `0.2.0` (`versionCode 2`)
- [x] `:app:assembleDebug` succeeds; APK is `18,981,210` bytes, target SDK `36`;
  lint reports `0 errors`
- [ ] Owner applies `019` to the live Supabase project
- [ ] Install the APK on a device/emulator and verify sign-in, signup, join,
  verified opt-in, install reporting and background usage sync. Blocked locally:
  no device is attached and the `VortexTest` AVD has no hypervisor acceleration.
- [ ] Supply an Android signing keystore and produce a release AAB/APK
- [ ] Play policy review for `QUERY_ALL_PACKAGES` and `PACKAGE_USAGE_STATS`
- [x] Added in 1.0.0: report form, sign-out, profile editor and token refresh.

## Android 1.0.0 release status (rebuilt at `mobile/`)

- Open product requirements (from the owner note `New Text Document.txt`): pay each
  tester $0.50 only after a completed 14-day run, allow reports only after 14 days,
  treat an uninstall before 14 days as a rejection, and disable an account after
  more than five rejections. These conflict with the current rules (payouts after
  the project passes and a report is filed), so they are **not implemented** and
  need owner confirmation before any change.


Completed:
- Deleted the old `src/TesterLoop.Android` project permanently and rebuilt the
  tester app from scratch at `mobile/` (`com.testerloop.app`).
- New warm-light Compose design system, Plus Jakarta Sans, custom brand mark and
  a phase-driven single-view-model architecture (`AppVm` + extension files).
- Screens: splash, auth (sign-in/sign-up/recover/verify), home with continuous-day
  hero and metrics, Projects with Joined/Open segments, campaign detail with
  opt-in/access/usage/reports, report bottom sheet, editable profile, shell with
  bottom navigation.
- Token refresh ported and fixed: JWT expiry check, mutex refresh, single 401
  retry, session clear on rejected refresh. Sign-out and profile editing are now
  in the app, and reports are wired to `file_report`.
- Install and daily usage reporting kept: WorkManager syncs yesterday and today
  plus install status, and install status is reported without Usage Access.
- Version `1.0.0` (`versionCode 10000`), `compileSdk`/`targetSdk` 36, `minSdk` 24.

Verification:
- Deliverables copied to `build/android/TesterLoop-Mobile-1.0.0-debug.apk` and
  `build/android/TesterLoop-Mobile-1.0.0-release-unsigned.apk`.
- `:app:assembleDebug` succeeds; APK `mobile/app/build/outputs/apk/debug/
  app-debug.apk` is `19,060,164` bytes (release unsigned APK `12,982,072` bytes), `versionCode 10000`, `versionName 1.0.0`.
- `:app:lintDebug` succeeds with `0 errors`, 24 warnings, 1 hint.

Pending:
- Install the APK on a device/emulator and verify sign-in, signup, join, verified
  opt-in, report filing, profile save, install reporting and background usage
  sync. Blocked locally: no attached device and no working emulator acceleration.
- Owner must apply migration `019_tester_app_usage.sql` (after `018`), and must
  still apply `017` and `018` and redeploy `verify-opt-in`.
- Supply an Android signing keystore and produce a release AAB/APK.
- Play policy review for `QUERY_ALL_PACKAGES` and `PACKAGE_USAGE_STATS`.
- Superseded: the old `0.2.0` checklist below is historical.

## Latest fix - 0.8.2 desktop / 1.0.1 Android

Completed:
- Tester Join is disabled when a project has no free seats.
  - Desktop `AvailableRow` exposes `SeatsFree` and `CanJoin`; the Join button is
    bound to `CanJoin`, and `JoinAsync` refuses a zero-seat row before calling the
    API.
  - Android `AppVm.join` refuses a zero-seat project, matching the already
    disabled button.
- Desktop apps rebuilt and republished for x86 and x64; both installers recompiled
  at product version `0.8.2`.
- Android debug and release-unsigned APKs rebuilt at `1.0.1` (`versionCode
  10001`) and copied to `build/android`.

Pending:
- Live check of the 0-seat Join state, which needs a fully used campaign and a
  live tester account.
- Migrations `017` and `018` (and `019` for the Android usage fields) are still
  owed by the owner, as is the `verify-opt-in` redeploy.









## Latest - 0.8.3 desktop

Completed:
- Developer project deletion from the project detail page and the Completed
  projects list, behind a confirmation dialog.
- `campaigns.first_opt_in_at` and a 14-day delete/edit lock that starts at the
  first verified opt-in and survives a tester opt-out.
- `delete_campaign` RPC (developer-only, `security definer`), `campaign.deleted`
  audit row and a refusal when any tester payout is already paid.
- `developer_campaign_json` returns `first_opt_in_at`, `delete_locked` and
  `delete_unlocks_at`; the client hides or disables Delete when locked.
- `sql/migrations/020_developer_delete_projects.sql` prepared for the live
  project.
- Desktop apps rebuilt and republished for x86 and x64; both installers recompiled
  at product version `0.8.3`; `medial_support.txt` regenerated.

Pending:
- Apply `020_developer_delete_projects.sql` after `019`, then verify the
  delete round-trip and the 14-day lock with a live developer account.
- Migrations `017`, `018`, `019` and `020` are still owed by the owner, plus the
  `verify-opt-in` redeploy after `017`.
- Installers remain unsigned and have not been run end to end.

## Latest - 0.9.0 desktop

Completed:
- Payment-first assisted group provisioning. Confirming the $15 fee reserves
  the campaign's exact group address, display name, URL name and per-developer
  sequence; operations creates the group manually, attests all five settings and
  attaches the reserved identity before the developer saves a Play link.
- Added `group_sequence`, `reserved_group_email`, `reserved_group_url_name`,
  `reserved_group_display_name`, `group_identity_reserved_at` and
  `developers.group_sequence_counter`, plus group display/settings fields.
- New `reserve_group_identity` and `rotate_group_identity` RPCs;
  `confirm_payment` now reserves on payment, and the old 3-argument `attach_group`
  was replaced by a 5-argument version that requires the exact reserved identity
  and settings attestation.
- Admin Operations now has payment/group-setup queues, copy actions, a settings
  checklist, attach lock and "Issue next number"; developer copy explains the
  fee-before-group order without exposing reserved identities.
- Added `sql/migrations/021_assisted_group_provisioning.sql` and mirrored it into
  the greenfield schema/functions/grants.
- Release build 0 warnings / 0 errors. WPF harness loaded all seven admin tabs
  with `BINDING_COUNT=0`.
- Published and packaged `0.9.0` for both apps and both architectures; all four
  executables start and stay responsive, and all four installers report product
  version `0.9.0`.

Pending:
- Owner must run `021` after `020` in the Supabase SQL editor.
- Migrations `017`, `018`, `019`, `020` and `021` are still owed, plus the
  `verify-opt-in` redeploy after `017`.
- The admin client and `021` must deploy together because the attach signature
  changed.
- Live reservation, rotation, attach, settings attestation and developer copy are
  not verified.
- Installers remain unsigned and have not been run end to end.

## Latest - 0.10.0 desktop

Completed:
- Payment still reserves the exact group identity; operations can now check the
  reserved address through the Apps Script checker, open Google's group creation
  page in one click, then verify and attach the group in one action.
- Added campaign fields `group_provision_state`, `group_provision_checked_at` and
  `group_provision_error`, plus the trigger that resets the check when the
  reserved identity changes and marks a group `created` after attach.
- Added admin-only `record_group_check`, extended `admin_dashboard.group_setup`,
  and kept the large dashboard body behind an `admin_dashboard_base()` wrapper.
- Extended Apps Script with `check_availability` and `verify_group`; `groupName`
  is now required for every action. Added the `provision-group` Edge Function with
  admin check, service-role lookup, 10-second cooldown, check recording and
  automatic attach.
- Admin Operations now has a provisioning status panel, Check availability, Open
  group create page, Verify and attach, Attach without check, Issue next number,
  and a copy action for the reserved URL name.
- Confirming payment now triggers an availability check without rolling back the
  payment if the check fails.
- Added `sql/migrations/022_group_provision_automation.sql` and mirrored the
  greenfield schema/functions/grants.
- Release build 0 warnings / 0 errors. WPF harness loaded `AdminView` with seeded
  group-setup data and reported `BINDING_COUNT=0`.
- Published all four `0.10.0` executables and compiled all four installers at
  product version `0.10.0`.
- All four executables start and keep responsive windows titled `TesterLoop` /
  `TesterLoop Admin`.

Pending:
- Owner must apply migrations `017` -> `018` -> `019` -> `020` -> `021` -> `022`
  in the Supabase SQL editor.
- Redeploy the Apps Script web app as a new version, then deploy
  `provision-group` with the existing `GROUP_CHECK_URL` and
  `GROUP_CHECK_SECRET`. The Apps Script account must be able to see created
  groups.
- Live check, verify/attach, post-payment auto-check and the new admin UI are not
  verified.
- Installers remain unsigned and have not been run end to end.

## Latest - 0.10.1 desktop

Completed:
- Confirming the $15 payment now selects the paid project in the group setup
  queue and opens Google's group creation page automatically.
- Admin Operations explains that Google has no create API for personal
  `@gmail.com` groups; the app reserves the identity and opens the page
  operations must complete by hand.
- The post-payment availability check still runs without rolling back the
  payment if the check fails.
- Release build 0 warnings / 0 errors. WPF harness loaded `AdminView` with
  seeded group-setup data and reported `BINDING_COUNT=0`.
- Published and packaged `0.10.1` for both apps and both architectures; all four
  executables start and stay responsive, and all four installers report product
  version `0.10.1`.

Pending:
- Owner must apply migrations `017` -> `018` -> `019` -> `020` -> `021` -> `022`
  in the Supabase SQL editor.
- Redeploy the Apps Script web app as a new version, then deploy
  `provision-group` with the existing `GROUP_CHECK_URL` and
  `GROUP_CHECK_SECRET`.
- Live post-payment browser hand-off and the updated admin copy are not
  verified, because no live operations account or payment was used.
- Installers remain unsigned and have not been run end to end.

## Latest - 0.10.2 desktop

Completed:
- Reverted automatic group availability checking, verification and attach.
  Confirming the $15 fee still reserves the exact identity and selects the
  project; operations uses `Open group create page`, completes the five-item
  settings checklist and attaches the reserved identity by hand.
- Kept reservation, rotation, copy actions, the create-page button and the manual
  attach fallback.
- Deleted the local `provision-group` Edge Function and removed its client
  service, DTO fields, commands and Operations status panel.
- Reduced the Apps Script checker to `membership`; removed `check_availability`,
  `verify_group`, the group-page fetch and the external-request scope.
- Removed `group_provision_state`, `group_provision_checked_at`,
  `group_provision_error`, the sync trigger and `record_group_check` from the
  greenfield SQL.
- Added `023_revert_group_automation.sql`, which restores `admin_dashboard()` if
  `022` was applied, removes the automation objects and columns, and reloads the
  PostgREST schema cache. `022` is historical and must be skipped on fresh installs.
- Release build 0 warnings / 0 errors. WPF harness loaded `AdminView` with seeded
  reservation data and reported `BINDING_COUNT=0`.
- Published and packaged `0.10.2` for both apps and both architectures; all four
  executables start and stay responsive, and all four installers report product
  version `0.10.2`.

Pending:
- Owner must run `023` after `021` in the Supabase SQL editor.
- Redeploy the Apps Script web app as a new membership-only version.
- Delete the deployed `provision-group` Edge Function in Supabase.
- Live reservation, manual create/attach and the updated Operations copy are not
  verified, because no live operations account or payment was used.
- Installers remain unsigned and have not been run end to end.

## Latest - Android 1.0.2

Completed:
- Fixed the Android "Opt out of this project" failure. `SupabaseApi.setOptIn` used
  a `Map<String, Any>` request body, which Kotlin compiles to
  `Map<String, ? extends Object>`; Retrofit rejects wildcard parameter types, so
  the call failed with "Parameter type must not include a type variable or
  wildcard" before any request was sent.
- Added the typed `SetOptInRequest(p_campaign_id, p_opted_in)` Moshi model and
  switched `AppVm.optOut` to it. Other `Map<String, String>` bodies are unchanged
  because `String` is final and compiles without a wildcard (`javap` verified).
- `:app:assembleDebug`, `:app:assembleRelease` and `:app:lintDebug` succeed;
  `build/android/TesterLoop-Mobile-1.0.2-debug.apk` (18,814,810 bytes) and
  `build/android/TesterLoop-Mobile-1.0.2-release-unsigned.apk` (12,982,076 bytes)
  are `versionCode 10002`, `versionName 1.0.2`. The release APK is unsigned.
- The live `set_opt_in` RPC was probed with an authenticated tester account and
  returns the expected `400 "Join this project before recording an opt-in."`, so
  the grant and function are healthy.

Pending:
- Verify the opt-out round-trip on a real device; no device or accelerated
  emulator is available in this environment.
- Delete the probe account `qa.optout.e43aa5a4ee@example.com` from Supabase.
- Migrations `017`-`023` and the membership-only Apps Script redeploy are still
  owed by the owner.

## Latest - Android 1.0.3 / Desktop 0.10.3

Completed:
- Mobile: removed the Google Group row and `Open Google Group` button from the
  campaign access card; Join still opens the stored group page.
- Mobile: Confirm opt-in now requires Usage Access. Without it the campaign page
  shows a warning banner and `Allow usage access`, and the action refuses before
  any network call. The page re-checks access on resume and on entry.
- Mobile: a confirmed opt-in reloads the dashboard and opens the campaign's Play
  test link automatically when the stored link is valid.
- Mobile: removed the unused `openGroup` helper.
- Desktop: removed Confirm opt-in. `SetOptInAsync` is now a confirmed leave
  action; rows read `Joined`, the button reads `Leave project` / `Opt out`, and
  the note points testers to TesterLoop Mobile.
- Removed the desktop's `verify-opt-in` call, `SupabaseService.OptIn.cs` and the
  unused `VerifiedOptInDto`.
- Versions: Android `1.0.3` (`versionCode 10003`); desktop, admin, both
  projects, both installers and marketing `0.10.3`.
- Verification: `dotnet build TesterLoop.sln -c Release` 0 warnings / 0 errors;
  Android `assembleDebug`, `assembleRelease` and `lintDebug` succeeded.
- Published all four Windows executables at file version `0.10.3.0` (PE `0x14C`
  x86 / `0x8664` x64) and compiled all four installers at product version
  `0.10.3`. APKs: `build/android/TesterLoop-Mobile-1.0.3-debug.apk` and
  `TesterLoop-Mobile-1.0.3-release-unsigned.apk`.

Pending:
- Verify the Usage Access gate, the automatic Play hand-off and the desktop leave
  action on live data. No Android device or accelerated emulator is available.
- Owner must run migrations `017`-`023` and redeploy the membership-only Apps
  Script web app, then delete the deployed `provision-group` Edge Function.
- Installers remain unsigned and have not been run end to end.
- Delete the QA probe account `qa.optout.e43aa5a4ee@example.com`.

## Latest - Android 1.1.0 / Desktop 0.11.0 (dual-role accounts)

Completed:
- Added Developer/Tester to the Windows login. The selected role authenticates,
  reads `whoami`, calls `ensure_account_role` only when that role id is absent,
  then reads `whoami` again; reading first preserves the `claim_profile` repair.
  The plain sign-in remains for TesterLoop Admin.
- Added `ensure_account_role(p_role)` with admin rejection, missing-profile
  creation, Google-address uniqueness handling and an `account.role_added` audit
  row.
- `whoami()` now returns both `developer_id` and `tester_id`; access continues to
  use the role tables, not `profiles.role`.
- Mobile gates on `tester_id` and creates a tester profile when missing; the
  mobile UI remains the tester workspace only. Added a typed `EnsureRoleRequest`.
- Added migration `024_dual_role_accounts.sql` and mirrored the SQL in the
  greenfield functions and grants.
- Versions: Android `1.1.0` (`versionCode 10100`); desktop, admin, both projects,
  both installers and marketing `0.11.0`.
- Verification: Windows build 0 warnings / 0 errors; Android debug, release and
  lint succeeded (0 errors, 24 warnings, 1 hint). Sign-in helpers were split into
  `SupabaseService.Auth.cs` to keep every C# file under 300 lines, then the
  solution, published apps and installers were rebuilt after the final
  claim-preserving sign-in order change. UI Automation confirmed the login
  ComboBox defaults to `Developer` and offers exactly `Developer`/`Tester`.
- Published all four Windows executables at file version `0.11.0.0` (PE `0x14C`
  x86 / `0x8664` x64) and compiled all four installers at product version
  `0.11.0`. APKs: `build/android/TesterLoop-Mobile-1.1.0-debug.apk` and
  `TesterLoop-Mobile-1.1.0-release-unsigned.apk`.

Pending:
- Owner must run migration `024` after `023`, then verify a developer account can
  enter the tester workspace and a tester account can create a project. Until
  then the new RPC returns `404`.
- The capability is broad by design: every non-admin account can now create
  projects. The $15 payment and manual operations activation still gate go-live.
- Installers remain unsigned and have not been run end to end.
- Delete the QA probe account `qa.optout.e43aa5a4ee@example.com`.

## Latest - Android 1.1.1 / Desktop 0.11.1 (mobile device type)

Completed:
- Added `testers.mobile_device_name` and `mobile_device_seen_at`, the
  authenticated `record_tester_device(p_device_name)` RPC, and migration
  `025_mobile_device_type.sql`.
- TesterLoop Mobile reports the normalised manufacturer/model after each
  dashboard load; failures appear as `deviceError` on Profile instead of
  blocking the dashboard.
- Windows tester workspace/profile show the mobile device read-only and the
  report form uses it by default. Manual device editing was removed; legacy
  `devices` values are preserved in profile saves.
- Added the `TEST ON MOBILE` promotion card with `Copy install request`; no
  public mobile download URL is advertised.
- Versions: Android `1.1.1` (`versionCode 10101`); desktop, admin, both projects,
  both installers and marketing `0.11.1`.
- Verification: Windows Release build 0 warnings / 0 errors; Android
  `assembleDebug`, `assembleRelease` and `lintDebug` succeeded (0 errors,
  24 warnings, 1 hint). `aapt` confirms both APKs are `com.testerloop.app`,
  `versionCode 10101`, `versionName 1.1.1`, `minSdk 24`, `targetSdk 36`.
- Published all four Windows executables at file version `0.11.1.0` and compiled
  all four installers at product version `0.11.1`:
  - `build/win-x86/TesterLoop.exe` 141,824 bytes, PE `0x14C`
  - `build/win-x64/TesterLoop.exe` 172,544 bytes, PE `0x8664`
  - `build/admin-win-x86/TesterLoopAdmin.exe` 141,824 bytes, PE `0x14C`
  - `build/admin-win-x64/TesterLoopAdmin.exe` 172,544 bytes, PE `0x8664`
  - `build/win-x86/TesterLoop-Setup-x86.exe` 45,160,046 bytes
  - `build/win-x64/TesterLoop-Setup-x64.exe` 50,050,623 bytes
  - `build/admin-win-x86/TesterLoop-Admin-Setup-x86.exe` 45,079,666 bytes
  - `build/admin-win-x64/TesterLoop-Admin-Setup-x64.exe` 49,953,484 bytes
- Android artifacts copied to `build/android`:
  `TesterLoop-Mobile-1.1.1-debug.apk` (18,814,806 bytes) and
  `TesterLoop-Mobile-1.1.1-release-unsigned.apk` (12,998,456 bytes). The
  superseded `1.1.0` copies were removed. The release APK is unsigned.
- Launch smoke test: all four `0.11.1` executables start, keep responsive
  windows titled `TesterLoop` / `TesterLoop Admin`, and were stopped after the
  check.

Pending:
- Owner must run migration `025` after `024`. Until then device reporting returns
  `404` and the Profile page shows the update notice.
- Verify the device round-trip and install-request copy on live data; no Android
  device or accelerated emulator is available.
- Optional consistency follow-up: the developer roster and admin tester detail
  still read legacy `devices`; update their RPC payloads and UI to prefer
  `mobile_device_name` when desired.
- Installers remain unsigned and have not been run end to end.

## Latest - 0.11.2 desktop

Completed:
- Removed the `Copy install request` button from the tester workspace
  `TEST ON MOBILE` card. The card now ends with "No public download link is
  configured. Ask operations for the install link." and offers no action.
- Deleted the `CopyInstallRequestCommand`, its field and the clipboard handler
  from `TesterViewModel.Mobile.cs`, plus the two usings they left unused.
- No SQL, RPC, Edge Function, grant, secret or data model changed. Android stays
  at `1.1.1`.
- Version bumped to `0.11.2` in `AppConfig`, both projects, both installers and
  `medial_support.txt`.
- Release build 0 warnings / 0 errors. Published all four executables at file
  version `0.11.2.0` and compiled all four installers at product version
  `0.11.2`; all four executables start and stay responsive.

Pending:
- Visual check on the live tester workspace, which needs a live tester account.
- Migrations `017`-`025` and the membership-only Apps Script redeploy remain
  owed by the owner.
- Installers remain unsigned and have not been run end to end.

## Latest - 0.11.3 desktop

Completed:
- Fixed three double-encoded separators in `DeveloperProjectDetailView.xaml`
  report meta rows; they now render as a middle dot.
- Added an inline `LinkActionNote` under the closed-test `Open` and `Copy`
  buttons, so a missing or unsaved link is visible without scrolling to the
  workspace error banner.
- Version bumped to `0.11.3` in `AppConfig`, both projects, both installers and
  `medial_support.txt`. Android stays at `1.1.1`.
- Release build 0 warnings / 0 errors. Published all four executables at file
  version `0.11.3.0` and compiled all four installers at product version
  `0.11.3`.

Pending:
- Verify the inline note and the corrected separators against live report data.
- Migrations `017`-`025` and the membership-only Apps Script redeploy remain
  owed by the owner.
- Installers remain unsigned and have not been run end to end.

## Maintenance - test account purge

Completed:
- Added `sql/maintenance/purge_test_accounts.sql`, a preview-first, single-
  transaction cleanup for the three documented QA accounts:
  `qa.smoke.1101231128@example.com`, `qa.nav.developer.1102@example.com` and
  `qa.optout.e43aa5a4ee@example.com` (`9629c566-2651-453a-bafc-770e091b6112`).
- The script deletes their auth users, profiles, developer/tester rows, campaigns
  (including `Nav QA App`), Google Group rows, seats, bug reports, cascaded mobile
  install/usage rows and the audit rows that mention them or their entities.
- It targets an explicit list, not email patterns, and Step 1 is read-only so the
  rows can be reviewed before Step 2 runs.

Pending:
- Owner must run Step 1, review the preview, then run Step 2 and Step 3 in the
  Supabase SQL Editor. Step 3 must report `0` for every kind.
- No local `psql`, `supabase` CLI, DB connection or service-role key exists in
  this environment, so the script could not be executed here.
- No application build is required; no client source, RPC, grant or secret
  changed.

## Latest - 0.12.0 desktop (payment packages + in-app notifications)

Completed:
- Added admin-managed `payment_packages` with name, project fee, tester payout and
  active flag. Operations create/edit packages on the new `Payment Packages` tab;
  developers choose an active package when creating a project.
- `create_campaign` now requires a package and copies both amounts onto the
  campaign, so later package edits cannot rewrite history. The old 2-argument
  RPC was dropped.
- Added `save_payment_package` (admin-only) and `list_payment_packages`
  (authenticated active-package read). `admin_dashboard` returns packages with
  project counts.
- Replaced all `MessageBox` alerts with shared success/error toasts and a styled
  in-app confirm dialog. Toasts cap at four, expire after five seconds, and are
  hosted by the shared `ShellView` for all workspaces.
- Added `026_payment_packages.sql`, mirrored the table, columns, RPCs, grants and
  dashboard payload in the greenfield SQL/bootstrap, and refreshed
  `medial_support.txt`. The dashboard rename is guarded so rerunning `026`
  preserves the original `admin_dashboard_base`.
- Versions: desktop, admin, both projects and both installers `0.12.0`; Android
  stays at `1.1.1`.
- Verification: `dotnet build TesterLoop.sln -c Release` 0 warnings / 0 errors.
  A temporary WPF harness loaded the shared shell and admin view in separate modes
  and reported `BINDING_COUNT=0`. All four published executables are file version
  `0.12.0.0` (PE `0x14C` x86 / `0x8664` x64), start and stay responsive, and all
  four installers report product version `0.12.0`.

Pending:
- Owner must run `sql/migrations/026_payment_packages.sql` after `025` in the
  Supabase SQL Editor as `postgres`, then verify package create/edit/select, the
  campaign fee copy and the toast/confirm overlays with live accounts.
- The migration's `admin_dashboard` wrapper has not been exercised against the
  live migration-023 state.
- Installers remain unsigned and have not been run end to end.
- QA purge remains owner-run: execute Steps 1-3 of
  `sql/maintenance/purge_test_accounts.sql`.

## Latest - 0.12.1 desktop (payment queue order + package deletion)

Completed:
- Reordered Admin Operations so `PROJECTS AWAITING PAYMENT` appears before
  `GROUPS TO CREATE`, matching the fee-first workflow.
- Replaced fixed `$15` Operations copy with `ConfirmPaymentLabel`, which follows
  the selected package amount. Campaign payment status now shows the campaign's
  copied amount rather than the default package fee.
- Added admin-only `delete_payment_package` and migration `027`. Unused packages
  can be deleted from the package editor after confirmation; used packages and the
  last active package are blocked server-side.
- Added `DeletePaymentPackageAsync`, delete guard state, `CampaignsUsed` on
  `PaymentPackageRow`, the editor delete action/note, the RPC grant in the bootstrap
  SQL, and updated marketing copy.
- Version bumped to `0.12.1` for desktop, admin, both projects and both installers.
  Android remains `1.1.1`.
- Verification: Release build 0 warnings / 0 errors; external harness reports
  `BINDING_COUNT=0` for admin and shell; all four `0.12.1` executables launch and
  stay responsive; all four installers report product version `0.12.1`.

Pending:
- Owner must run `026_payment_packages.sql`, then
  `027_delete_payment_package.sql` in the Supabase SQL Editor as `postgres`.
- Verify live package deletion, the used/last-active blocks, the dynamic confirm
  amount and the Operations ordering with an operations account.
- Installers remain unsigned and have not been run end to end.
- QA purge remains owner-run: execute Steps 1-3 of
  `sql/maintenance/purge_test_accounts.sql`.

## Latest - 0.12.2 desktop (admin usage visibility)

Completed:
- Added an admin-only `USAGE` column to Tester detail project rows. It shows
  install state, distinct and continuous day counts, the 14-day requirement state,
  and the last usage date. Usage remains scoped to the joined project package.
- Updated `admin_tester_detail` in migration
  `028_admin_usage_visibility.sql` and mirrored it in `sql/functions/004_queries.sql`:
  `usage_available: true` plus a per-campaign `usage` object with `installed`,
  `distinct_days_used`, `continuous_days_used`, `meets_usage_requirement`,
  `last_usage_at` and `first_install_at`.
- Migration `028` preflights for `public.tester_app_usage_summary` and raises
  `Run migration 019_tester_app_usage.sql before 028_admin_usage_visibility.sql.`
  when the usage tables are absent. It is admin-only (`require_admin()`), revoked
  from `public`/`anon`, granted to `authenticated`, and reloads the PostgREST
  schema cache.
- Added `AdminTesterUsageDto`, `AdminTesterCampaignDto.Usage`,
  `AdminTesterDetailDto.UsageAvailable`, row labels/tone/tooltip fields and
  `AdminTesterDetail` warning fields. `BuildUsageLabels` uses
  `AppConfig.RequiredDays` (`14`) for `Met`, `In progress`, `8/14 days`,
  `Not installed`, `Not reported`, `Last used yyyy-MM-dd` and `No usage yet`.
- Added the migration-warning banner for old payloads without usage data, and
  cleaned touched detail-page separators to `&#183;`.
- Versions: desktop, admin, both projects, both installers and marketing `0.12.2`;
  Android remains `1.1.1`.
- Verification: `dotnet build TesterLoop.sln -c Release` 0 warnings / 0 errors.
  The external WPF harness reports `BINDING_COUNT=0` for `testerdetail`,
  `testerdetail-missing`, `admin` and `shell`. All four `0.12.2` executables
  start, keep responsive windows titled `TesterLoop` / `TesterLoop Admin`, and
  were stopped. All four installers report product version `0.12.2`.

Pending:
- Owner must run `026_payment_packages.sql`, then
  `027_delete_payment_package.sql`, then `028_admin_usage_visibility.sql` after
  `019` in the Supabase SQL Editor as `postgres`.
- Verify the usage labels and the migration-warning banner with an operations
  account after `028` is applied.
- Installers remain unsigned and have not been run end to end.
- QA purge remains owner-run: execute Steps 1-3 of
  `sql/maintenance/purge_test_accounts.sql`.
## Latest - 0.12.3 desktop (admin usage layout fix)

Completed:
- Corrected the Tester detail project table in TesterLoop Admin. The item template
  now defines the missing `104`-wide `USAGE` column, so the usage, reports, fee,
  payout, reference and action cells align with their headers.
- Version bumped to `0.12.3` for desktop, admin, both projects, both installers and
  marketing. Android remains `1.1.1`.
- Verification: `dotnet build TesterLoop.sln -c Release` 0 warnings / 0 errors.
  The external WPF harness reports `BINDING_COUNT=0` for `testerdetail`,
  `testerdetail-missing`, `admin` and `shell`. All four `0.12.3` executables
  start, keep responsive windows titled `TesterLoop` / `TesterLoop Admin`, and
  were stopped. All four installers report product version `0.12.3`.

Pending:
- Owner must run `026_payment_packages.sql`, then
  `027_delete_payment_package.sql`, then `028_admin_usage_visibility.sql` after
  `019` in the Supabase SQL Editor as `postgres`.
- Verify the usage labels, migration-warning banner and corrected table layout with
  an operations account after `028` is applied.
- Installers remain unsigned and have not been run end to end.
- QA purge remains owner-run: execute Steps 1-3 of
  `sql/maintenance/purge_test_accounts.sql`.

## Latest - 1.1.2 Android (package name + back navigation fix)

Completed:
- Added `029_restore_tester_dashboard_package_usage.sql`, restoring
  `mine[].package_name` and `mine[].usage_status` in `tester_dashboard()` while
  keeping the current mobile device fields. The migration preflights for the
  usage table and reloads the PostgREST schema cache.
- Mirrored both fields into `sql/functions/004_queries.sql`.
- Android `openCampaign` refreshes the dashboard when a project has no package
  name, so the corrected payload appears without a manual refresh.
- Added `BackExitHandler` and wired system back for shell tabs, auth modes,
  campaign detail and splash. Home and login now require a second back press
  within two seconds; the snackbar shows "Press back again to exit".
- Android bumped to `1.1.2` (`versionCode 10102`); Windows remains `0.12.3`.
- Verification: `dotnet build TesterLoop.sln -c Release` 0 warnings / 0 errors.
  Android debug, release and lint succeed; lint reports 0 errors, 24 warnings
  and 1 hint. APKs are in `build/android` as `TesterLoop-Mobile-1.1.2-debug.apk`
  and `TesterLoop-Mobile-1.1.2-release-unsigned.apk`.

Pending:
- Owner must run `029_restore_tester_dashboard_package_usage.sql` after `028`
  (and after `019`) in the Supabase SQL Editor as `postgres`.
- Verify the package name and usage sync on a live tester account after `029` is
  applied.
- Verify back navigation on a physical Android device or accelerated emulator.
  No device or accelerated emulator is available in this environment.
- The release APK is unsigned. Windows installers were not rebuilt because no
  Windows source changed.

## Latest - 0.13.0 desktop / 1.2.0 Android (report usage snapshot + admin report detail)

Completed:
- Added `bug_reports.usage_snapshot` and `usage_captured_at`. `file_report` now
  captures the joined campaign's usage summary server-side, falls back to
  `tester_app_installs` plus the campaign package name, and never blocks a report
  when evidence is missing.
- `tester_dashboard.reports` returns the usage snapshot and capture time; the
  Windows tester MY REPORTS list shows `Usage not captured`, `Usage not reported`,
  `Installed - x/14 days` or `Not installed - x/14 days`.
- Added `admin_report_detail(p_report_id)` and the full report detail page in
  TesterLoop Admin Feedback. It shows severity, status, tester, project, device,
  build, reproduction notes, evidence links, the usage when filed beside current
  usage, and a package mismatch warning. Evidence links are copy-only.
- Admin Feedback is now a master/detail page with Back, refresh and copy actions;
  the duplicate XAML style attributes were removed and a code-behind file added.
- Android: `UsageStatus` gained `available`, `packageName` and `capturedAt`;
  `ReportItem` gained `usage` and `usageCapturedAt`; the report sheet shows an
  "Attached with this report" usage preview and report rows show a usage label.
- Added `030_report_usage_snapshot.sql`, mirrored the schema, queries, action and
  grant into the greenfield SQL and bootstrap, and bumped Windows to `0.13.0`,
  Android to `1.2.0` (`versionCode 10200`).
- Verification: `dotnet build TesterLoop.sln -c Release` 0 warnings / 0 errors.
  The external WPF harness reports `BINDING_COUNT=0` for `reportdetail`, `admin`,
  `shell`, `testerdetail` and `testerdetail-missing`. Android debug, release and
  lint succeed. All four `0.13.0` executables start and stay responsive. All four
  installers report product version `0.13.0`. APKs are in `build/android` as
  `TesterLoop-Mobile-1.2.0-debug.apk` and
  `TesterLoop-Mobile-1.2.0-release-unsigned.apk` (package `com.testerloop.app`,
  `versionCode 10200`, `versionName 1.2.0`).

Pending:
- Owner must run `030_report_usage_snapshot.sql` after `029` (and after `019`,
  `026`-`028`) in the Supabase SQL Editor as `postgres`. `030` was reviewed
  statically only; no local Postgres or `psql` is available.
- Verify on live accounts: tester report usage line, admin report detail snapshot
  vs current usage, the package mismatch warning and the copy actions.
- Verify the Android report-sheet usage preview on a physical device or
  accelerated emulator. No device or accelerated emulator is available in this
  environment.
- Installers remain unsigned and have not been run end to end. The release APK is
  unsigned.
- QA purge remains owner-run: execute Steps 1-3 of
  `sql/maintenance/purge_test_accounts.sql`.
## Latest - 0.14.0 desktop (close test project detail)

Completed:
- Added `admin_campaign_detail(p_campaign_id)` returning the campaign profile,
  totals, testers (with nested usage and payout state), reports (with the usage
  snapshot taken at filing) and the last 50 audit rows for that project.
- Added `031_admin_campaign_detail.sql` (preflight on `tester_app_usage_summary`,
  function, revokes, grant, PostgREST reload); mirrored the function in
  `sql/functions/004_queries.sql` and the bootstrap grants.
- Added shared DTOs and `GetAdminCampaignDetailAsync`; added
  `AdminViewModel.CampaignDetail.cs`, campaign detail row types and
  `AdminCampaignDetail`.
- Close Test Projects is now master/detail. `AdminCampaignDetailView` covers the
  header, metrics, Google Group and payment; `AdminCampaignTestersView` holds the
  tester table; `AdminCampaignActivityView` holds reports and project history.
- Bumped Windows to `0.14.0`. Android stays at `1.2.0`; no Android source changed.
- Verification: `dotnet build TesterLoop.sln -c Release` 0 warnings / 0 errors. The
  external WPF harness reports `BINDING_COUNT=0` for `campaigndetail`,
  `campaignlist`, `admin` and `shell`. All four `0.14.0` executables start and stay
  responsive; all four installers report product version `0.14.0`.

Pending:
- Owner must run `031_admin_campaign_detail.sql` after `030` (and after `019`) in the
  Supabase SQL Editor as `postgres`. `031` was reviewed statically only.
- Verify the project detail page with real data, including usage coverage, report
  snapshots and the project audit list.
- Still owed from earlier rounds: `026`, `027`, `028`, `030` migrations and the QA
  purge (`sql/maintenance/purge_test_accounts.sql`).
- Installers remain unsigned and have not been run end to end.

## Previous - 0.14.1 desktop / 1.2.1 Android (daily install history)

Completed:
- Added `tester_app_install_daily` (one install check per tester, project and day)
  with RLS self/admin select, client-table revokes, touch trigger and unique
  tester/project/date row.
- Added `report_app_install_daily(campaign_id, date, installed, source)` and kept
  `report_app_install_status` as a compatibility wrapper for older APKs. The
  wrapper routes live/at-risk through the daily record, clamps a passed project to
  its pass date and returns `recorded: false` for a cancelled project.
- `file_report` now stores `install_history` (join-date to report-date daily
  window, capped at 365 days), `install_history_captured_at`,
  `install_window_start` and `install_window_end`.
- `tester_dashboard` returns `campaign_state` and `joined_at` for joined projects
  plus the four install-history fields on reports. `admin_report_detail` returns
  the same four fields at the top level.
- Android: new `InstallHistoryStore` (DataStore + `org.json`), `InstallTracking`
  predicate (`live` / `at_risk` only), `DailyInstallCheckWorker`, `SyncQueue` and
  a rewritten `UsageSyncWorker`. Dashboard loads and manual checks record the day
  locally first, then upload; 401 is rethrown, other 4xx marks the row synced and
  transport/5xx retries. Synced rows are pruned after 45 days.
- Android UI: install checks stop on closed projects, the campaign card and report
  sheet explain the daily check, and report rows show an install summary.
- Admin: `AdminInstallCheckDto` and the four fields on `AdminReportDetailDto`;
  a DAILY INSTALL CHECKS AT FILING card shows Installed daily / Gaps found / Not
  installed / Not checked, installed vs checked days and the window.
- Added `032_daily_install_history.sql`; mirrored the table, columns, RLS, RPCs and
  read models into the greenfield SQL and bootstrap grants.
- Bumped Windows to `0.14.1` and Android to `1.2.1` (`versionCode 10201`).
- Verification: `dotnet build TesterLoop.sln -c Release` 0 warnings / 0 errors.
  Android `:app:assembleDebug`, `:app:assembleRelease` and `:app:lintDebug`
  succeed. All four `0.14.1` executables start and stay responsive; all four
  installers report `0.14.1`. APKs are `1.2.1` / `10201`.

Pending:
- Owner must run `032_daily_install_history.sql` after `031` (and after `019`) in
  the Supabase SQL Editor as `postgres`. `032` was reviewed statically only.
- Verify the daily check, the report install window and the admin card with a real
  tester device; no device or accelerated emulator is available here.
- Still owed from earlier rounds: `017`-`032` migrations and the QA purge
  (`sql/maintenance/purge_test_accounts.sql`).
- Installers remain unsigned and have not been run end to end.
## Latest - 0.14.1 desktop / 1.2.2 Android (signed release + in-app updater)

Completed:
- Created the TesterLoop upload keystore at `.keys/testerloop-upload.jks` with
  credentials in `.keys/credentials.txt`. Both are gitignored, and
  `mobile/keystore.properties` carries the local signing values.
- `mobile/app/build.gradle.kts` now creates a release signing config only when
  `keystore.properties` exists, so clones without the keystore still build an
  unsigned release.
- Signed `TesterLoop-Mobile-1.2.2.apk` and `.aab` are committed under `release/`
  and attached to the `mobile-v1.2.2` GitHub release with `mobile-version.json`.
- Added `core/AppUpdater.kt`: reads the latest public GitHub release, prefers the
  `mobile-version.json` manifest, downloads the APK to the cache and launches the
  system installer through a `FileProvider`. Handles the missing
  "install unknown apps" permission by opening the settings page.
- Added `ui/AppVm.Update.kt`, update fields in `UiState`, the Profile APP UPDATE
  card and silent checks after sign-in and after the first dashboard load.
- Manifest gained `REQUEST_INSTALL_PACKAGES` and the FileProvider; new
  `res/xml/file_paths.xml` exposes only `cacheDir/updates`.
- Created the public repo `chamarawickramarathne-spec/close-test`, pushed `main`
  and published release `mobile-v1.2.2`.
- Bumped Android to `1.2.2` (`versionCode 10202`). Windows stays `0.14.1`.

Pending:
- Owner decision on removing the mobile update feature from git; when removed,
  delete `AppUpdater`, `AppVm.Update.kt`, the Profile card, the manifest
  permission/FileProvider, `file_paths.xml` and the published
  `mobile-version.json` together.
- Owner must run `032_daily_install_history.sql` after `031` (and after `019`) in
  the Supabase SQL Editor as `postgres`. `032` was reviewed statically only.
- Verify the update check, download, install prompt, daily install check and report
  install window on a real tester device; no device or accelerated emulator is
  available here.
- Still owed from earlier rounds: `017`-`032` migrations and the QA purge
  (`sql/maintenance/purge_test_accounts.sql`).
- Windows installers remain unsigned and have not been run end to end.
## Fix - admin project detail SQL (2026-11-08)

Completed:
- Fixed `admin_campaign_detail` using `h.` (campaign_health) without selecting
  from the view, which made every close-test project page fail with
  `missing FROM-clause entry for table "h"`.
- The function now loads the view into `v_health`; `031` and the greenfield
  `004_queries.sql` copy are corrected, and `033_fix_admin_campaign_detail.sql`
  applies the fix to the live project.
- SQL-only change; Windows stays `0.14.1`, no client rebuild.

Pending:
- Owner must run `033_fix_admin_campaign_detail.sql` in Supabase after `031`.
- Verify the project page opens with real data once `033` is applied.
## Release 0.14.2 desktop - developer payout hidden (2026-11-08)

Completed:
- Developer new-project package summary shows the project fee only; tester payout
  is no longer displayed anywhere in TesterLoop.
- TesterLoop Admin unchanged: package fee and tester payout still visible to
  operations.
- Built `0.14.2` for x86/x64 main + admin, four installers, x64 smoke test.

Pending:
- Owner to run `033_fix_admin_campaign_detail.sql` and
  `032_daily_install_history.sql` in Supabase.
- Confirm the developer new-project form against the live package list.## Release 0.14.3 desktop - merged report usage cards (2026-11-08)

Completed:
- Merged the Admin report detail `INSTALL AND USAGE AT FILING` and
  `CURRENT USAGE` cards into one `INSTALL AND USAGE` card with `AT FILING` and
  `LIVE NOW` columns, and moved `DAILY INSTALL CHECKS AT FILING` beside it.
- Presentation-only; no SQL, RPC, DTO or validation change.
- Built `0.14.3` for x86/x64 main + admin, four installers, launch smoke test on
  the published x64 builds. Harness reported `BINDING_COUNT=0` for
  `reportdetail`.

Pending:
- Verify the merged card with live report data and an operations account.

## Release 1.2.3 mobile - report build auto-detected (2026-11-08)

Completed:
- Added `core/InstalledApp.kt`; the report sheet no longer asks for a build and
  shows the detected `versionName (versionCode)` read-only.
- `AppVm.submitReport` detects the build from the joined project's package at
  submit time and sends it as `p_build_label`, or nothing when the app is not
  installed.
- Android bumped to `1.2.3` (`versionCode 10203`); signed APK and AAB rebuilt and
  copied to `build/android` and `release/`; `release/mobile-version.json`
  updated.

Pending:
- Publish GitHub release `mobile-v1.2.3` so the in-app updater offers it.
- Verify the detected build label and read-only card on a real tester device.

## Release 0.15.0 desktop - tester project activity (2026-11-08)

Completed:
- Added `AdminTesterProjectActivity`, `AdminViewModel.TesterProject.cs` and
  `AdminTesterProjectView` with open, refresh and back commands. The page shows
  the tester's seat state, timeline, install and usage evidence, payout record
  and every report filed on that project.
- Added origin-aware report navigation: one report page with `Back to feedback`,
  `Back to project` and `Back to activity`, plus a resettable origin when the
  side menu changes.
- Campaign activity report rows and tester project activity report rows are now
  clickable buttons.
- Extended `AdminTestersView` with activity/report tabs (indices 2 and 3) and
  `AdminCampaignsView` with a project report tab (index 2).
- Split report usage helpers into `AdminViewModel.ReportDetail.Usage.cs`; both
  report partials are under 300 lines.
- Windows bumped to `0.15.0`; both apps published for x86/x64 and both installers
  rebuilt.

Pending:
- Verify the activity page, the origin-aware back button and clickable report
  rows against live operations data.
- Run the new page with migration `028` applied so the usage section is live.

## Release 0.15.1 desktop - admin dashboard counts refresh (2026-11-08)

Completed:
- Fixed the Operations top cards showing stale zeros. `LoadAsync` now raises
  `DeveloperCount`, `PendingCount`, `LiveCount`, `TesterCount` and `GroupCount`
  after assigning `_counts`, so the five metric cards reflect the dashboard
  payload as soon as it arrives.
- Windows bumped to `0.15.1`; both apps published for x86/x64 and both installers
  rebuilt.

Pending:
- Verify the top cards with a live operations account after sign-in and refresh.

## Release 0.15.2 desktop / 1.2.4 Android - project clock (2026-11-08)

Completed:
- `tester_dashboard().mine` now takes `days`, `clock_started_at` and
  `confirmed_testers` from `campaign_health`, so the 14-day clock starts only
  after 12 testers confirm opt-in and resets when the count drops below 12.
- Windows tester MY CAMPAIGNS shows `Clock not started` until the clock begins.
- Android added a shared `ProjectClock`; joined-project, campaign and home cards
  show `Waiting for N more confirmed testers` with an empty progress track, then
  `X of 14 days`. Pre-migration payloads fall back to the old per-tester count.
- Added `sql/migrations/034_tester_project_clock.sql` for the live project.
- Windows `0.15.2` published for x86/x64 with both installers; Android `1.2.4`
  (`versionCode 10204`) signed APK and AAB built and copied to `release/`.
- Committed the previously uncommitted modifications 053-058 with this round.

Pending:
- Apply migration `034` after `033` and verify the clock transition on live data.
- Device-verify the Android clock copy; no device or accelerated emulator is
  available here.

## Still owed from earlier rounds

- Supabase migrations `017`-`034` run by the owner, plus the QA purge in
  `sql/maintenance/purge_test_accounts.sql`.
- Windows installers remain unsigned and have not been run end to end.

## Release 1.2.5 Android - update check retries (2026-11-08)

Completed:
- Fixed the mobile updater reporting "The update server answered 504" from the
  GitHub REST API with no retry.
- Checks now read `releases/latest/download/mobile-version.json` from
  `github.com` first and build the APK URL from its validated `apk` field, so the
  normal path never calls `api.github.com`. The API remains a fallback.
- `AppUpdater` retries 5xx and transport failures three times with backoff on the
  check, manifest fetch and download; downloads are verified against
  `Content-Length` and a truncated file is retried.
- Android bumped to `1.2.5` (`versionCode 10205`); signed APK and AAB copied to
  `release/`. Windows stays at `0.15.2`.

Pending:
- Install `1.2.5` once on a device; older clients keep the old updater until then.
- Device-verify the retry path and manifest-first check; no device or accelerated
  emulator is available here.

## Release 1.2.6 Android - Play distribution and package rename (2026-11-08)

Completed:
- Removed the GitHub in-app updater from TesterLoop Mobile because Google Play now
  owns updates: deleted `AppUpdater.kt`, `AppVm.Update.kt`, the Profile update card,
  the update `UiState` fields, `REQUEST_INSTALL_PACKAGES`, the FileProvider and
  `res/xml/file_paths.xml`, and deleted `release/mobile-version.json`.
- Renamed the Android application id and Kotlin package from `com.testerloop.app`
  to `lk.closetester.helper` (namespace, applicationId, source tree, all imports).
- Android bumped to `1.2.6` (`versionCode 10206`). Windows stays at `0.15.2`.
- Clean build of `assembleDebug`, `assembleRelease`, `bundleRelease` and
  `lintDebug` succeeded; lint reports 0 errors and 11 warnings.
- Artifacts: `release/TesterLoop-Mobile-1.2.6.apk` and
  `release/TesterLoop-Mobile-1.2.6.aab` (Play upload), plus debug/release APKs in
  `build/android`. Signed with the existing upload keystore; superseded 1.2.5
  artifacts were removed.

Pending:
- Upload `release/TesterLoop-Mobile-1.2.6.aab` to Google Play (new app identity
  `lk.closetester.helper`).
- Device-verify sign-in, join, opt-in, reports and usage sync under the new
  package id; no device or accelerated emulator is available here.
- Apply migrations `032`-`034` and run the QA purge.