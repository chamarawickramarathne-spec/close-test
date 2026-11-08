# AGENTS.md - TesterLoop

Application-level rules and long-term modification memory for TesterLoop.

## 1. What this application is

TesterLoop is a Windows desktop suite plus an Android tester app for running
Google Play **closed testing** programmes as a paid service. Three clients share
one Supabase backend, and each audience only ever sees its own side:

- **TesterLoop** - for developers and testers.
  - **Developer** - a paying app developer. Creates a project, pays the project
    fee, waits for operations to create and attach the Google Group, adds the
    group to Play Console, tracks the 12-tester / 14-day clock and reads tester
    reports.
  - **Tester** - a freelance app tester. Joins any number of open campaigns,
    confirms opt-in per campaign and files bug reports.
- **TesterLoop Admin** - for our own operations staff. Records each project fee,
  reserves the group identity, creates the Google Group by hand in
  groups.google.com, confirms its settings, attaches the exact reserved address
  and URL name, activates the campaign, checks membership manually and reads the
  audit log.
- **TesterLoop Mobile** - the Android tester app in `mobile/`. Tester workspace
  only. Shows the tester bench, joins projects, opens the group and Play pages,
  confirms group-verified opt-in, files reports, edits the profile, and records
  install status plus daily foreground usage for joined project packages.

A non-admin account may sign in to TesterLoop as either Developer or Tester; the
missing role profile is created on first use. There is no role switcher inside a
session. TesterLoop and TesterLoop Mobile refuse admin accounts; TesterLoop Admin
refuses developer and tester accounts. All three clients use email/password
sign-in, and TesterLoop Admin has no public signup.

## 2. Architecture decisions

| Decision | Choice | Reason |
|---|---|---|
| UI framework | WPF on .NET 8 (`net8.0-windows`) | x86 and x64 are both first-class; self-contained publish has no WebView2 or Chromium dependency, which matters for the old 32-bit machines x86 exists for |
| Why not Electron | rejected | Electron 44 (Aug 2026) removed Windows ia32 builds; v43 support ends Jan 2027 |
| Applications | `TesterLoop` for developers/testers; `TesterLoop Admin` for operations | Separate processes and installers; the admin workspace is not exposed inside the main app |
| Mobile app | Kotlin + Jetpack Compose in `mobile/`, package `lk.closetester.helper` | Tester-only Android client for the phone that runs the app under test; shares the same Supabase auth, RPCs and Edge Function as the desktop apps; distributed through Google Play, which owns updates |
| Shared code | `TesterLoop.Shared` WPF library | Supabase transport, account models, tokens, controls and shell chrome are shared; role-specific views stay in each app |
| Data store | Supabase (Postgres + Auth + RLS) | Requested by the owner. Desktop clients hold a public anon key, so authorisation must live in RLS, never in the client |
| Server tier | Supabase Edge Functions | Google Workspace service-account credentials must never ship inside a desktop binary |
| Group provisioning | Assisted manual: payment reserves the identity, the app opens Google's group creation page, and operations creates and attaches the group by hand | Google refuses automated sign-in from a controlled browser, and consumer `@gmail.com` groups have no create/list API. The app never claims to create or verify a group; the Apps Script checker reads membership only |
| Group source | Payment reserves the identity; operations creates the group and attaches the exact reserved address, display name and actual URL name | The sequence, address and display name are generated server-side after the fee is paid, so staff cannot mistype or reuse them. The URL slug is confirmed after the group exists; membership is never presented as synced |
| Installers | Inno Setup, stable names `TesterLoop-Setup-x86/x64.exe` and `TesterLoop-Admin-Setup-x86/x64.exe` | Update system depends on stable filenames; admin installs separately |
| Updates | GitHub Releases via in-app updater | Satisfies the Git-based desktop update requirement |

## 3. Non-negotiable domain rules

1. **A campaign may use at most 15 distinct testers over its lifetime**, because
   every tester is paid. Enforced in the database by `join_campaign` under the
   campaign advisory lock, not in the UI. Dropped seats count, so only the same
   tester can refill their own dropped row; a 16th distinct tester is refused.
   There is no cap on how many campaigns one tester may join.
2. **12 testers must stay opted in for 14 continuous days.** If a tester opts out,
   their own clock resets to zero. A campaign still needs 12 active testers, and
   the lifetime limit leaves only three replaceable testers before the project
   must run with those seats.
3. **A failed Google Group check releases the seat.** When `verify-opt-in` cannot
   confirm active membership - an `inactive` answer, an unavailable checker or a
   checker error - the Edge Function calls the service-role-only
   `release_unverified_seat`, so the tester leaves the project and may join again
   after fixing access. Only a failure before the membership check runs (missing
   secrets or configuration) leaves the seat intact.
4. **A campaign pays before its group is created.** A developer creates a project
   and it stays `Pending`. Staff confirm the $15 fee, which reserves the exact
   `@googlegroups.com` address, per-developer sequence, display name and URL name.
   Operations then creates the Google Group by hand. Confirming the fee selects
   the paid project; operations opens Google's group creation page from the app,
   creates the group, completes the settings checklist and attaches the exact
   reserved identity. For a consumer `@gmail.com` account the app cannot create,
   inspect or verify the group through any API. The developer saves the Play link
   only after the group is attached. The app never claims to create a group.
   A group that is never used by a campaign is flagged `orphaned` after 30 days, never
   deleted automatically.
5. A group on a consumer `@gmail.com` account has **no Admin SDK API** - it cannot
   be created or listed. Membership can still be read one address at a time by the
   Apps Script `GroupsApp` service, acting as the account that owns the group.
   Groups are never presented as reconciled: the UI says `manual sync`, and only a
   Workspace domain with domain-wide delegation could ever change that.
6. Play Console has **no API for tester opt-in status**. Opt-in is confirmed by
   checking that the tester's Google address is an active member of the campaign's
   Google Group, via the `verify-opt-in` Edge Function and an Apps Script web app.
   The UI must show that as a Google Group membership check, never as a Play
   Console opt-in read.
7. **A closed-test link is final once any tester joins.** The first seat locks the
   Play link in SQL; the client must not offer an edit path after that.
8. **A tester is paid the campaign's copied tester payout only after it passes and
   only with a filed report.** Payouts are recorded once per seat by operations,
   with a reference and an audit row. The fee is stored on the seat so a later rate
   change cannot rewrite an amount already owed or paid. A dropped seat still
   counts if the report and passed state exist.
9. **A reserved group identity is admin-only until it is attached.** The developer
   sees that operations is creating the group, not the reserved address. Only
   `confirm_payment` and `rotate_group_identity` may reserve an identity; a client
   cannot choose a sequence, address, display name or URL name.
10. **Payment terms come from an active admin package.** Operations define the
    package name, project fee and tester payout; a developer chooses one when
    creating a project. `create_campaign` copies both amounts onto the campaign, so
    later package edits never rewrite an existing project or an amount already owed.
    The default `Standard` package is `$15` and `$0.50`.

## 4. Security rules

- The Supabase anon key lives in the client. Every table has RLS policies; a
  tester must not read another developer's campaigns.
- TesterLoop Admin is not an authentication bypass. Live operations require an
  authenticated admin account; the client-side role check only keeps each app on
  its own side.
- TesterLoop refuses admin accounts and TesterLoop Admin refuses developer and
  tester accounts. Neither app has a role switcher inside a session.
- `ensure_account_role` is authenticated-only and refuses admins. Any non-admin
  account can deliberately create the missing developer or tester profile; that
  is a product decision, and the $15 fee plus operations activation still gate a
  project before it can go live.
- Google service-account JSON, and any Play Console credentials, exist only in
  Edge Function secrets.
- No credential, token or service-account value is written to logs, crash dumps
  or the audit trail.
- Group membership is never shown as verified for a manually created group. Those
  groups are labelled `manual sync`, with instructions instead of a sync state.
  A successful `verify-opt-in` check may mark that one tester's seat as verified,
  but it never becomes a reconciled group roster.
- The `verify-opt-in` Edge Function is the only caller allowed to confirm an
  opt-in. Its `GROUP_CHECK_URL` and `GROUP_CHECK_SECRET` live in Edge secrets and
  are never shipped to a desktop client.

## 5. Coding standards

- One type per file, files under 300 lines.
- Shared transport, models, controls and shell chrome live in `TesterLoop.Shared`.
  Role-specific views and view-models stay in `TesterLoop.Desktop` or
  `TesterLoop.Admin`.
- No silent fallbacks: invalid input surfaces as an inline message and a toast, and
  the campaign keeps its previous state.
- No comments unless they explain a non-obvious constraint.
- Every change to the Android app under `mobile/` must be committed to Git after
  it is verified, so the owner can review it. Do not leave mobile changes
  uncommitted.

## 6. Modification log

### Modification 001

Date: 2026-11-01

#### Changes
- Created project skeleton: solution, WPF desktop shell, three role views.
- Added Postgres schema for developers, testers, campaigns, groups, seats,
  memberships, reports and audit log.
- Added RLS policy set.
- Added Edge Function for Google Group provisioning and membership reconcile.
- Added simulated group provisioner so the product is demonstrable before a
  Google Workspace domain exists.

#### Files / Components
- `src/TesterLoop.Desktop/`
- `sql/schema/001_init.sql`
- `sql/policies/002_rls.sql`
- `sql/seed/003_seed.sql`
- `supabase/functions/provision-group/`

#### Important Notes
- Real group creation requires a Google Workspace domain plus a service account
  with domain-wide delegation (scopes `admin.directory.group`,
  `admin.directory.group.member`) or the Group Administrator role.
- Until that domain is supplied, `SimulatedProvisioner` is active and every
  provisioned group is marked `simulated` in the database.

### Modification 002

Date: 2026-11-01

#### Changes
- Completed the WPF shell: navigation rail, role header, and one view per role.
- Theme split into `Tokens.xaml` (colour, type) and `Controls.xaml` (cards,
  buttons, inputs, rail navigation, hairlines).
- Domain records and view-model row types added.
- In-memory `Workspace` provides four developers, four groups, four campaigns,
  ten testers, seats, reports and an audit trail.
- Developer view: eligibility metrics, 15-cell seat meter, roster, reports,
  group address with copy, opt-in link, rule panel.
- Tester view: seat budget, open campaigns with join, own campaigns, report form.
- Admin view: counts, group table with sync state, campaign table, audit trail.
- Build succeeds for `net8.0-windows` with 0 warnings, 0 errors.
- Published pipeline script for `win-x86` and `win-x64`; Inno Setup script with
  a per-architecture `Arch` define and stable installer names.
- Brand assets generated by `tools/make_brand.py`: 1024 logo, 512 / 256 / 114
  icons, and a multi-size `.ico` wired into the executable.
- `medial_support.txt`, `.gitignore`, and a local Git repository on `main`.

#### Files / Components
- `src/TesterLoop.Desktop/Theme/`, `Views/`, `ViewModels/`, `Core/`
- `installer/TesterLoop.iss`, `scripts/publish.ps1`, `scripts/build-installers.ps1`
- `tools/make_brand.py`, `media/`

#### Important Notes
- Skills are *not* used; the app is plain WPF with MVVM and no third-party
  packages, which keeps both architectures easy to publish self-contained.
- Deviation recorded: records that form one cohesive group live in a single file
  (`Core/Models/Domain.cs`, `ViewModels/Rows.cs`) instead of one type per file.
  Both files stay well under 300 lines; the rule exists to limit file size.
- Blockers still open: no Google Workspace domain, so `SimulatedProvisioner`
  remains the only path; Inno Setup 6 is not installed, so installers are scripted
  but not compiled; the running window has not been visually verified because
  screen access was not granted.

### Modification 003

Date: 2026-11-01

#### Changes
- Project moved to `E:\AIprojects\Safety App\Close Testers` at the owner's
  request. This is now the canonical working folder for source, tools and builds.
- Rebuilt from the new root: Release build succeeds, 0 warnings, 0 errors.
- Published both architectures self-contained:
  - `build\win-x86\TesterLoop.exe` - PE machine `0x14c` (x86), 242 files
  - `build\win-x64\TesterLoop.exe` - PE machine `0x8664` (x64), 242 files

#### Files / Components
- Entire project tree; `.tools\dotnet-sdk` (SDK 8.0.427) moved with it.
- `build\win-x86`, `build\win-x64`

#### Important Notes
- The first copy of `.tools` was incomplete (robocopy skipped a nested SDK folder),
  which surfaced as `MSB4019: Microsoft.Build.Tasks.Git.props not found`. Re-running
  robocopy over `.tools` repaired it; builds are green again.
- The previous copy under the task workspace folder is left untouched as a backup.
- `E:\AIprojects\AI Agent` remains unwritable; the owner's newer instruction
  supersedes it, so downloads and build output go under `Close Testers`.

### Modification 004

Date: 2026-11-01

#### Changes
- Located the existing Inno Setup 6.7.3 compiler at
  `E:\AIprojects\AI Agent\InnoSetup\ISCC.exe` (found through the uninstall
  registry key, not a default Program Files path).
- `scripts/build-installers.ps1` now searches that location and verifies
  `build\win-<arch>\TesterLoop.exe` before compiling.
- Installer output moved into the per-architecture folders so the app and its
  installer sit together: `OutputDir=..\build\win-{#Arch}`.
- Removed the empty `ArchitecturesInstallIn64BitMode=` directive on the x86 pass
  by moving each directive into its own preprocessor branch.
- Compiled both installers:
  - `build\win-x86\TesterLoop-Setup-x86.exe` - 42.3 MB
  - `build\win-x64\TesterLoop-Setup-x64.exe` - 47.0 MB

#### Files / Components
- `installer/TesterLoop.iss`, `scripts/build-installers.ps1`, `build\win-x86`,
  `build\win-x64`

#### Important Notes
- Stable installer names are used, so the in-app updater can rely on
  `TesterLoop-Setup-x86.exe` and `TesterLoop-Setup-x64.exe` never changing name.
- The installers are not code-signed. Windows SmartScreen will warn on first run
  until a signing certificate is supplied.
- Installers have not been run end to end; that needs interactive approval on the
  owner's desktop.

### Modification 005

Date: 2026-11-01

#### Changes
- Launched both published builds and inspected the live window.
  - `build\win-x64\TesterLoop.exe` (pid 10344) and `build\win-x86\TesterLoop.exe`
    (pid 13392) both start and render the Developer view.
  - Verified from the accessibility tree: rail (Developer/Tester/Admin, DEMO DATA
    chip, v0.1.0 footer), metrics `12 / 12`, `19 d`, `13 / 15`, the 15-cell seat
    meter with 12 opted + 1 joined + 2 empty, 13 roster rows, 2 reports, group
    address `tl-northbeam-studio-111111@testerloop.dev`, opt-in link, and the rule
    panel.
- Removed the duplicate and x86 test processes; one x64 window left open.

#### Files / Components
- `build\win-x86`, `build\win-x64` (no source changes)

#### Important Notes
- No runtime binding errors or crashes observed on either architecture.
- The screenshot itself could not be assessed (no image input on this model), so
  the visual pass rests on the accessibility tree plus the owner's own view of the
  open window. Pixel-level design review is still outstanding.

### Modification 006

Date: 2026-11-01

#### Changes
- Reworked the shell around sign-in. Developer, tester and staff are three
  different people, so the app now opens on a sign-in screen and the signed-in
  account decides which workspace is shown. There is no role switcher any more.
- Added Core/Data/Directory.cs: the three demonstration accounts, with passwords
  stored as SHA-256 hashes and compared in constant time.
  - ops@northbeam.studio -> developer (Northbeam Studio)
  - mara.silva@gmail.com -> tester
  - dmin@testerloop.dev -> operations staff
  - shared demo password: demo1234
- Added LoginViewModel, AppViewModel (switches login <-> shell) and
  ShellViewModel (rail with the signed-in identity, sign-out, role header).
- Added Views/LoginView (brand panel plus credentials, inline error, demo-account
  shortcuts) and Views/ShellView (the rail, header and content host moved out of
  MainWindow).
- MainWindow is now a thin host bound to AppViewModel.Current.
- DeveloperViewModel takes the signed-in developer's id and resolves that
  developer's own campaign and group; TesterViewModel takes the tester id.
  Both fail loudly if the account has no matching record.
- Removed MainViewModel and the RoleItem record.
- Version bumped to 0.2.0.
- Installer fix: the [Files] entry now excludes `TesterLoop-Setup-*.exe`, which
  had been pulling the previous installer into the new one and locking the output
  ("process cannot access the file"). Both installers rebuilt cleanly.

#### Files / Components
- src/TesterLoop.Desktop/Core/Data/Directory.cs (new)
- src/TesterLoop.Desktop/ViewModels/{AppViewModel,LoginViewModel,ShellViewModel}.cs (new)
- src/TesterLoop.Desktop/Views/{LoginView,ShellView}.xaml(.cs) (new)
- src/TesterLoop.Desktop/MainWindow.xaml, App.xaml, App.xaml.cs
- src/TesterLoop.Desktop/Theme/Controls.xaml (PasswordBox style)
- src/TesterLoop.Desktop/Core/Models/Domain.cs, ViewModels/{Developer,Tester}ViewModel.cs
- installer/TesterLoop.iss, uild/win-x86, uild/win-x64

#### Important Notes
- Verified by driving the running app: all three accounts sign in and land on the
  correct workspace - developer shows Northbeam's campaign (12/12, 19 d, 13/15),
  tester shows Amara's bench with open campaigns, staff shows Operations.
- The demo directory is a stand-in for Supabase Auth with Google sign-in. It does
  not hash with a salt or store a real session; it must not ship as production
  authentication.
- Sign-in currently runs against local demo accounts, so every tester and developer
  on one machine shares the same seeded data set.

### Modification 007

Date: 2026-11-01

#### Changes
- Removed automatic and simulated Google Group provisioning. A consumer
  `@gmail.com` group has no API, and Google refuses sign-in from the controlled
  browser, so group creation is now a deliberate operations task.
- New project lifecycle: `Pending` -> `AwaitingLink` -> `Live` (plus `AtRisk`,
  `Passed`, `Cancelled`). `Provisioning` and `ProvisioningFailed` are gone.
- Developer creates a project with one tap. It stays `Pending` until staff attach
  a Google Group address and activate it. The developer then sees the address,
  copies it into Play Console, and saves the closed-test link. Saving a valid
  `https://play.google.com/apps/testing/...` link promotes the project to `Live`
  and testers can join.
- Added campaign mutations with explicit validation in `Workspace.Campaigns.cs`.
  `CreateCampaign`, `AttachGroup`, `SetOptInUrl` and `TryJoin` reject bad input,
  duplicate group addresses and full groups. A dropped seat is reused instead of
  colliding with a full seat map. Invalid input throws a plain-language error;
  nothing is half-applied. Every step writes an audit row
  (`campaign.created`, `group.attached`, `campaign.link_saved`, `seat.joined`).
- Added `Core/LinkLauncher.cs`. Only https Play testing links are opened, via the
  default browser; other schemes and hosts are refused.
- Rebuilt the developer view: project list, next-step panel, 15-cell seat map,
  roster, reports, group card with copy, closed-test link card with a suggested
  URL, and a new-project form.
- Rebuilt the tester view: available projects with per-project Join, a post-join
  banner with the Play link, own campaigns with per-row Open, report form.
- Rebuilt the admin view around a "Projects waiting for a Google Group" queue:
  staff paste the group address and activate. The group table is labelled manual
  sync; the old simulated reconcile label is gone.
- Version bumped to 0.3.0 in the project, installer and shell footer.

#### Files / Components
- `src/TesterLoop.Desktop/Core/Models/Domain.cs`
- `src/TesterLoop.Desktop/Core/Data/Workspace.cs`,
  `src/TesterLoop.Desktop/Core/Data/Workspace.Campaigns.cs` (new partial)
- `src/TesterLoop.Desktop/Core/LinkLauncher.cs`
- `src/TesterLoop.Desktop/ViewModels/DeveloperViewModel.cs`,
  `DeveloperViewModel.Detail.cs`, `TesterViewModel.cs`, `AdminViewModel.cs`,
  `PendingProjectRow.cs`, `Rows.cs`, `ShellViewModel.cs`
- `src/TesterLoop.Desktop/Views/DeveloperView.xaml`, `TesterView.xaml`,
  `AdminView.xaml`, `ShellView.xaml`
- `installer/TesterLoop.iss`, `src/TesterLoop.Desktop/TesterLoop.Desktop.csproj`
- `build/win-x86`, `build/win-x64`

#### Important Notes
- The project record remains in memory only. Relaunching the app restores the
  seeded demo data, so a created project disappears on exit until Supabase is
  connected.
- Group membership is not read back from Google; staff check it by hand. The UI
  says "manual sync" everywhere it would otherwise imply a verified state.
- Verification: Release build 0 warnings / 0 errors; an in-process harness drove
  create -> attach -> link -> join and the rejection paths (bad email, non-Play
  link, duplicate join) with all checks passing; all four views were loaded and
  laid out with no XAML or binding-path errors. There was no visual or
  accessibility-tree review this round, and the installers were not run.
- Installers rebuilt for both architectures:
  `build/win-x86/TesterLoop-Setup-x86.exe` (44,375,845 bytes) and
  `build/win-x64/TesterLoop-Setup-x64.exe` (49,253,943 bytes). Both report
  version 0.3.0.0; PE machines are 0x14C and 0x8664.
- `DeveloperView.xaml` is 467 lines, above the 300-line guideline. Its item
  templates are specific to that screen; splitting them into a resource dictionary
  is deferred. Every C# file stays under 300 lines.
- Still blocked: no Google Workspace domain (only matters for future automation),
  no Supabase project, no code-signing certificate.

### Modification 008

Date: 2026-11-01

#### Changes
- Connected TesterLoop to the live Supabase project
  `https://omlhddzyitzjbcgrxvbn.supabase.co` with the publishable key
  `sb_publishable_muvojumpOQ52sZirZKA4Lw_6BcNVb8G`. The key is client-safe;
  no service-role key is shipped.
- Replaced the demo directory and in-memory workspace with real email/password
  authentication and PostgREST RPC reads and writes.
- Added open developer and tester signup, plus OTP-based password recovery.
  The login screen no longer exposes demo accounts.
- Added the full greenfield SQL set: schema, RLS, signup trigger, `whoami`,
  developer/tester/admin read models, campaign mutations, tester actions and
  admin bootstrap. Direct table access is revoked; all client access goes through
  checked RPC functions.
- Added the 15-seat / 12-tester / 14-day rule in SQL. The 12th-oldest opt-in is
  the threshold; opt-outs free the seat and reset that tester's clock.
- Added project lifecycle `pending` -> `awaiting_link` -> `live`, with
  `at_risk`, `passed` and `cancelled`. Operations still creates Google Groups by
  hand and attaches the address.
- Reworked all three workspaces against live RPC JSON:
  - Developer: project list, next-step panel, 15-cell seat map, roster, reports,
    group card, Play link card, create-project form.
  - Tester: seat budget, open projects, join, opt-in/opt-out, Play link, reports.
  - Admin: pending queue, group attach, manual-sync group table, campaign table,
    audit trail.
- Added `Core/AppConfig.cs`, `Core/AsyncRelayCommand.cs`,
  `Core/AsyncRelayCommandOfT.cs`, `Core/Data/Contracts.cs`,
  `Core/Data/LiveSessionStore.cs`, `Core/Data/SupabaseService.cs`.
- Added a case-insensitive unique tester Google-email index and a friendly signup
  rejection when that account is already linked to another tester.
- Split Supabase transport into `SupabaseService.Transport.cs`; request timeouts,
  network failures and malformed responses now surface as inline errors instead
  of escaping an async command.
- Sign-out always clears the local session and returns to the login screen.
- Removed unused prototype domain records and split developer helpers so every
  C# file stays under 300 lines.
- Version bumped to `0.4.0` in the application, installer and shell footer.

#### Files / Components
- `sql/schema/001_init.sql`
- `sql/policies/002_rls.sql`
- `sql/functions/003_auth.sql`, `004_queries.sql`, `005_mutations.sql`,
  `006_tester_actions.sql`
- `sql/seed/007_admin_bootstrap.sql`
- `src/TesterLoop.Desktop/Core/AppConfig.cs`
- `src/TesterLoop.Desktop/Core/Data/SupabaseService.cs`,
  `SupabaseService.Transport.cs`, `Contracts.cs`, `LiveSessionStore.cs`
- `src/TesterLoop.Desktop/Core/Models/Domain.cs`
- `src/TesterLoop.Desktop/ViewModels/AppViewModel.cs`, `LoginViewModel.cs`,
  `SignUpViewModel.cs`, `ResetPasswordViewModel.cs`, `ShellViewModel.cs`,
  `DeveloperViewModel.cs`, `DeveloperViewModel.Detail.cs`,
  `TesterViewModel.cs`, `TesterViewModel.Actions.cs`, `AdminViewModel.cs`,
  `Rows.cs`
- `src/TesterLoop.Desktop/Views/LoginView.xaml`, `SignUpView.xaml`,
  `ResetPasswordView.xaml`, `DeveloperView.xaml`, `TesterView.xaml`,
  `AdminView.xaml`, `ShellView.xaml`, `App.xaml`
- Removed: `Core/Data/Directory.cs`, `Core/Data/Workspace.cs`,
  `Core/Data/Workspace.Campaigns.cs`, `ViewModels/PendingProjectRow.cs`
- `installer/TesterLoop.iss`, `src/TesterLoop.Desktop/TesterLoop.Desktop.csproj`

#### Important Notes
- Supabase auth settings assumed for this release: email provider on, Google
  provider off, signup on, `mailer_autoconfirm=true`.
- The Reset Password email template must contain `{{ .Token }}` so the app can
  verify the OTP. The default link-only template will not work.
- Deployment order is `001` -> `002` -> `003` -> `004` -> `005` -> `006` ->
  `007`. The SQL has not been applied by the agent and must be run by the owner
  in the Supabase SQL editor.
- First admin: create the auth user in Dashboard -> Authentication -> Users, then
  run `select public.bootstrap_admin('admin@testerloop.dev');` as `postgres`.
  Dashboard-created users without a role are intentionally left without a
  profile so they cannot become admins by accident.
- Static review fixes: admin-created auth users no longer fail the signup
  trigger; re-joining after opt-out now picks a free seat instead of colliding
  with a reused seat number; package duplicates are case-insensitive; new
  functions are not executable by `public` by default; bootstrap checks
  `session_user`, not the security-definer `current_user`.
- Additional review fixes before release: tester Google emails are unique
  case-insensitively at both trigger and index level; refresh requires a valid
  role; RPC timeouts, network faults and malformed JSON are mapped to inline
  errors; sign-out always returns to login even if the remote call fails.
- Verification: Release build 0 warnings / 0 errors. Published
  `build/win-x86/TesterLoop.exe` (141,824 bytes, PE 0x14C) and
  `build/win-x64/TesterLoop.exe` (172,544 bytes, PE 0x8664), both version
  `0.4.0.0`. Both launch and show the login view. Installers recompiled:
  `TesterLoop-Setup-x86.exe` (45,137,170 bytes) and
  `TesterLoop-Setup-x64.exe` (50,027,192 bytes), product version `0.4.0`.
- The live sign-in screen was driven through UI Automation: both architectures
  render it, and submitting empty credentials shows the expected inline
  "Enter your email and password." message without crashing.
- All C# source files are now under 300 lines. `DeveloperView.xaml` (439 lines)
  and `TesterView.xaml` (305 lines) remain above the guideline; template
  extraction is still deferred.
- Supabase auth health endpoint responds (`GoTrue v2.197.0`). REST still returns
  `PGRST205` for `public.campaigns`, confirming the schema has not been deployed.
- Not verified: signup, sign-in, reset, RPC dashboards, join/opt-in, reports,
  admin attach, or installers end to end. These need the SQL deployment and the
  reset template first.
- Open risks: signup has no billing or invite gate; built-in email has strict
  rate limits until SMTP is configured; installers are unsigned, so SmartScreen
  will warn.
- The old `supabase/functions/provision-group` draft remains for future
  Workspace-based automation. It is not deployed and is not used by `0.4.0`.

### Modification 009

Date: 2026-11-01

#### Changes
- Diagnosed the reported create-account failure: the live Supabase project has no
  deployed schema. `whoami`, `developer_dashboard` and `refresh_campaign_states`
  still return `404 PGRST202`, and `public.campaigns` returns `404 PGRST205`.
- Added a schema preflight to signup. `EnsureSchemaAsync` calls `rpc/whoami` before
  any auth user is created, so a missing deployment now shows
  "TesterLoop's database setup is incomplete..." inline instead of leaving an
  orphan auth account.
- Added `public.claim_profile()` in `003_auth.sql`, granted in `007`. If `whoami`
  reports an auth user with no TesterLoop profile, the client calls `claim_profile`
  once and retries, repairing accounts created before the trigger existed.
- Removed the separate Google email field from signup. The sign-in email is now
  also the Google address added to the Play tester list; the signup trigger
  defaults a missing `google_email` to the auth email. Signup copy says this
  explicitly.
- Changed `MainWindow` to open `WindowState="Maximized"` with minimum size
  `1000x600`. This is a maximized window, not borderless kiosk mode.
- Version bumped to `0.4.1` in the application, project, installer and marketing
  file.

#### Files / Components
- `sql/functions/003_auth.sql`, `sql/seed/007_admin_bootstrap.sql`
- `src/TesterLoop.Desktop/Core/Data/SupabaseService.cs`,
  `SupabaseService.Transport.cs`
- `src/TesterLoop.Desktop/ViewModels/SignUpViewModel.cs`
- `src/TesterLoop.Desktop/Views/SignUpView.xaml`
- `src/TesterLoop.Desktop/MainWindow.xaml`
- `src/TesterLoop.Desktop/Core/AppConfig.cs`,
  `src/TesterLoop.Desktop/TesterLoop.Desktop.csproj`
- `installer/TesterLoop.iss`, `medial_support.txt`

#### Important Notes
- Deployment order is unchanged: `001` -> `002` -> `003` -> `004` -> `005` ->
  `006` -> `007`. `007` now ends with `notify pgrst, 'reload schema';`; rerun
  `007` after the other files, or issue the `NOTIFY` separately, so PostgREST
  picks up the new tables and functions.
- An auth account created by an earlier failed signup has no profile. After the
  SQL is deployed, signing in calls `claim_profile` and repairs it; alternatively
  delete that auth user in the Dashboard and sign up again.
- The preflight treats `404` as missing schema. `401`/`403` are expected for an
  anonymous `whoami` call after deployment and do not block signup.
- Verification: Release build 0 warnings / 0 errors. Published
  `build/win-x86/TesterLoop.exe` (141,824 bytes, PE `0x14C`) and
  `build/win-x64/TesterLoop.exe` (172,544 bytes, PE `0x8664`), both file version
  `0.4.1.0`, product version `0.4.1`. Installers recompiled:
  `build/win-x86/TesterLoop-Setup-x86.exe` (45,137,542 bytes) and
  `build/win-x64/TesterLoop-Setup-x64.exe` (50,029,456 bytes), both product
  version `0.4.1`.
- UI Automation on both architectures: window rect `-7,-7,1543,831`, maximized
  `True`; signup shows 4 input fields and no Google email field; submitting a
  valid form against the undeployed project shows the schema-incomplete message
  and creates no auth user.
- Security audit: only the publishable key is in the client; no service-role key,
  secret or token is logged. `LinkLauncher` accepts only
  `https://play.google.com/apps/testing/...`. SQL revokes table access from `anon`
  and `authenticated`, grants RPC execution only to `authenticated`, and keeps
  `bootstrap_admin` Dashboard-only.
- Not verified: live signup, sign-in, reset, dashboards, join/opt-in, reports,
  admin attach, or installers end to end. These require the SQL deployment and
  the reset template.
- The 0.4.1 installers have not been run. They remain unsigned.

### Modification 010

Date: 2026-11-01

#### Changes
- Fixed the tester signup crash. `System.Windows.Documents.Run.Text` binds two-way
  by default, so `<Run Text="{Binding Email}" />` and the `Region` run in
  `TesterView` tried to write to read-only view-model properties. WPF threw
  `InvalidOperationException` during layout and the process terminated.
- Added `Mode=OneWay` to every bound `Run` in `TesterView`, `DeveloperView` and
  `AdminView` (15 bindings). Display-only text no longer attempts to write back.
- The email/region separator line in `TesterView` was replaced with the `&#183;`
  entity so the XAML no longer carries a corrupted glyph.
- Version bumped to `0.4.2` in the application, project, installer and marketing
  file.

#### Files / Components
- `src/TesterLoop.Desktop/Views/TesterView.xaml`
- `src/TesterLoop.Desktop/Views/DeveloperView.xaml`
- `src/TesterLoop.Desktop/Views/AdminView.xaml`
- `src/TesterLoop.Desktop/Core/AppConfig.cs`
- `src/TesterLoop.Desktop/TesterLoop.Desktop.csproj`
- `installer/TesterLoop.iss`, `medial_support.txt`

#### Important Notes
- Root cause evidence: Windows Application log, `.NET Runtime` event 1026,
  `TesterLoop.exe` 0.4.1.0, "A TwoWay or OneWayToSource binding cannot work on the
  read-only property 'Email' of type 'TesterLoop.Desktop.ViewModels.TesterViewModel'."
- The live Supabase schema is now deployed. Anonymous calls to `whoami`,
  `claim_profile`, `refresh_campaign_states` and the three dashboards return `401`
  (function exists, not granted to `anon`) instead of `404 PGRST202`.
- End-to-end verification: a disposable tester account was created through the
  UI, the tester workspace rendered and the process stayed open. Signing in with
  that account also reached the tester workspace on both x86 and x64. The account
  is `qa.smoke.1101231128@example.com`; delete it from Supabase when convenient.
- Verification: Release build 0 warnings / 0 errors. Published
  `build/win-x86/TesterLoop.exe` (141,824 bytes, PE `0x14C`) and
  `build/win-x64/TesterLoop.exe` (172,544 bytes, PE `0x8664`), both file version
  `0.4.2.0`, product version `0.4.2`. Installers recompiled:
  `build/win-x86/TesterLoop-Setup-x86.exe` (45,137,706 bytes) and
  `build/win-x64/TesterLoop-Setup-x64.exe` (50,028,465 bytes), product version
  `0.4.2`.
- No new security surface: no secrets added, no new network endpoints, and the
  change only removes two-way binding on read-only display properties.
- The 0.4.2 installers have not been run end to end and remain unsigned.

### Modification 011

Date: 2026-11-01

#### Changes
- Removed the per-tester project budget. A tester may now hold seats in any
  number of campaigns; only each campaign is capped at 15 testers.
- `join_campaign` no longer reads or compares `testers.max_seats`. The campaign
  advisory lock, the 15-seat check, duplicate-join rejection and dropped-seat
  reuse still apply.
- Removed `max_seats` from the greenfield tester table and from
  `tester_dashboard` JSON.
- Added `sql/migrations/008_unlimited_tester_projects.sql` for the live project.
  It replaces `join_campaign` and `tester_dashboard`, drops the unused
  `testers.max_seats` column, and reloads the PostgREST schema cache.
- Removed `MaxSeats` from `TesterDto`, `_maxSeats` / `_seatsUsed` from
  `TesterViewModel`, and the `SeatsLabel` / `SeatsHint` properties.
- Replaced the tester `SEAT BUDGET` card with `PROJECTS JOINED` and a
  "No limit on projects" caption.
- Version bumped to `0.4.3` in the application, project, installer and marketing
  file.

#### Files / Components
- `sql/schema/001_init.sql`
- `sql/functions/004_queries.sql`, `sql/functions/006_tester_actions.sql`
- `sql/migrations/008_unlimited_tester_projects.sql` (new)
- `src/TesterLoop.Desktop/Core/Data/Contracts.cs`
- `src/TesterLoop.Desktop/ViewModels/TesterViewModel.cs`
- `src/TesterLoop.Desktop/Views/TesterView.xaml`
- `src/TesterLoop.Desktop/Core/AppConfig.cs`,
  `src/TesterLoop.Desktop/TesterLoop.Desktop.csproj`
- `installer/TesterLoop.iss`, `AGENTS_PLAN.md`, `medial_support.txt`

#### Important Notes
- Deployment: the live project already has `001`-`007`; run
  `sql/migrations/008_unlimited_tester_projects.sql` once in the Supabase SQL
  editor. A fresh greenfield install can run `001`-`007`; `008` is safe there too
  because it uses `drop column if exists`.
- Until `008` runs, the live `tester_dashboard` still returns `max_seats`. The
  `0.4.3` client no longer has that DTO property, so it ignores the extra field.
  The old 15-seat personal budget check remains active in the database until
  `008` replaces `join_campaign`.
- A tester can still join a campaign only once, and an opt-out frees that
  campaign's seat and resets only that tester's clock for that campaign.
- Verification: Release build 0 warnings / 0 errors. Published
  `build/win-x86/TesterLoop.exe` (141,824 bytes, PE `0x14C`) and
  `build/win-x64/TesterLoop.exe` (172,544 bytes, PE `0x8664`), both file version
  `0.4.3.0`, product version `0.4.3`. Installers recompiled:
  `build/win-x86/TesterLoop-Setup-x86.exe` (45,137,621 bytes) and
  `build/win-x64/TesterLoop-Setup-x64.exe` (50,028,038 bytes), product version
  `0.4.3`.
- Both published executables launch, show a responsive TesterLoop window and
  were closed after the check.
- Not verified: the live tester workspace and unlimited joins, because `008` has
  not been applied. Installers still have not been run end to end and remain
  unsigned.
- No new security surface: no secrets or endpoints were added. The migration only
  replaces two existing `security definer` functions, removes an unused column and
  keeps the existing RPC grants.

### Modification 012

Date: 2026-11-02

#### Changes
- Split the product into two Windows applications that share one Supabase
  backend:
  - `TesterLoop` for developers and testers;
  - `TesterLoop Admin` for operations staff.
- Extracted shared code into `TesterLoop.Shared`: Supabase transport, auth session
  store, DTOs, account models, commands, theme dictionaries and `ShellView`.
- Removed the admin workspace from the main app. Admin accounts are refused there
  with a message to use `TesterLoop Admin`.
- Added `TesterLoop.Admin` with an operations-only sign-in, the existing pending
  queue, group attach, manual-sync groups, campaign table, counts and audit trail.
  There is no public signup in the admin app.
- Added a separate admin installer per architecture with stable names
  `TesterLoop-Admin-Setup-x86.exe` and `TesterLoop-Admin-Setup-x64.exe`.
- Updated publish and installer scripts to build both applications for x86 and x64.
- Version bumped to `0.5.0` in the shared config, both projects, both installers
  and the marketing file.

#### Files / Components
- `src/TesterLoop.Shared/` (new): `Core/`, `Theme/`, `Views/ShellView.xaml`
- `src/TesterLoop.Admin/` (new): app, window, login view, admin view and view-models
- `src/TesterLoop.Desktop/App.xaml`, `AppViewModel.cs`, `ShellViewModel.cs`,
  `Rows.cs`, `LoginView.xaml`, `TesterLoop.Desktop.csproj`
- `src/TesterLoop.Admin/TesterLoop.Admin.csproj`
- `TesterLoop.sln` (new): shared library, main app and admin app
- `installer/TesterLoop.iss`, `installer/TesterLoop.Admin.iss` (new)
- `scripts/publish.ps1`, `scripts/build-installers.ps1`
- `AGENTS.md`, `AGENTS_PLAN.md`, `medial_support.txt`

#### Important Notes
- Both apps still require an authenticated Supabase account. The admin app's
  minimal sign-in is deliberate; removing it would require an embedded privileged
  token or anonymous admin RPCs, both of which are rejected security risks.
- The main app rejects admin accounts after sign-in and signs the session out.
  The admin app rejects developer and tester accounts the same way.
- Admin RPC authorisation is unchanged and still enforced server-side by RLS and
  `security definer` checks.
- Verification: both projects build with 0 warnings / 0 errors. Published
  `build/win-x86/TesterLoop.exe` and `build/admin-win-x86/TesterLoopAdmin.exe`
  (141,824 bytes each, PE `0x14C`), and
  `build/win-x64/TesterLoop.exe` and `build/admin-win-x64/TesterLoopAdmin.exe`
  (172,544 bytes each, PE `0x8664`); both file version `0.5.0.0`, product `0.5.0`.
- Installers compiled: main `45,137,026` / `50,026,583` bytes and admin
  `45,045,650` / `49,919,593` bytes for x86 / x64; product version `0.5.0`.
- Launch checks: all four published executables start and show responsive
  windows. UI Automation on `TesterLoopAdmin` shows the operations sign-in copy,
  and submitting empty credentials shows
  "Enter your operations email and password."
- Not verified: live admin sign-in and dashboard because no operations account was
  supplied, main-app rejection of a live admin account, migration `008`, and the
  installers end to end. Installers remain unsigned.

### Modification 013

Date: 2026-11-02

#### Changes
- Expanded TesterLoop Admin from one operations screen into seven tabs:
  `Operations`, `Campaigns`, `Developers`, `Clients`, `Feedback`, `Audit Trail`
  and `Profile`. `Clients` is the tester roster; the other tabs are read-only
  views over the admin dashboard payload.
- Added editable admin profile (display name and operations note) backed by a new
  `update_admin_profile` RPC. The signed-in email stays read-only. Saving raises
  `ProfileSaved` so the shell header identity and initials refresh.
- Extended `admin_dashboard()` to return campaign `package_name`, developer
  accounts, tester accounts, tester feedback and the current admin profile.
- Made Play link validation shared and stricter. Both accepted forms now pass:
  `https://play.google.com/apps/testing/<package>` and
  `https://play.google.com/store/apps/details?id=<package>`. Non-https,
  non-`play.google.com`, non-443, userinfo, invalid package IDs and links over
  500 characters are rejected in the client and in SQL.
- The developer Play link card now shows both example forms.
- Added live migrations `009_admin_tabs_profile.sql` and
  `010_play_link_validation.sql`.
- Version bumped to `0.5.1`.

#### Files / Components
- `src/TesterLoop.Admin/Views/AdminView.xaml`,
  `AdminCampaignsView`, `AdminDevelopersView`, `AdminClientsView`,
  `AdminFeedbackView`, `AdminProfileView` (new views and code-behind)
- `src/TesterLoop.Admin/ViewModels/AdminViewModel.cs`,
  `AdminViewModel.Tabs.cs`, `AdminViewModel.Profile.cs` (new),
  `AdminShellViewModel.cs`, `AdminRows.cs`
- `src/TesterLoop.Shared/Core/PlayLink.cs` (new),
  `Core/Data/Contracts.cs`, `Core/Data/SupabaseService.cs`,
  `Core/AppConfig.cs`
- `src/TesterLoop.Desktop/Core/LinkLauncher.cs`,
  `ViewModels/DeveloperViewModel.cs`, `ViewModels/DeveloperViewModel.Detail.cs`,
  `Views/DeveloperView.xaml`
- `sql/functions/004_queries.sql`, `sql/functions/005_mutations.sql`,
  `sql/seed/007_admin_bootstrap.sql`
- `sql/migrations/009_admin_tabs_profile.sql`,
  `sql/migrations/010_play_link_validation.sql` (new)
- `src/TesterLoop.Desktop/TesterLoop.Desktop.csproj`,
  `src/TesterLoop.Admin/TesterLoop.Admin.csproj`,
  `installer/TesterLoop.iss`, `installer/TesterLoop.Admin.iss`
- `AGENTS.md`, `AGENTS_PLAN.md`, `medial_support.txt`

#### Important Notes
- `SaveProfileCommand` is assigned in the `AdminViewModel` constructor, not a
  field initializer, because the command references another instance field
  (`CS0236` otherwise).
- Admin tabs are populated from the same single `admin_dashboard` call; no new
  table access was opened to the client. RLS and `security definer` checks still
  enforce authorisation.
- Play link validation is duplicated deliberately: the shared client validator
  gives immediate feedback, and the SQL function remains the authority so a
  tampered client cannot store a non-Play URL.
- Verification: Release build 0 warnings / 0 errors. A temporary harness exercised
  the Play validator with 13 accepted/rejected cases (`PASS 13/13`), and a WPF
  harness loaded `AdminView` with all seven tabs and no XAML or binding-path
  errors.
- Published and packaged `0.5.1` for both apps and both architectures:
  - `build/win-x86/TesterLoop.exe` 141,824 bytes, PE `0x14C`
  - `build/win-x64/TesterLoop.exe` 172,544 bytes, PE `0x8664`
  - `build/admin-win-x86/TesterLoopAdmin.exe` 141,824 bytes, PE `0x14C`
  - `build/admin-win-x64/TesterLoopAdmin.exe` 172,544 bytes, PE `0x8664`
  - `build/win-x86/TesterLoop-Setup-x86.exe` 45,139,698 bytes
  - `build/win-x64/TesterLoop-Setup-x64.exe` 50,030,354 bytes
  - `build/admin-win-x86/TesterLoop-Admin-Setup-x86.exe` 45,054,022 bytes
  - `build/admin-win-x64/TesterLoop-Admin-Setup-x64.exe` 49,928,945 bytes
  All four executables report file version `0.5.1.0`; all four installers report
  product version `0.5.1`.
- Launch checks: all four published executables start, keep responsive windows
  titled `TesterLoop` / `TesterLoop Admin`, and were stopped after the check.
- Deployment: run `008`, then `009`, then `010` in the Supabase SQL editor.
  `009` creates `update_admin_profile`; `010` replaces `save_play_link`. Both
  reload the PostgREST schema cache.
- Not verified: live admin tabs/profile save and the store-details link, because
  `009` / `010` and an operations account are still pending. The installers have
  not been run end to end and remain unsigned.
- Security: no secrets or endpoints were added. The new RPC is admin-only via the
  existing `security definer` role check and is granted only to `authenticated`;
  both Play forms stay restricted to `play.google.com` over TLS.

### Modification 014

Date: 2026-11-02

#### Changes
- Renamed the admin `Clients` tab to `Testers`, since that roster is testers, not
  paying clients.
  - `AdminClientsView.xaml` / `.xaml.cs` -> `AdminTestersView` (files, class and
    XAML root renamed).
  - `ClientRow` -> `TesterRow`; `Clients` -> `Testers`; `ClientTabLabel` ->
    `TesterTabLabel`; `HasClients` -> `HasTesters`.
  - `AdminView.xaml` header is now `Testers` and hosts `AdminTestersView`.
  - Admin shell subtitle now reads "Campaigns, testers, feedback and the audit
    trail".
- Added a database-upgrade notice to `AdminViewModel.LoadAsync`. When the live
  `admin_dashboard()` payload has no `developers`, `testers` or `profile`, the
  admin tabs set `Error` to "The admin tabs need a database update. Run
  sql/migrations/009_admin_tabs_profile.sql in Supabase, then press Refresh."
  This turns a silent empty tab into an actionable message.
- Diagnosed two owner reports without changing behaviour:
  - A Play store-details link was rejected with "The link must be start with
    https://play.google.com/apps/testng/". That text is not in the 0.5.x source
    or the current SQL, so the running client or live `save_play_link` predates
    `0.5.1` / `010`. The current message is "The link must be a Google Play
    testing link or store details link.", and both link forms are accepted.
  - Empty Developers and Testers tabs are consistent with `009` not being
    applied; the old `admin_dashboard()` does not return those keys.
- Version bumped to `0.5.2` in `AppConfig`, both projects and both installers.
- Documented the deploy order still owed by the owner: `008` -> `009` -> `010`.

#### Files / Components
- `src/TesterLoop.Admin/Views/AdminTestersView.xaml`, `.xaml.cs` (renamed)
- `src/TesterLoop.Admin/Views/AdminView.xaml`
- `src/TesterLoop.Admin/ViewModels/AdminViewModel.cs`,
  `AdminViewModel.Tabs.cs`, `AdminRows.cs`, `AdminShellViewModel.cs`
- `src/TesterLoop.Shared/Core/AppConfig.cs`
- `src/TesterLoop.Desktop/TesterLoop.Desktop.csproj`,
  `src/TesterLoop.Admin/TesterLoop.Admin.csproj`
- `installer/TesterLoop.iss`, `installer/TesterLoop.Admin.iss`
- `AGENTS.md`, `AGENTS_PLAN.md`, `medial_support.txt`

#### Important Notes
- Verification: Release build 0 warnings / 0 errors. Published and packaged
  `0.5.2` for both apps and both architectures:
  - `build/win-x86/TesterLoop.exe` 141,824 bytes, PE `0x14C`
  - `build/win-x64/TesterLoop.exe` 172,544 bytes, PE `0x8664`
  - `build/admin-win-x86/TesterLoopAdmin.exe` 141,824 bytes, PE `0x14C`
  - `build/admin-win-x64/TesterLoopAdmin.exe` 172,544 bytes, PE `0x8664`
  - `build/win-x86/TesterLoop-Setup-x86.exe` 45,140,069 bytes
  - `build/win-x64/TesterLoop-Setup-x64.exe` 50,030,437 bytes
  - `build/admin-win-x86/TesterLoop-Admin-Setup-x86.exe` 45,055,044 bytes
  - `build/admin-win-x64/TesterLoop-Admin-Setup-x64.exe` 49,928,942 bytes
  All four executables report file version `0.5.2.0`; all four installers report
  product version `0.5.2`.
- Launch checks: all four published executables start, keep responsive windows
  titled `TesterLoop` / `TesterLoop Admin`, and were stopped after the check.
- Not verified: live Developers/Testers tabs, profile save and the store-details
  link. All three depend on the owner running `008`, `009` and `010` in Supabase
  and on an operations account.
- No new security surface: the rename and the notice are client-side; no secrets,
  endpoints, RPC grants or validation rules changed. The installer binaries
  remain unsigned.

### Modification 015

Date: 2026-11-02

#### Changes
- The shell header now shows the signed-in role as a badge next to the email:
  `DEVELOPER`, `TESTER` or `OPERATIONS`. Added `RoleBadge` to `ShellViewModel`
  and `AdminShellViewModel` and rendered it in the shared `ShellView` header.
- Developer `YOUR PROJECTS` now lists active projects only. `passed` and
  `cancelled` projects are filtered out in `DeveloperViewModel.LoadAsync`;
  `pending`, `awaiting_link`, `live` and `at_risk` still appear so a new project
  remains visible while operations sets it up.
- Moved the `YOUR PROJECTS` card below the `NEW PROJECT` card in
  `DeveloperView.xaml`.
- Added self-service profile editing for developers and testers:
  - Developer fields: display name, company/studio, contact email and Google
    account email.
  - Tester fields: display name, Google account email, region and up to 10
    comma-separated devices.
  - Each workspace has an `Edit profile` button in its header and an inline
    profile card with `Save profile` / `Close`.
  - New RPCs `update_developer_profile` and `update_tester_profile` validate and
    persist the changes, write an audit row and keep the auth sign-in email
    read-only.
  - `developer_dashboard()` now returns `display_name`.
- Added `Core/InputChecks.cs` for shared email/device parsing and
  `DeveloperViewModel.Profile.cs` / `TesterViewModel.Profile.cs` partials.
- Version bumped to `0.5.3` in `AppConfig`, both projects and both installers.

#### Files / Components
- `src/TesterLoop.Shared/Views/ShellView.xaml`
- `src/TesterLoop.Desktop/ViewModels/ShellViewModel.cs`
- `src/TesterLoop.Admin/ViewModels/AdminShellViewModel.cs`
- `src/TesterLoop.Desktop/ViewModels/DeveloperViewModel.cs`,
  `DeveloperViewModel.Profile.cs`, `TesterViewModel.cs`,
  `TesterViewModel.Profile.cs`
- `src/TesterLoop.Desktop/Views/DeveloperView.xaml`, `TesterView.xaml`
- `src/TesterLoop.Desktop/Core/InputChecks.cs` (new)
- `src/TesterLoop.Shared/Core/Data/Contracts.cs`,
  `SupabaseService.cs`, `SupabaseService.Transport.cs`
- `sql/functions/004_queries.sql`, `sql/functions/005_mutations.sql`,
  `sql/seed/007_admin_bootstrap.sql`
- `sql/migrations/011_profile_editing.sql` (new)
- `src/TesterLoop.Shared/Core/AppConfig.cs`,
  `src/TesterLoop.Desktop/TesterLoop.Desktop.csproj`,
  `src/TesterLoop.Admin/TesterLoop.Admin.csproj`
- `installer/TesterLoop.iss`, `installer/TesterLoop.Admin.iss`
- `AGENTS.md`, `AGENTS_PLAN.md`, `medial_support.txt`

#### Important Notes
- "Active" means any state except `passed` and `cancelled`. Filtering only
  `live`/`at_risk` would hide a project as soon as a developer creates it.
- Profile edits never change the Supabase auth email. The developer contact and
  Google emails, and the tester Google email, are stored on the role tables; the
  tester Google email stays unique case-insensitively and a collision surfaces
  as "That Google account is already linked to another tester."
- SQL deployment order is now `008` -> `009` -> `010` -> `011`.
- Verification: Release build 0 warnings / 0 errors. Published and packaged
  `0.5.3` for both apps and both architectures:
  - `build/win-x86/TesterLoop.exe` 141,824 bytes, PE `0x14C`
  - `build/win-x64/TesterLoop.exe` 172,544 bytes, PE `0x8664`
  - `build/admin-win-x86/TesterLoopAdmin.exe` 141,824 bytes, PE `0x14C`
  - `build/admin-win-x64/TesterLoopAdmin.exe` 172,544 bytes, PE `0x8664`
  - `build/win-x86/TesterLoop-Setup-x86.exe` 45,143,190 bytes
  - `build/win-x64/TesterLoop-Setup-x64.exe` 50,033,304 bytes
  - `build/admin-win-x86/TesterLoop-Admin-Setup-x86.exe` 45,054,908 bytes
  - `build/admin-win-x64/TesterLoop-Admin-Setup-x64.exe` 49,928,967 bytes
  All four executables report file version `0.5.3.0`; all four installers report
  product version `0.5.3`.
- Launch checks: all four published executables start, keep responsive windows
  titled `TesterLoop` / `TesterLoop Admin`, and were stopped after the check.
- Not verified live: the profile save round-trip, the role badge with each live
  role, and the active-project filter against a real passed project. These need
  `011` applied and live accounts.
- Security: only the publishable key ships. Both new RPCs are `security definer`,
  require `current_developer_id()` / `current_tester_id()`, are granted only to
  `authenticated`, and validate input server-side. No credentials are logged.
- The installers remain unsigned and have not been run end to end.

### Modification 016

Date: 2026-11-02

#### Changes
- Both sign-in screens now remember the last successful email address.
  - Added `Core/LastLoginStore.cs`: stores one email per app under
    `%LOCALAPPDATA%\TesterLoop\main-last-login.txt` and
    `admin-last-login.txt`.
  - `LoginViewModel` and `AdminLoginViewModel` prefill the saved email.
  - `AppViewModel` and `AdminAppViewModel` save the email only after a
    successful role check, so a rejected admin sign-in in TesterLoop does not
    overwrite the remembered developer/tester email.
  - Only the email is stored; the password and Supabase tokens are never
    written to disk.
- Version bumped to `0.5.4` in `AppConfig`, both projects and both installers.

#### Files / Components
- `src/TesterLoop.Shared/Core/LastLoginStore.cs` (new)
- `src/TesterLoop.Desktop/ViewModels/LoginViewModel.cs`,
  `AppViewModel.cs`
- `src/TesterLoop.Admin/ViewModels/AdminLoginViewModel.cs`,
  `AdminAppViewModel.cs`
- `src/TesterLoop.Shared/Core/AppConfig.cs`,
  `src/TesterLoop.Desktop/TesterLoop.Desktop.csproj`,
  `src/TesterLoop.Admin/TesterLoop.Admin.csproj`
- `installer/TesterLoop.iss`, `installer/TesterLoop.Admin.iss`
- `AGENTS.md`, `AGENTS_PLAN.md`, `medial_support.txt`

#### Important Notes
- Read and write failures for this convenience file are ignored; they never
  block sign-in. The file holds only a normalised email address.
- Sign-out keeps the remembered email, so the sign-in form is pre-filled on the
  next launch.
- Verification: Release build 0 warnings / 0 errors. A seeded
  `main-last-login.txt` was read by the published x64 app and UI Automation
  confirmed the email field was pre-filled; the test file was then removed.
- Published and packaged `0.5.4` for both apps and both architectures:
  - `build/win-x86/TesterLoop.exe` 141,824 bytes, PE `0x14C`
  - `build/win-x64/TesterLoop.exe` 172,544 bytes, PE `0x8664`
  - `build/admin-win-x86/TesterLoopAdmin.exe` 141,824 bytes, PE `0x14C`
  - `build/admin-win-x64/TesterLoopAdmin.exe` 172,544 bytes, PE `0x8664`
  - `build/win-x86/TesterLoop-Setup-x86.exe` 45,143,127 bytes
  - `build/win-x64/TesterLoop-Setup-x64.exe` 50,033,445 bytes
  - `build/admin-win-x86/TesterLoop-Admin-Setup-x86.exe` 45,055,126 bytes
  - `build/admin-win-x64/TesterLoop-Admin-Setup-x64.exe` 49,928,568 bytes
  All four executables report file version `0.5.4.0`; all four installers report
  product version `0.5.4`.
- Not verified: the remembered email after a real live sign-in and on the admin
  app; those need working accounts. The installers remain unsigned and have not
  been run end to end.
### Modification 017

Date: 2026-11-02

#### Changes
- Moved workspace navigation into the shared left rail. The rail now carries a
  menu between the brand and the signed-in account card, and the current page is
  highlighted.
- Added `TesterLoop.Shared/Core/NavigationItem.cs`; shared `ShellView` renders
  `NavItems` with an active-state button template.
- `ShellViewModel` builds the developer menu (`Workspace`, `Completed projects`,
  `Profile`) or the tester menu (`Tester bench`, `Profile`) and drives the inner
  view's `SelectedTabIndex`.
- `AdminShellViewModel` builds the operations menu (`Operations`, `Campaigns`,
  `Developers`, `Testers`, `Feedback`, `Audit Trail`, `Profile`).
- Removed the admin tab strip. `AdminView` is now a headerless `TabControl` bound
  to `SelectedTabIndex`; the left menu replaces the tabs.
- Profile editing moved out of the workspace into its own page for both developers
  and testers. Each profile page has `Save profile` and `Discard changes`; the
  inline profile cards and header `Edit profile` toggles are gone.
- Added `DeveloperCompletedView`; `DeveloperViewModel` now keeps all campaigns and
  splits them into `Campaigns` (active) and `CompletedCampaigns` (passed,
  cancelled). The workspace count reflects active projects only.
- Split `DeveloperView.xaml` into `DeveloperWorkspaceView` + `DeveloperCompletedView`
  + `DeveloperProfileView`, and `TesterView.xaml` into `TesterWorkspaceView` +
  `TesterProfileView`; each host is a headerless `TabControl`.
- Removed the sample Play link hints and the `Use suggested` shortcut from the
  closed-test link card. The card now shows one neutral instruction.
- Added `DeveloperViewModel.Navigation.cs`, `TesterViewModel.Navigation.cs` and
  `AdminViewModel.Navigation.cs` for `SelectedTabIndex`.
- Version bumped to `0.5.5` in `AppConfig`, both projects, both installers and the
  marketing file.

#### Files / Components
- `src/TesterLoop.Shared/Core/NavigationItem.cs` (new)
- `src/TesterLoop.Shared/Views/ShellView.xaml`
- `src/TesterLoop.Desktop/ViewModels/ShellViewModel.cs`,
  `DeveloperViewModel.cs`, `DeveloperViewModel.Detail.cs`,
  `DeveloperViewModel.Profile.cs`, `DeveloperViewModel.Navigation.cs` (new),
  `TesterViewModel.Profile.cs`, `TesterViewModel.Navigation.cs` (new)
- `src/TesterLoop.Desktop/Views/DeveloperView.xaml`,
  `DeveloperWorkspaceView.xaml(.cs)` (new),
  `DeveloperCompletedView.xaml(.cs)` (new),
  `DeveloperProfileView.xaml(.cs)` (new), `TesterView.xaml`,
  `TesterWorkspaceView.xaml(.cs)` (new), `TesterProfileView.xaml(.cs)` (new)
- `src/TesterLoop.Admin/ViewModels/AdminShellViewModel.cs`,
  `AdminViewModel.Navigation.cs` (new)
- `src/TesterLoop.Admin/Views/AdminView.xaml`
- `src/TesterLoop.Shared/Core/AppConfig.cs`,
  `src/TesterLoop.Desktop/TesterLoop.Desktop.csproj`,
  `src/TesterLoop.Admin/TesterLoop.Admin.csproj`
- `installer/TesterLoop.iss`, `installer/TesterLoop.Admin.iss`
- `AGENTS.md`, `AGENTS_PLAN.md`, `medial_support.txt`

#### Important Notes
- A headerless `TabControl` needs `x:Name="PART_SelectedContentHost"` on its
  content presenter; without it WPF leaves the page blank. The template also keeps
  a collapsed `TabPanel` marked `IsItemsHost="True"` so item containers are still
  generated.
- The shared rail uses one control template for all three apps; the signed-in
  shell decides which items exist, so a role can never see another role's pages.
- Verification: Release build 0 warnings / 0 errors. All four executables report
  file version `0.5.5.0`, product `0.5.5`; PE machines are `0x14C` for x86 and
  `0x8664` for x64. All four launch and stay responsive.
- Installers recompiled: `build/win-x86/TesterLoop-Setup-x86.exe` 45,145,003 bytes;
  `build/win-x64/TesterLoop-Setup-x64.exe` 50,034,279 bytes;
  `build/admin-win-x86/TesterLoop-Admin-Setup-x86.exe` 45,055,365 bytes;
  `build/admin-win-x64/TesterLoop-Admin-Setup-x64.exe` 49,930,343 bytes. All four
  report product version `0.5.5`.
- UI Automation on the published x64 app: signed in with a disposable developer
  account, confirmed the left menu (`Workspace`, `Completed projects`, `Profile`),
  switched to the Completed projects page (`COMPLETED PROJECTS`, `0 completed`,
  empty-state card) and the Profile page (`Save profile`, `Discard changes`),
  then returned to Workspace. Created project `Nav QA App`
  (`com.qanav.checkapp`) and confirmed the closed-test card shows only the neutral
  instruction, `Save link`, `Open` and `Copy` - no sample URLs and no
  `Use suggested`.
- QA artefacts left in Supabase for the owner to delete: developer auth user
  `qa.nav.developer.1102@example.com` and project `Nav QA App`.
- Not verified: the tester menu and the admin menu, because no tester or operations
  account was used this round. The tester and admin hosts use the same tab-host and
  rail code that passed on the developer side.
- No new security surface: the change is presentational. No secrets, endpoints,
  RPC grants or validation rules changed.
- Deployment order is unchanged and still owed by the owner: `008` -> `009` ->
  `010` -> `011` in the Supabase SQL editor.

### Modification 018

Date: 2026-11-02

#### Changes
- Added a $15 per-project fee. A project cannot go live until its Google Group
  is attached and operations confirms the payment.
- Payment is enforced where the campaign changes state: `save_play_link` now
  refuses an unpaid campaign, and the developer view disables the link action
  until `payment_state = 'paid'`.
- New campaign payment data: `payment_state` (`unpaid` / `paid`),
  `payment_amount_cents` (default `1500`), `payment_reference`, `paid_at` and
  `payment_confirmed_by`.
- Added the admin-only `confirm_payment(p_campaign_id, p_reference)` RPC. It
  requires an attached group, rejects closed or already-paid campaigns, writes a
  `payment.confirmed` audit row and returns the payment state. It is granted only
  to `authenticated`, and `require_admin()` enforces the role server-side.
- Developer view: new PROJECT FEE card with amount, `TL-XXXXXXXX` reference and
  status; the next-step copy explains that the fee is due after the group is
  attached and that the Play link stays locked until confirmation.
- Admin view: new payments queue on Operations, a reference field and
  `Confirm $15 payment` action. The Campaigns table now shows PAYMENT status.
  The operations header/subtitle mentions payments.
- `developer_campaign_json` and `admin_dashboard` now return payment fields; the
  admin dashboard adds a `payments` array limited to `awaiting_link` campaigns
  that have a group and are still unpaid.
- Added `sql/migrations/012_project_payments.sql` for the live project. It adds
  the columns, backfills `live` / `at_risk` / `passed` campaigns as paid, adds
  the amount and paid-at constraints, replaces the two read functions and
  `save_play_link`, creates `confirm_payment`, grants it, and reloads the
  PostgREST schema cache.
- Added `AppConfig.ProjectFeeCents = 1500` and
  `AppConfig.ProjectFeeLabel = "$15"`.
- Version bumped to `0.6.0` in `AppConfig`, both projects, both installers and
  `medial_support.txt`.

#### Files / Components
- `sql/schema/001_init.sql`
- `sql/functions/004_queries.sql`, `sql/functions/005_mutations.sql`
- `sql/seed/007_admin_bootstrap.sql`
- `sql/migrations/012_project_payments.sql` (new)
- `src/TesterLoop.Shared/Core/AppConfig.cs`,
  `src/TesterLoop.Shared/Core/Data/Contracts.cs`,
  `src/TesterLoop.Shared/Core/Data/SupabaseService.cs`
- `src/TesterLoop.Desktop/ViewModels/DeveloperViewModel.cs`,
  `DeveloperViewModel.Detail.cs`, `DeveloperViewModel.Payments.cs` (new),
  `DeveloperViewModel.Projects.cs` (new)
- `src/TesterLoop.Desktop/Views/DeveloperProjectDetailView.xaml`
- `src/TesterLoop.Admin/ViewModels/AdminRows.cs`,
  `AdminViewModel.cs`, `AdminViewModel.Payments.cs` (new),
  `AdminShellViewModel.cs`
- `src/TesterLoop.Admin/Views/AdminOperationsView.xaml`,
  `AdminCampaignsView.xaml`
- `src/TesterLoop.Desktop/TesterLoop.Desktop.csproj`,
  `src/TesterLoop.Admin/TesterLoop.Admin.csproj`
- `installer/TesterLoop.iss`, `installer/TesterLoop.Admin.iss`
- `AGENTS.md`, `AGENTS_PLAN.md`, `medial_support.txt`

#### Important Notes
- The lifecycle is unchanged: `pending` -> `awaiting_link` -> `live`. The fee is
  a gate on activation, not a new campaign state, so the existing state machine,
  seat logic and 12-tester / 14-day clock are unaffected.
- The payment reference is derived from the campaign id (`TL-` + the first eight
  hex characters, upper-case), so the developer and operations see the same value
  without storing another user-editable identifier.
- Backfilling existing `live`, `at_risk` and `passed` campaigns as paid prevents
  the new gate from breaking campaigns that were already running before 0.6.0.
  An `awaiting_link` campaign from before the migration becomes unpaid and must be
  confirmed by operations.
- If the live database has not run `012`, the admin app sets an actionable error
  ("The payments queue needs a database update...") instead of silently showing
  an empty queue. The developer payment card then shows the unpaid state.
- Payment UI code was split into `DeveloperViewModel.Payments.cs` and
  `AdminViewModel.Payments.cs`; project creation moved to
  `DeveloperViewModel.Projects.cs`. Every C# file is now under 300 lines.
- Fixed a corrupted separator glyph in the admin pending-selection label.
- Deployment order is now `008` -> `009` -> `010` -> `011` -> `012`.
- Verification: Release build 0 warnings / 0 errors. All four published
  executables report file version `0.6.0.0`; PE machines are `0x14C` for x86 and
  `0x8664` for x64. All four launch, keep responsive windows titled `TesterLoop`
  or `TesterLoop Admin`, and were stopped after the check.
- Installers recompiled after the split:
  `build/win-x86/TesterLoop-Setup-x86.exe` 45,146,854 bytes;
  `build/win-x64/TesterLoop-Setup-x64.exe` 50,037,342 bytes;
  `build/admin-win-x86/TesterLoop-Admin-Setup-x86.exe` 45,059,088 bytes;
  `build/admin-win-x64/TesterLoop-Admin-Setup-x64.exe` 49,933,385 bytes. All four
  report product version `0.6.0`.
- Not verified: a live payment confirmation and the developer link gate. Both
  need `012` applied, a developer account and an operations account. The payment
  card was not driven through UI Automation this round.
- Security: no secrets or endpoints were added. `confirm_payment` is
  `security definer`, calls `require_admin()`, is granted only to
  `authenticated`, and records the confirming admin id. The developer gate is
  duplicated in SQL so a modified client cannot activate an unpaid project.
- Installers remain unsigned and have not been run end to end.
### Modification 019

Date: 2026-11-02

#### Changes
- Developers no longer see tester email addresses anywhere in the developer
  workspace. The roster now shows only the tester display name, device, seat
  number, state and opt-in date.
- Removed `google_email` from the developer campaign seat payload so a developer
  cannot recover tester addresses by calling the RPC directly.
- Removed `GoogleEmail` from `DeveloperSeatDto` and from the `RosterRow` project
  record; the roster falls back to `Tester <seat>` when a display name is missing.
- TesterLoop Admin keeps the full tester roster, including tester emails, because
  operations needs it for group membership checks.
- Version bumped to `0.6.1` in `AppConfig`, both projects, both installers and
  `medial_support.txt`.

#### Files / Components
- `sql/functions/004_queries.sql`
- `sql/migrations/013_hide_tester_emails.sql` (new)
- `src/TesterLoop.Shared/Core/Data/Contracts.cs`
- `src/TesterLoop.Desktop/ViewModels/Rows.cs`,
  `ViewModels/DeveloperViewModel.Detail.cs`
- `src/TesterLoop.Desktop/Views/DeveloperProjectDetailView.xaml`
- `src/TesterLoop.Shared/Core/AppConfig.cs`,
  `src/TesterLoop.Desktop/TesterLoop.Desktop.csproj`,
  `src/TesterLoop.Admin/TesterLoop.Admin.csproj`
- `installer/TesterLoop.iss`, `installer/TesterLoop.Admin.iss`
- `AGENTS.md`, `AGENTS_PLAN.md`, `medial_support.txt`

#### Important Notes
- The client change alone removes the addresses from the developer screen. The
  SQL migration is still required to stop them being returned by
  `developer_campaign_json`; until `013` runs, a tampered client could read the
  extra JSON field.
- Tester email remains hidden from developers but stays visible to operations in
  TesterLoop Admin. Testers still see their own email on their profile page.
- Deployment order is now `008` -> `009` -> `010` -> `011` -> `012` -> `013`.
- Verification: Release build 0 warnings / 0 errors. All four executables report
  file version `0.6.1.0`; PE machines are `0x14C` for x86 and `0x8664` for x64.
- Published and packaged `0.6.1`:
  - `build/win-x86/TesterLoop.exe` 141,824 bytes
  - `build/win-x64/TesterLoop.exe` 172,544 bytes
  - `build/admin-win-x86/TesterLoopAdmin.exe` 141,824 bytes
  - `build/admin-win-x64/TesterLoopAdmin.exe` 172,544 bytes
  - `build/win-x86/TesterLoop-Setup-x86.exe` 45,147,014 bytes
  - `build/win-x64/TesterLoop-Setup-x64.exe` 50,037,158 bytes
  - `build/admin-win-x86/TesterLoop-Admin-Setup-x86.exe` 45,059,186 bytes
  - `build/admin-win-x64/TesterLoop-Admin-Setup-x64.exe` 49,933,181 bytes
  All four installers report product version `0.6.1`.
- Launch checks: all four executables start, keep responsive windows titled
  `TesterLoop` / `TesterLoop Admin`, and were stopped after the check.
- Not verified live: the developer roster after `013` is applied, because the
  migration has not been run against the live project yet.
- Security: this change reduces data exposure. No secrets, endpoints or RPC
  grants changed; `developer_campaign_json` remains callable only by the
  authenticated developer role. Installers remain unsigned.

### Modification 020

Date: 2026-11-02

#### Changes
- Renamed the admin Operations card `ACTIVE` to `ACTIVE PROJECTS`.
- Renamed the admin `Campaigns` navigation item, page title, tab header and
  operations card to `Close Test Projects`.
- Updated admin supporting copy (`Campaigns` counts, empty state, developer,
  tester and feedback descriptions) to say close test projects.
- Updated admin subtitle and marketing copy to match the new wording.
- Version bumped to `0.6.2` in `AppConfig`, both projects, both installers and
  `medial_support.txt`.

#### Files / Components
- `src/TesterLoop.Admin/Views/AdminView.xaml`
- `src/TesterLoop.Admin/Views/AdminCampaignsView.xaml`,
  `AdminOperationsView.xaml`, `AdminDevelopersView.xaml`,
  `AdminTestersView.xaml`, `AdminFeedbackView.xaml`
- `src/TesterLoop.Admin/ViewModels/AdminShellViewModel.cs`,
  `AdminViewModel.Tabs.cs`
- `src/TesterLoop.Shared/Core/AppConfig.cs`
- `src/TesterLoop.Desktop/TesterLoop.Desktop.csproj`,
  `src/TesterLoop.Admin/TesterLoop.Admin.csproj`
- `installer/TesterLoop.iss`, `installer/TesterLoop.Admin.iss`
- `AGENTS.md`, `AGENTS_PLAN.md`, `medial_support.txt`

#### Important Notes
- Presentation-only change. No SQL, RPC, validation or data model changed.
- Verification: Release build 0 warnings / 0 errors. All four executables report
  file version `0.6.2.0`; PE machines are `0x14C` for x86 and `0x8664` for x64.
  All four launch, keep responsive windows titled `TesterLoop` or
  `TesterLoop Admin`, and were stopped after the check.
- Published and packaged `0.6.2`:
  - `build/win-x86/TesterLoop.exe` 141,824 bytes
  - `build/win-x64/TesterLoop.exe` 172,544 bytes
  - `build/admin-win-x86/TesterLoopAdmin.exe` 141,824 bytes
  - `build/admin-win-x64/TesterLoopAdmin.exe` 172,544 bytes
  - `build/win-x86/TesterLoop-Setup-x86.exe` 45,146,798 bytes
  - `build/win-x64/TesterLoop-Setup-x64.exe` 50,037,033 bytes
  - `build/admin-win-x86/TesterLoop-Admin-Setup-x86.exe` 45,058,603 bytes
  - `build/admin-win-x64/TesterLoop-Admin-Setup-x64.exe` 49,933,825 bytes
  All four installers report product version `0.6.2`.
- A leftover `TesterLoopAdmin` process from an earlier verification run locked
  `build/admin-win-x64`; it was stopped before republishing.
- Installers remain unsigned and have not been run end to end.

### Modification 021

Date: 2026-11-02

#### Changes
- Locked the developer's closed-test link once any tester has joined. The first
  tester seat makes the Play link final, so testers cannot be redirected to a
  different app or test.
  - `save_play_link` now rejects a save when any `campaign_seats` row exists for
    the campaign, even if that tester later opted out.
  - `developer_campaign_json` returns `has_joined_testers`.
  - The developer link card is read-only, the Save action is disabled and a lock
    note is shown when `has_joined_testers` is true or the seat list is non-empty.
- Added report status to the developer roster. Each active seat now carries
  `has_report`, and the roster shows `Reported` or `No report` for that tester.
  No tester email address is exposed.
- Added the honest project start date. `developer_campaign_json` now returns
  `clock_started_at` = the 12th opt-in timestamp from `campaign_health`; the
  developer detail view shows `STARTED` with the date, or `Not started` until at
  least 12 testers are actively opted in. The existing `started_at` (link saved)
  and the at-risk timer are unchanged.
- Added live migration `014_lock_play_link_after_join.sql` with the new JSON
  fields and the link lock. It must run after `013`.
- Version bumped to `0.6.3` in `AppConfig`, both projects, both installers and
  `medial_support.txt`.

#### Files / Components
- `sql/functions/004_queries.sql`
- `sql/functions/005_mutations.sql`
- `sql/migrations/014_lock_play_link_after_join.sql` (new)
- `src/TesterLoop.Shared/Core/Data/Contracts.cs`
- `src/TesterLoop.Desktop/ViewModels/Rows.cs`
- `src/TesterLoop.Desktop/ViewModels/DeveloperViewModel.cs`,
  `DeveloperViewModel.Detail.cs`
- `src/TesterLoop.Desktop/Views/DeveloperProjectDetailView.xaml`
- `src/TesterLoop.Shared/Core/AppConfig.cs`,
  `src/TesterLoop.Desktop/TesterLoop.Desktop.csproj`,
  `src/TesterLoop.Admin/TesterLoop.Admin.csproj`
- `installer/TesterLoop.iss`, `installer/TesterLoop.Admin.iss`
- `AGENTS.md`, `AGENTS_PLAN.md`, `medial_support.txt`

#### Important Notes
- `has_joined_testers` is deliberately based on any seat row, not only active
  seats. A dropped tester still leaves the link locked, so re-joining testers
  cannot be sent to a changed test.
- Report status is per campaign and tester. A tester who filed a report and then
  opted out still counts as having reported; only active seats appear in the
  roster.
- The visible `STARTED` value is the 12th opt-in, matching where `days_banked`
  and `eligible_on` already start. It does not change `started_at` or the 7-day
  at-risk rule, so existing live projects keep their current behaviour.
- Deployment order is now `008` -> `009` -> `010` -> `011` -> `012` -> `013` ->
  `014`.
- Verification: Release build 0 warnings / 0 errors. All four executables report
  file version `0.6.3.0`; PE machines are `0x14C` for x86 and `0x8664` for x64.
  All four launch, keep responsive windows titled `TesterLoop` or
  `TesterLoop Admin`, and were stopped after the check.
- Published and packaged `0.6.3`:
  - `build/win-x86/TesterLoop.exe` 141,824 bytes
  - `build/win-x64/TesterLoop.exe` 172,544 bytes
  - `build/admin-win-x86/TesterLoopAdmin.exe` 141,824 bytes
  - `build/admin-win-x64/TesterLoopAdmin.exe` 172,544 bytes
  - `build/win-x86/TesterLoop-Setup-x86.exe` 45,148,388 bytes
  - `build/win-x64/TesterLoop-Setup-x64.exe` 50,037,841 bytes
  - `build/admin-win-x86/TesterLoop-Admin-Setup-x86.exe` 45,059,198 bytes
  - `build/admin-win-x64/TesterLoop-Admin-Setup-x64.exe` 49,933,191 bytes
  All four installers report product version `0.6.3`.
- Not verified live: the link lock, roster report column and started date, because
  `014` has not been applied to the Supabase project and no live developer or
  tester accounts were used this round. Installers remain unsigned and have not
  been run end to end.
- Security: no secrets or endpoints were added. The link lock is enforced in SQL,
  not only in the client. `developer_campaign_json` still omits tester emails, and
  the new report flag is a boolean, not report content.

### Modification 022

Date: 2026-11-02

#### Changes
- Testers now land in the project's Google Group when they press Join.
  - `JoinCampaign` still records the seat first, then the app opens
    `https://groups.google.com/g/<group-name>` in the default browser.
  - `<group-name>` is the local part of the campaign group address, so
    `hireartist@googlegroups.com` opens `https://groups.google.com/g/hireartist`.
- Added the shared `GroupLink` helper. It accepts only a single `@`, a
  non-empty local part and letters, digits, `.`, `_` or `-`; anything else does
  not produce a link.
- Added `LinkLauncher.TryOpenGroup`; it reuses the same guarded launch path as
  Play links and never starts another scheme.
- Joined projects now carry a `Google Group` button that reopens the derived
  group page later.
- Version bumped to `0.6.4` in `AppConfig`, both projects, both installers and
  `medial_support.txt`.

#### Files / Components
- `src/TesterLoop.Shared/Core/GroupLink.cs` (new)
- `src/TesterLoop.Desktop/Core/LinkLauncher.cs`
- `src/TesterLoop.Desktop/ViewModels/TesterViewModel.cs`,
  `TesterViewModel.Actions.cs`
- `src/TesterLoop.Desktop/Views/TesterWorkspaceView.xaml`
- `src/TesterLoop.Shared/Core/AppConfig.cs`,
  `src/TesterLoop.Desktop/TesterLoop.Desktop.csproj`,
  `src/TesterLoop.Admin/TesterLoop.Admin.csproj`
- `installer/TesterLoop.iss`, `installer/TesterLoop.Admin.iss`
- `AGENTS.md`, `AGENTS_PLAN.md`, `medial_support.txt`

#### Important Notes
- The browser opens only after the seat is accepted. A full or duplicate join
  never sends the tester to a group they did not join.
- If the stored address cannot produce a group link, the seat is still kept and
  the app asks the tester to contact operations instead of silently doing nothing.
- The join page is derived, not stored, so no SQL migration or new column is
  needed. Existing campaigns with a normal `name@googlegroups.com` address work
  immediately.
- The `Google Group` button uses the same helper, so a later reopen follows the
  same validation.
- Verification: Release build 0 warnings / 0 errors. A temporary harness
  exercised `GroupLink` with 15 addresses, including consumer and custom-domain
  forms plus malformed input (`PASS 15/15`).
- Published and packaged `0.6.4` for both apps and both architectures:
  - `build/win-x86/TesterLoop.exe` 141,824 bytes, PE `0x14C`
  - `build/win-x64/TesterLoop.exe` 172,544 bytes, PE `0x8664`
  - `build/admin-win-x86/TesterLoopAdmin.exe` 141,824 bytes, PE `0x14C`
  - `build/admin-win-x64/TesterLoopAdmin.exe` 172,544 bytes, PE `0x8664`
  - `build/win-x86/TesterLoop-Setup-x86.exe` 45,148,293 bytes
  - `build/win-x64/TesterLoop-Setup-x64.exe` 50,038,617 bytes
  - `build/admin-win-x86/TesterLoop-Admin-Setup-x86.exe` 45,059,945 bytes
  - `build/admin-win-x64/TesterLoop-Admin-Setup-x64.exe` 49,933,559 bytes
  All four executables report file version `0.6.4.0`; all four installers report
  product version `0.6.4`.
- Launch checks: all four published executables start, keep responsive windows
  titled `TesterLoop` / `TesterLoop Admin`, and were stopped after the check.
- Not verified live: the Join-to-browser hand-off and the `Google Group` button,
  because no live tester account was used this round. `GroupLink` itself is
  covered by the harness.
- Security: the group opener accepts only `groups.google.com` URLs built from a
  validated group address; no free-form URL can be launched. No secrets or
  endpoints were added. Installers remain unsigned and have not been run end to
  end.

### Modification 023

Date: 2026-11-02

#### Changes
- Replaced attendance-only opt-in with Google Group membership verification.
  A tester's `Confirm opt-in` now calls the `verify-opt-in` Edge Function, which
  asks a Google Apps Script web app whether that tester's Google address is an
  active member of the campaign's group. Only an `active` answer confirms opt-in.
- `set_opt_in(true)` no longer accepts a client attestation. It raises
  "Confirm opt-in checks the Google Group. Use the Confirm opt-in button." for
  authenticated callers. Opt-out is unchanged and clears any verification.
- Added `public.record_verified_opt_in(p_tester_id uuid, p_campaign_id uuid)`,
  callable only by `service_role`, which sets the seat to `opted_in`, records
  `opt_in_verified_at` and `opt_in_verification = 'google_group'`, and writes
  an audit row `seat.opted_in_verified`.
- Added `campaign_seats.opt_in_verified_at` and `opt_in_verification`; the tester
  dashboard returns both.
- Added `google-apps-script/group-check/`: `Code.gs` (secret-checked `doPost`,
  `GroupsApp.getGroupByEmail(...).hasUser(...)`, `doGet` health, manual test
  helper), `appsscript.json` (`USER_DEPLOYING` / `ANYONE_ANONYMOUS`, Groups scope)
  and a `README.md` with deployment steps.
- Added `supabase/functions/verify-opt-in/index.ts`: JWT-verified tester call,
  service-role seat/group lookup, 15-second Apps Script call, then
  `record_verified_opt_in`. Returns plain-language errors for an unconfigured or
  unavailable checker, a non-tester caller, and an inactive membership.
- Client: `ConfirmOptInAsync` posts to `/functions/v1/verify-opt-in`; a `404`
  becomes "Opt-in verification is not deployed yet. Deploy the verify-opt-in
  Edge Function in Supabase, then try again."
- Tester rows now distinguish `Opted in - verified`, `Opted in - unverified`
  (legacy seats) and `Joined - confirm opt-in`, with a note explaining the
  Google Group check.
- Changing `testers.google_email` while any seat is opted in is now rejected:
  "Opt out of your active projects before changing your Google account email."
- Added `sql/migrations/015_verified_opt_in.sql` for the live project. It adds
  the columns and constraint, replaces `tester_dashboard`, `set_opt_in` and
  `update_tester_profile`, adds and grants `record_verified_opt_in`, and reloads
  the PostgREST schema cache.
- Version bumped to `0.7.0` in `AppConfig`, both projects, both installers and
  `medial_support.txt`.

#### Files / Components
- `google-apps-script/group-check/Code.gs`, `appsscript.json`, `README.md` (new)
- `supabase/functions/verify-opt-in/index.ts` (new)
- `sql/schema/001_init.sql`
- `sql/functions/004_queries.sql`, `005_mutations.sql`, `006_tester_actions.sql`
- `sql/seed/007_admin_bootstrap.sql`
- `sql/migrations/015_verified_opt_in.sql` (new)
- `src/TesterLoop.Shared/Core/Data/Contracts.cs`
- `src/TesterLoop.Shared/Core/Data/SupabaseService.cs`,
  `SupabaseService.OptIn.cs` (new), `SupabaseService.Transport.cs`
- `src/TesterLoop.Desktop/ViewModels/Rows.cs`, `TesterViewModel.cs`,
  `TesterViewModel.Actions.cs`
- `src/TesterLoop.Desktop/Views/TesterWorkspaceView.xaml`
- `src/TesterLoop.Shared/Core/AppConfig.cs`,
  `src/TesterLoop.Desktop/TesterLoop.Desktop.csproj`,
  `src/TesterLoop.Admin/TesterLoop.Admin.csproj`
- `installer/TesterLoop.iss`, `installer/TesterLoop.Admin.iss`
- `AGENTS.md`, `AGENTS_PLAN.md`, `medial_support.txt`

#### Important Notes
- Verification is a **direct membership** check only. Pending applicants, nested
  groups and members hidden from the executing account return `inactive`. The
  Apps Script runs as the account that owns-can-view the group, so that account's
  access is the limit of what can be verified.
- Group creation and roster reconciliation stay manual. A verified seat is not a
  group-wide sync and is never shown as one.
- The Edge Function is the only holder of `GROUP_CHECK_URL` and
  `GROUP_CHECK_SECRET`. The desktop client never sees either value, and the Apps
  Script secret is compared with a timing-safe comparison.
- Deployment is manual and outside the agent's reach: deploy `Code.gs` as a web
  app, set its `SHARED_SECRET` script property, create the Edge secrets, deploy
  `verify-opt-in`, then run `015` in the SQL editor.
- Backfill: existing `opted_in` seats keep working and are labelled
  `Opted in - unverified` until they confirm through the new path. Nothing is
  retro-verified, because the app has no record of a past check.
- Open risk: the Edge Function has no per-user rate limit. Each new confirmation
  spends one Apps Script execution (consumer quota is roughly 20k/day and
  `GroupsApp` calls are not free), so a future revision should short-circuit when
  the seat is already verified and add a cooldown.
- Verification: Release build 0 warnings / 0 errors. SQL was reviewed manually
  only; no local Postgres, `psql`, `supabase` or `deno` CLI is available, so `015`
  was not executed.
- Published and packaged `0.7.0` for both apps and both architectures:
  - `build/win-x86/TesterLoop.exe` 141,824 bytes, file `0.7.0.0`, PE `0x14C`
  - `build/win-x64/TesterLoop.exe` 172,544 bytes, file `0.7.0.0`, PE `0x8664`
  - `build/admin-win-x86/TesterLoopAdmin.exe` 141,824 bytes, file `0.7.0.0`
  - `build/admin-win-x64/TesterLoopAdmin.exe` 172,544 bytes, file `0.7.0.0`
  - `build/win-x86/TesterLoop-Setup-x86.exe` 45,149,619 bytes
  - `build/win-x64/TesterLoop-Setup-x64.exe` 50,039,495 bytes
  - `build/admin-win-x86/TesterLoop-Admin-Setup-x86.exe` 45,061,130 bytes
  - `build/admin-win-x64/TesterLoop-Admin-Setup-x64.exe` 49,935,626 bytes
  All four installers report product version `0.7.0`.
- Launch checks: all four published executables start, keep responsive windows
  titled `TesterLoop` / `TesterLoop Admin`, and were stopped after the check.
- Not verified live: the Apps Script check, the Edge Function round-trip and the
  verified opt-in UI, because none of those are deployed yet. Installers remain
  unsigned and have not been run end to end.

### Modification 024

Date: 2026-11-02

#### Changes
- A project's Google Group now stores both its address and its Google Groups URL
  name. The two can differ (`name@googlegroups.com` vs
  `groups.google.com/g/<name>`), so the slug is no longer guessed from the email
  local part.
- Added `google_groups.name` (`not null`, lowercase, letters/digits/`.`/`_`/`-`,
  1-200 chars) to the greenfield schema.
- `attach_group(p_campaign_id, p_group_email, p_group_name)` now accepts and
  validates the group name. An omitted name still defaults to the email local
  part, but TesterLoop Admin requires it explicitly.
- TesterLoop Admin's attach form has a second field, `Group URL name`, validated
  with the shared `GroupLink` rules. The Google Groups list shows
  `groups.google.com/g/<name>` under each group.
- `developer_campaign_json`, `tester_dashboard` (`mine`, `available`) and
  `admin_dashboard` (`groups`, `payments`) now return the group name.
- Tester join and the `Google Group` button open `groups.google.com/g/<name>`
  from the stored name instead of deriving it from the address.
- `verify-opt-in` selects `email, name` from `google_groups` and sends
  `{secret, group, name, email}` to the Apps Script checker. `Code.gs` validates
  the name and echoes it in the response; membership is still looked up by the
  group address.
- Added `sql/migrations/016_group_name_slug.sql` for the live project. It adds
  the column, backfills a sanitised slug with a `group-<id>` fallback, sets the
  constraint, drops the 2-argument `attach_group`, recreates `attach_group` and
  the four read models, grants the new signature and reloads the PostgREST
  schema cache.
- Version bumped to `0.7.1` in `AppConfig`, both projects, both installers and
  `medial_support.txt`.

#### Files / Components
- `sql/schema/001_init.sql`
- `sql/functions/004_queries.sql`, `005_mutations.sql`
- `sql/seed/007_admin_bootstrap.sql`
- `sql/migrations/016_group_name_slug.sql` (new)
- `supabase/functions/verify-opt-in/index.ts`
- `google-apps-script/group-check/Code.gs`, `README.md`
- `src/TesterLoop.Shared/Core/GroupLink.cs`,
  `Core/Data/Contracts.cs`, `Core/Data/SupabaseService.cs`,
  `Core/AppConfig.cs`
- `src/TesterLoop.Admin/ViewModels/AdminViewModel.cs`, `AdminRows.cs`,
  `Views/AdminOperationsView.xaml`
- `src/TesterLoop.Desktop/Core/LinkLauncher.cs`,
  `ViewModels/Rows.cs`, `TesterViewModel.cs`, `TesterViewModel.Actions.cs`
- `src/TesterLoop.Desktop/TesterLoop.Desktop.csproj`,
  `src/TesterLoop.Admin/TesterLoop.Admin.csproj`
- `installer/TesterLoop.iss`, `installer/TesterLoop.Admin.iss`
- `AGENTS.md`, `AGENTS_PLAN.md`, `medial_support.txt`

#### Important Notes
- Membership lookup still uses the group address. `GroupsApp` cannot resolve a
  group by its URL name, so the name is used for the join page and as a
  consistency check only; a wrong slug is not detected by Google.
- Backfill uses the email local part with non-slug characters replaced by `-`
  and leading/trailing separators trimmed; an empty result becomes
  `group-<first 8 of id>`. A name that was already correct is unchanged.
- If `016` has not run, the admin group list shows `â€”` for the name and the
  developer/tester JSON omits `group_name`; the client tolerates a missing name
  and refuses to open a group page rather than guessing.
- Deployment order is now `008` -> `009` -> `010` -> `011` -> `012` -> `013` ->
  `014` -> `015` -> `016`. `016` must run after `015`, because both replace
  `tester_dashboard`.
- Verification: Release build 0 warnings / 0 errors. SQL and TypeScript were
  reviewed manually only; no local Postgres, `psql`, `supabase` or `deno` CLI is
  available, so `016` and the Edge Function were not executed.
- Published and packaged `0.7.1` for both apps and both architectures:
  - `build/win-x86/TesterLoop.exe` 141,824 bytes, file `0.7.1.0`, PE `0x14C`
  - `build/win-x64/TesterLoop.exe` 172,544 bytes, file `0.7.1.0`, PE `0x8664`
  - `build/admin-win-x86/TesterLoopAdmin.exe` 141,824 bytes, file `0.7.1.0`
  - `build/admin-win-x64/TesterLoopAdmin.exe` 172,544 bytes, file `0.7.1.0`
  - `build/win-x86/TesterLoop-Setup-x86.exe` 45,150,527 bytes
  - `build/win-x64/TesterLoop-Setup-x64.exe` 50,040,409 bytes
  - `build/admin-win-x86/TesterLoop-Admin-Setup-x86.exe` 45,061,866 bytes
  - `build/admin-win-x64/TesterLoop-Admin-Setup-x64.exe` 49,935,868 bytes
  All four installers report product version `0.7.1`.
- Launch checks: all four published executables start, keep responsive windows
  titled `TesterLoop` / `TesterLoop Admin`, and were stopped after the check.
- Not verified live: the admin group-name field, the tester join page using the
  stored slug, and the Edge Function passing the name to the Apps Script,
  because `016` and the redeployed checker are still owed. Installers remain
  unsigned and have not been run end to end.
- Security: the group page is still built only from a validated slug under
  `groups.google.com`; no free-form URL can be launched. `attach_group` keeps
  `require_admin()`, is granted only to `authenticated`, and validates the slug
  server-side. No secrets or endpoints were added.

### Modification 025

Date: 2026-11-02

#### Changes
- A campaign may use at most 15 distinct testers over its lifetime, because every
  tester is paid. `join_campaign` now counts every `campaign_seats` row, including
  dropped rows, so a 16th distinct tester is refused. Only the same tester may
  rejoin their own dropped seat, and that rejoin clears any stale verification.
- `tester_dashboard.available` uses the lifetime count for `seats_free` and stops
  advertising a project that has already used all 15 testers. The seat-number
  search and full-seat messages now describe tester seats rather than membership.
- `developer_campaign_json` and `admin_dashboard` return `testers_used`; the
  admin screen shows the paid roster size. `DeveloperCampaignDto` and
  `AdminCampaignDto` gained `TestersUsed`.
- Developer counts now separate active seats from paid testers. The TESTERS metric,
  the seat map, the project list and the open-slot caption use `seats_used`, so a
  dropped tester shows 14/15 both in the map and in the count. The paid lifetime
  count (`testers_used`) stays visible in the seat summary and on completed
  projects, because it is the 15-tester limit that is actually enforced.
- The requirement copy explains the lifetime limit. Admin campaign copy and its
  TESTERS column match.
- Any failed membership check releases the seat. The new
  `public.release_unverified_seat(p_tester_id, p_campaign_id)` is
  `security definer`, callable only by `service_role`, drops the seat, clears
  opt-in fields, writes a `seat.released_unverified` audit row and refreshes the
  campaign state. `verify-opt-in` calls it for an `inactive`, `error` or
  unavailable checker result and returns a rejoin message. A failure before the
  check runs (missing secret or configuration) does not release the seat.
- The tester client reloads the dashboard after a failed Confirm opt-in, keeping
  the server message so the project reappears under open projects for a rejoin.
- Opting out removes the row from MY CAMPAIGNS immediately, before the dashboard
  reload, so the joined list updates without waiting for a manual refresh.
- `release_unverified_seat` grants added to `sql/seed/007_admin_bootstrap.sql`.
- Added `sql/migrations/017_lifetime_seat_cap.sql` with `join_campaign`,
  `release_unverified_seat`, `developer_campaign_json`, `tester_dashboard` and
  `admin_dashboard`, the join/release grants and a PostgREST schema reload.
- Split the admin label helpers out of `AdminViewModel.cs` into
  `AdminViewModel.Labels.cs`; every C# file is under 300 lines again.
- Domain rule 1 in the application `AGENTS.md` is now the lifetime tester limit;
  a new rule 3 documents seat release on a failed check.
- Version bumped to `0.7.2` in `AppConfig`, both projects, both installers and
  `medial_support.txt`; marketing copy no longer claims three warm spares.

#### Files / Components
- `sql/functions/004_queries.sql`, `sql/functions/006_tester_actions.sql`
- `sql/seed/007_admin_bootstrap.sql`
- `sql/migrations/017_lifetime_seat_cap.sql` (new)
- `supabase/functions/verify-opt-in/index.ts`
- `src/TesterLoop.Shared/Core/Data/Contracts.cs`
- `src/TesterLoop.Desktop/ViewModels/DeveloperViewModel.cs`,
  `DeveloperViewModel.Detail.cs`, `TesterViewModel.Actions.cs`
- `src/TesterLoop.Desktop/Views/DeveloperProjectDetailView.xaml`
- `src/TesterLoop.Admin/ViewModels/AdminViewModel.cs`,
  `AdminViewModel.Labels.cs` (new)
- `src/TesterLoop.Admin/Views/AdminCampaignsView.xaml`
- `src/TesterLoop.Shared/Core/AppConfig.cs`,
  `src/TesterLoop.Desktop/TesterLoop.Desktop.csproj`,
  `src/TesterLoop.Admin/TesterLoop.Admin.csproj`
- `installer/TesterLoop.iss`, `installer/TesterLoop.Admin.iss`
- `AGENTS.md`, `AGENTS_PLAN.md`, `medial_support.txt`

#### Important Notes
- A dropped seat still counts against the 15-tester lifetime limit. That is the
  point of the rule: the developer pays every tester who ever held a seat, so a
  replacement must be one of the up-to-15 people already on the project.
- Release happens for any failed membership check: `inactive`, checker error or an
  unreachable Apps Script. A failure before the check runs (missing Edge secret,
  malformed checker URL, no group attached) leaves the seat intact so a deployment
  mistake cannot mass-drop testers.
- Rejoining after a release reuses the tester's own row and seat number, so the
  lifetime count and active seat map stay consistent.
- The lifetime limit changes one existing behaviour: an `awaiting_link` or `live`
  campaign that has already used all 15 testers would have no replaceable seats;
  testers who drop can only rejoin themselves.
- Deployment: run `sql/migrations/017_lifetime_seat_cap.sql` after `016`, then
  redeploy `verify-opt-in` from the Supabase Dashboard editor so the release call
  is active. Secrets are already configured and the function is deployed.
- Verification: Release build 0 warnings / 0 errors. Published and packaged
  `0.7.2` for both apps and both architectures:
  - `build/win-x86/TesterLoop.exe` 141,824 bytes, file `0.7.2.0`, PE `0x14C`
  - `build/win-x64/TesterLoop.exe` 172,544 bytes, file `0.7.2.0`, PE `0x8664`
  - `build/admin-win-x86/TesterLoopAdmin.exe` 141,824 bytes, file `0.7.2.0`
  - `build/admin-win-x64/TesterLoopAdmin.exe` 172,544 bytes, file `0.7.2.0`
  - `build/win-x86/TesterLoop-Setup-x86.exe` 45,150,418 bytes
  - `build/win-x64/TesterLoop-Setup-x64.exe` 50,041,080 bytes
  - `build/admin-win-x86/TesterLoop-Admin-Setup-x86.exe` 45,061,974 bytes
  - `build/admin-win-x64/TesterLoop-Admin-Setup-x64.exe` 49,935,775 bytes
  All four installers report product version `0.7.2`. All four executables start,
  keep responsive windows titled `TesterLoop` / `TesterLoop Admin`, and were
  stopped after the check.
- SQL and TypeScript were reviewed manually only; no local Postgres, `psql`,
  `supabase` or `deno` CLI is available, so `017` and the updated Edge Function
  were not executed.
- Security: no secrets or endpoints were added. `release_unverified_seat` is
  service-role-only with explicit revokes, and it is the only new privileged
  surface. The Edge Function still owns the group-check secret. Installers remain
  unsigned and have not been run end to end.

### Modification 026

Date: 2026-11-02

#### Changes
- Added a per-tester payout ledger. A tester earns a fixed $0.50 for a project
  only when the project is `passed` and that tester filed at least one report on
  it. Any seat state counts, including a dropped seat; paid seats are recorded
  once and carry a reference, timestamp and confirming admin.
- `campaign_seats` now stores `payout_amount_cents` (default 50),
  `payout_state` (`unpaid` / `paid`), `payout_reference`, `paid_at` and `paid_by`.
  The fee is stored per seat so a future rate change cannot rewrite history.
- Added `confirm_tester_payout(p_campaign_id, p_tester_id, p_reference)`.
  It requires operations, locks the seat, rejects a missing seat, an already-paid
  payout, a campaign that has not passed and a tester with no report, then writes
  `tester_payout.confirmed` to the audit log. An omitted reference becomes
  `TP-XXXXXXXX`.
- Added `admin_tester_detail(p_tester_id)` with the tester profile, project and
  payout totals, and every project seat with its report count, fee, eligibility,
  payout state and reference.
- Added `admin_developer_detail(p_developer_id)` with the developer profile,
  project and payment totals, tester payout totals, projects, groups, tester
  aggregates and up to 50 related audit entries. Developer payouts are grouped by
  the developer's projects; no direct table access was opened to the client.
- TesterLoop Admin now uses master/detail pages. Selecting a tester opens the
  payout ledger with a reference field and a `Mark paid` action per eligible
  project. Selecting a developer opens the full account page. Both pages have
  `Back`, and switching admin sections resets the selection.
- Added `sql/migrations/018_tester_payouts.sql` for the live project: new columns
  and constraint, the two detail functions, the payout function, revokes, grants
  and a PostgREST schema reload. It must run after `017`.
- Added `AppConfig.TesterFeeCents = 50` and `TesterFeeLabel = "$0.50"`.
- Version bumped to `0.8.0` in `AppConfig`, both projects, both installers and
  `medial_support.txt`.

#### Files / Components
- `sql/schema/001_init.sql`
- `sql/functions/004_queries.sql`, `sql/functions/005_mutations.sql`
- `sql/seed/007_admin_bootstrap.sql`
- `sql/migrations/018_tester_payouts.sql` (new)
- `src/TesterLoop.Shared/Core/AppConfig.cs`
- `src/TesterLoop.Shared/Core/Data/Contracts.AdminDetail.cs` (new)
- `src/TesterLoop.Shared/Core/Data/SupabaseService.AdminDetail.cs` (new)
- `src/TesterLoop.Admin/ViewModels/AdminRows.Detail.cs`, `AdminDetails.cs`,
  `AdminViewModel.TesterDetail.cs`, `AdminViewModel.DeveloperDetail.cs` (new)
- `src/TesterLoop.Admin/ViewModels/AdminViewModel.cs`,
  `AdminViewModel.Navigation.cs`, `AdminViewModel.Labels.cs`,
  `AdminShellViewModel.cs`
- `src/TesterLoop.Admin/Views/AdminTestersView.xaml`,
  `AdminDevelopersView.xaml`, `AdminView.xaml`,
  `AdminTesterDetailView.xaml(.cs)`, `AdminDeveloperDetailView.xaml(.cs)` (new)
- `src/TesterLoop.Desktop/TesterLoop.Desktop.csproj`,
  `src/TesterLoop.Admin/TesterLoop.Admin.csproj`
- `installer/TesterLoop.iss`, `installer/TesterLoop.Admin.iss`
- `AGENTS.md`, `AGENTS_PLAN.md`, `medial_support.txt`

#### Important Notes
- A payout is an operations record, not an automatic transfer. Nothing leaves the
  app; staff pay the tester through their normal channel and paste the reference.
  There is no edit or reversal action yet, so a mistaken confirmation is a manual
  database correction by the owner.
- Eligibility is computed at read time from the campaign state and report rows.
  A project that is cancelled, or a tester with no report, shows no payable fee.
  Once a project passes and a report exists, the fee becomes due even if the seat
  was dropped.
- The payouts are recorded against `campaign_seats`, so the $0.50 belongs to that
  tester on that project. A tester who joins several passed projects has several
  separate $0.50 lines.
- `admin_dashboard` is deliberately unchanged; per-project payout amounts live on
  the detail pages. This keeps the large dashboard function from being duplicated
  in the migration.
- Deployment order is now `008` -> `009` -> `010` -> `011` -> `012` -> `013` ->
  `014` -> `015` -> `016` -> `017` -> `018`. `017` and `018` are still owed by the
  owner, and `verify-opt-in` still needs redeploying after `017`.
- Verification: Release build 0 warnings / 0 errors. A temporary WPF harness
  loaded `AdminView`, `AdminTesterDetailView` and `AdminDeveloperDetailView` with
  the live theme dictionaries and reported no binding errors.
- Published and packaged `0.8.0` for both apps and both architectures:
  - `build/win-x86/TesterLoop.exe` 141,824 bytes, file `0.8.0.0`, PE `0x14C`
  - `build/win-x64/TesterLoop.exe` 172,544 bytes, file `0.8.0.0`, PE `0x8664`
  - `build/admin-win-x86/TesterLoopAdmin.exe` 141,824 bytes, file `0.8.0.0`
  - `build/admin-win-x64/TesterLoopAdmin.exe` 172,544 bytes, file `0.8.0.0`
  - `build/win-x86/TesterLoop-Setup-x86.exe` 45,156,544 bytes
  - `build/win-x64/TesterLoop-Setup-x64.exe` 50,047,232 bytes
  - `build/admin-win-x86/TesterLoop-Admin-Setup-x86.exe` 45,075,403 bytes
  - `build/admin-win-x64/TesterLoop-Admin-Setup-x64.exe` 49,950,183 bytes
  All four executables start, keep responsive windows titled `TesterLoop` /
  `TesterLoop Admin`, and were stopped after the check. All four installers report
  product version `0.8.0`.
- SQL was reviewed manually only; no local Postgres, `psql`, `supabase` or `deno`
  CLI is available, so `018` was not executed against the live project.
- Not verified live: the tester payout round-trip, the developer detail page and
  the $0.50 amounts, because `017` / `018` have not been applied and no operations
  account was used this round.
- Security: only the publishable key ships. Both detail functions and
  `confirm_tester_payout` are `security definer`, call `require_admin()`, are
  revoked from `public` / `anon` and granted only to `authenticated`. Tester
  emails stay visible only on the admin side. No secrets or endpoints were added.
  Installers remain unsigned and have not been run end to end.

### Modification 027

Date: 2026-11-02

#### Changes
- Reduced the text scale on the admin tester and developer detail pages. The top
  summary cards no longer use the full 30px metric style; they use a local
  `DetailMetric` style at 14px with wrapping, and section/table labels use a
  `DetailEyebrow` style at 9.5px.
- Reduced table body text: project names 11px, secondary text and cells 10px or
  9.5px, and the payout action button 10.5px. Page titles are 19px.
- Version bumped to `0.8.1` in `AppConfig`, both projects, both installers and
  `medial_support.txt`.

#### Files / Components
- `src/TesterLoop.Admin/Views/AdminTesterDetailView.xaml`
- `src/TesterLoop.Admin/Views/AdminDeveloperDetailView.xaml`
- `src/TesterLoop.Shared/Core/AppConfig.cs`
- `src/TesterLoop.Desktop/TesterLoop.Desktop.csproj`,
  `src/TesterLoop.Admin/TesterLoop.Admin.csproj`
- `installer/TesterLoop.iss`, `installer/TesterLoop.Admin.iss`
- `AGENTS.md`, `AGENTS_PLAN.md`, `medial_support.txt`

#### Important Notes
- Presentation-only change. No SQL, RPC, validation or data model changed.
- The local styles inherit from the shared `Metric` and `Eyebrow` styles, so the
  colour, font family and weight stay consistent with the rest of the admin app.
- Verification: Release build 0 warnings / 0 errors. The WPF harness loaded
  `AdminView`, `AdminTesterDetailView` and `AdminDeveloperDetailView` with no
  binding errors. Published and packaged `0.8.1` for both apps and both
  architectures:
  - `build/win-x86/TesterLoop.exe` 141,824 bytes, file `0.8.1.0`, PE `0x14C`
  - `build/win-x64/TesterLoop.exe` 172,544 bytes, file `0.8.1.0`, PE `0x8664`
  - `build/admin-win-x86/TesterLoopAdmin.exe` 141,824 bytes, file `0.8.1.0`
  - `build/admin-win-x64/TesterLoopAdmin.exe` 172,544 bytes, file `0.8.1.0`
  - `build/win-x86/TesterLoop-Setup-x86.exe` 45,156,902 bytes
  - `build/win-x64/TesterLoop-Setup-x64.exe` 50,047,867 bytes
  - `build/admin-win-x86/TesterLoop-Admin-Setup-x86.exe` 45,076,274 bytes
  - `build/admin-win-x64/TesterLoop-Admin-Setup-x64.exe` 49,950,016 bytes
  All four executables start, keep responsive windows titled `TesterLoop` /
  `TesterLoop Admin`, and were stopped after the check. All four installers report
  product version `0.8.1`.
- Not verified: the visual result on the live admin detail pages, because those
  pages need `017` / `018` applied and an operations account. Installers remain
  unsigned and have not been run end to end.
- Security: no new surface. Only two XAML files changed.

### Modification 028

Date: 2026-11-02

#### Changes
- Added Android tester app (`src/TesterLoop.Android/`) for testers only with
  parity features and install/usage tracking.
- Added Supabase migration `sql/migrations/019_tester_app_usage.sql`:
  `tester_app_installs`, `tester_app_usage`, `tester_app_usage_summary`,
  RLS policies, RPCs `report_app_install_status`, `report_app_usage_daily`,
  `get_tester_usage_status`, and extended `tester_dashboard` to return
  `usage_status` per joined campaign.
- Android app uses Kotlin + Jetpack Compose + Hilt + Retrofit, targets Supabase
  REST/Auth/Functions. Includes login, dashboard (mine/available), campaign
  detail with install check and verified opt-in, and a WorkManager worker for
  UsageStatsManager-based daily usage sync.
- Usage requires `PACKAGE_USAGE_STATS`; install detection uses targeted package
  checks. Tracking is per joined campaign only and gated to tester role.

#### Files / Components
- `src/TesterLoop.Android/` (new)
- `sql/migrations/019_tester_app_usage.sql` (new)
- `AGENTS.md`, `AGENTS_PLAN.md`

#### Important Notes
- Migration must be run in Supabase SQL editor and schema cache reloaded.
- Usage is tracked as 14 continuous days of foreground usage >= 60s per day
  (computed server-side). It is informational/compliance tracking tied to
  joined campaigns; existing group-verified opt-in remains the gate.
- `QUERY_ALL_PACKAGES` and `PACKAGE_USAGE_STATS` require Play Store review if
  published. The app avoids broad scanning and only checks packages for joined
  campaigns.

### Modification 029

Date: 2026-11-03

#### Changes
- Restored the missing `LoginVm` so the Android app compiles again. It now:
  - signs in against Supabase Auth and checks `whoami` before opening the app;
  - refuses developer and operations accounts and clears only the saved tokens;
  - sends `data.role = "tester"` plus the sign-in email as `google_email` on
    signup, because the database trigger reads the role from auth metadata;
  - repairs legacy auth users through `claim_profile` when `whoami` reports no
    profile;
  - remembers the last email, supports password recovery and maps HTTP errors to
    plain-language messages.
- Added an optional `data` map to `AuthRequest` and a `clearSession()` method that
  removes tokens while keeping the remembered email.
- Splash now validates the stored session through `whoami`, rejects a non-tester
  role, and clears an expired token instead of letting the home screen fail with
  a raw 401.
- Fixed `sql/migrations/019_tester_app_usage.sql`:
  - replaced the nonexistent `public.current_admin_id()` with `public.is_admin()`;
  - made triggers and policies idempotent with `drop ... if exists`;
  - revoked direct table access from `public`, `anon` and `authenticated`;
  - restricted usage dates to today or yesterday;
  - anchored the continuous-day count to the latest day only when that day is
    today or yesterday, so an old 14-day run no longer counts as current;
  - fixed the usage-summary recompute to select only the distinct-day count.
- Added the three Android RPC grants to `sql/seed/007_admin_bootstrap.sql`, so
  re-running the bootstrap does not strip them.
- Fixed `UsageSyncWorker`: it was reporting zero foreground time because `total`
  was never incremented. It now reads `UsageEvents` resume/pause pairs, counts
  foreground milliseconds and sessions, reports install status, and syncs
  yesterday plus today. Install status is reported even when usage access is not
  granted; only the usage part is skipped until the tester grants it.
- Scheduled usage sync in `TesterLoopApp` with a daily `PeriodicWorkRequest` and a
  one-time immediate request, both unique and network-constrained.
- Passed the campaign package name from the home list into the detail route, so
  the install check uses the campaign package and the field is read-only when
  known. The manual entry remains only as a fallback for old payloads.
- Manifest: `android:allowBackup="false"`, `android:fullBackupContent="false"`,
  a `dataExtractionRules` resource that excludes cloud backup and device transfer,
  and a launcher icon from `media/icons/testerloop-icon-512.png` copied to
  `mipmap-xxxhdpi`.
- Build: AGP `8.12.0`, Gradle wrapper `8.14.3`, `compileSdk`/`targetSdk` `36`,
  version `0.2.0` (`versionCode 2`). Target `36` meets the current Play target-API
  requirement for a new app in November 2026.
- Added Android build, keystore and local-properties entries to `.gitignore`.
- Regenerated `medial_support.txt` for desktop `0.8.1` and Android `0.2.0`.
- Updated `AGENTS_PLAN.md` with the Android P0 status.

#### Files / Components
- `src/TesterLoop.Android/app/src/main/kotlin/com/testerloop/app/ui/auth/LoginVm.kt`
  (new)
- `src/TesterLoop.Android/app/src/main/kotlin/com/testerloop/app/ui/auth/LoginScreen.kt`
- `src/TesterLoop.Android/app/src/main/kotlin/com/testerloop/app/ui/splash/SplashScreen.kt`
- `src/TesterLoop.Android/app/src/main/kotlin/com/testerloop/app/ui/Nav.kt`,
  `ui/home/HomeScreen.kt`, `ui/campaign/CampaignDetailScreen.kt`
- `src/TesterLoop.Android/app/src/main/kotlin/com/testerloop/app/worker/UsageReader.kt`
  (new), `worker/UsageSyncWorker.kt`, `TesterLoopApp.kt`
- `src/TesterLoop.Android/app/src/main/kotlin/com/testerloop/app/data/api/Models.kt`,
  `data/local/SessionStore.kt`
- `src/TesterLoop.Android/app/src/main/AndroidManifest.xml`
- `src/TesterLoop.Android/app/src/main/res/xml/data_extraction_rules.xml` (new)
- `src/TesterLoop.Android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png` (new)
- `src/TesterLoop.Android/app/build.gradle.kts`,
  `src/TesterLoop.Android/build.gradle.kts`,
  `src/TesterLoop.Android/gradle/wrapper/gradle-wrapper.properties`
- `sql/migrations/019_tester_app_usage.sql`,
  `sql/seed/007_admin_bootstrap.sql`
- `.gitignore`, `AGENTS.md`, `AGENTS_PLAN.md`, `medial_support.txt`

#### Important Notes
- Build command (no Gradle wrapper JAR is present):
  `$env:JAVA_HOME='C:\Users\Nwick\.local\jdk-17.0.20+8';
  $env:ANDROID_HOME='E:\AITools\android-sdk';
  $env:GRADLE_USER_HOME='E:\AITools\gradle-home';
  & 'E:\AITools\gradle-home\wrapper\dists\gradle-8.14.3-bin\cv11ve7ro1n3o1j4so8xd9n66\gradle-8.14.3\bin\gradle.bat'
  -p 'E:\AIprojects\Safety App\Close Testers\src\TesterLoop.Android' :app:assembleDebug
  --no-daemon`
  The first `8.14.3` build needed network access to resolve the Kotlin plugin;
  later builds can use `--offline`.
- Verification: `:app:assembleDebug` and `:app:lintDebug` succeed. Output
  `app/build/outputs/apk/debug/app-debug.apk` is `18,981,210` bytes, `versionCode
  2`, `versionName 0.2.0`, `minSdk 24`, `targetSdk 36`, label `TesterLoop`,
  application id `com.testerloop.app`. The APK is debug-signed and its manifest
  carries `allowBackup=false`, `fullBackupContent=false` and the extraction rules.
  Lint reports `0 errors`; the 27 warnings are dependency-version notices, a
  Composable modifier-order note and three `String.toUri` suggestions.
- The APK has not been installed on a device or emulator. `adb devices` is empty,
  and the cached `VortexTest` AVD cannot boot because this machine has no Android
  Emulator hypervisor driver / hardware acceleration (`x86_64 emulation currently
  requires hardware acceleration`). Runtime sign-in, signup, opt-in and usage sync
  are therefore not yet device-verified.
- Migration `019` has not been applied to the live Supabase project. The Android
  dashboard will not return `usage_status` until it is run; apply `019` after `018`
  and redeploy nothing else.
- No production release APK/AAB was produced because no Android signing keystore
  was supplied. The debug APK is not suitable for Play upload.
- Security: no secrets were added; only the publishable anon key ships. The
  Android app refuses non-tester accounts on sign-in and at startup. Migration
  `019` now revokes direct table access and allows usage reports only for today or
  yesterday. `allowBackup` is off. `QUERY_ALL_PACKAGES` and
  `PACKAGE_USAGE_STATS` still need Play policy review if published.
- Still open: expired access tokens are not refreshed (refresh token is stored but
  unused), there is no in-app sign-out or profile editor, and there is no bug
  report form wired to `file_report` in the Android app.

### Modification 030

Date: 2026-11-03

#### Changes
- Rebuilt the Android tester app from scratch at `mobile/` and deleted the old
  `src/TesterLoop.Android` project permanently at the owner's request. The
  Supabase backend, RPCs and migration `019` are unchanged and shared.
- New package structure: `com.testerloop.app` with `core/`, `data/api/`,
  `data/local/`, `di/`, `ui/theme/`, `ui/components/`, `ui/{splash,auth,home,
  projects,profile,campaign}/`, `worker/`, plus `MainActivity` and
  `TesterLoopApp`.
- New warm-light design system: `Bg #F7F4ED`, `Surface #FFFDF8`,
  `SurfaceWarm #F1ECE1`, `Ink #12211E`, `Teal #0F766E`, `Coral #EA580C`,
  semantic good/warn/bad tones, 22dp cards with 1dp borders and no elevation,
  52dp primary buttons, Plus Jakarta Sans 400/600/700/800 bundled as resources.
- Single `AppVm` (`@HiltViewModel`) holds `UiState` and a `Channel<UiEvent>`.
  Navigation is phase-driven (`splash` -> `auth` -> `shell`, plus
  `campaign/{id}`); the bottom tabs Home/Projects/Profile live in `UiState`, not
  in a nested NavHost. `AppVm.Actions.kt`, `AppVm.Auth.kt` and `AppVm.Profile.kt` hold action, auth and
  profile extensions.
- Screens: splash, one auth screen with sign-in/sign-up/recover/verify modes,
  home dashboard with a continuous-day hero, metric tiles, needs-attention list,
  joined projects and recent reports; Projects with Joined/Open segments;
  campaign detail with opt-in, access, usage and reports; report filing in a
  modal bottom sheet; profile with inline editing, usage access, background sync
  and sign-out confirmation; shared shell with bottom navigation and snackbar
  events.
- Device actions: Join records the seat then opens the stored
  `groups.google.com/g/<name>` page; Confirm opt-in calls the `verify-opt-in`
  Edge Function; Play links are opened only after `PlayLink` validation; usage
  settings open the system Usage Access screen; install checks use targeted
  package lookups.
- Ported the token-refresh fix: `SessionManager` reads the JWT expiry, refreshes
  a minute early, serialises refreshes with a mutex, retries a 401 once with the
  newer token, and clears the session on a rejected refresh. A stored refresh
  token is therefore no longer left unused until every call 401s.
- Every mutation is checked. `Response<Unit>` RPCs now call `orThrow()`, so a
  rejected join, opt-out, profile save, report or usage upload surfaces the real
  error instead of being treated as success. The opt-in response is read from
  `state` / `opt_in_verification` as well as the checker status.
- Kept install/usage reporting: a Hilt WorkManager worker syncs yesterday and
  today plus install status, both on an immediate one-time request and a daily
  periodic request; install status is still reported when Usage Access is not
  granted. `UsageReader` counts foreground milliseconds from `UsageEvents`
  resume/pause pairs.
- Signup also sends the tester display name in auth metadata, so the database
  trigger stores the name the tester typed instead of fallback text from the email.
- The profile page re-checks Usage Access when it resumes, so returning from
  Android settings updates the status without restarting the app.
- Background usage sync treats HTTP 4xx as non-retryable (for example, a seat that
  was released while the worker ran) and retries only transport or 5xx failures.
- Kept tester-only enforcement: sign-in and splash both call `whoami` and refuse
  non-tester roles; legacy auth users without a profile are repaired through
  `claim_profile`; admin and developer accounts are signed out with a clear
  message.
- Bumped the Android app to `1.0.0` (`versionCode 10000`),
  `compileSdk`/`targetSdk` 36, `minSdk` 24.
- Updated `.gitignore` for `.kotlin/`, Android captures, `.externalNativeBuild/`,
  `*.iml`, `*.apk` and `*.aab`.

#### Files / Components
- `mobile/` (new): Gradle files, manifest, resources, fonts, launcher icon,
  Kotlin source and all UI described above.
- Removed: `src/TesterLoop.Android/` (entire old app).
- `.gitignore`, `AGENTS.md`, `AGENTS_PLAN.md`, `medial_support.txt`

#### Important Notes
- Verification: `:app:assembleDebug` and `:app:lintDebug` succeed with
  `--no-daemon`. APK `mobile/app/build/outputs/apk/debug/app-debug.apk` is
  `19,060,164` bytes, package `com.testerloop.app`, `versionCode 10000`,
  `versionName 1.0.0`, `minSdk 24`, `targetSdk 36`, label `TesterLoop`. Lint
  reports `0 errors`, 24 warnings and 1 hint; the warnings are dependency and
  deprecation notices (`ArrowForward`, `UsageEvents` constants, Moshi codegen).
- Installable debug APK is copied to `build/android/TesterLoop-Mobile-1.0.0-debug.apk`; the unsigned release APK is copied to `build/android/TesterLoop-Mobile-1.0.0-release-unsigned.apk`.
- Release compilation also succeeds: `mobile/app/build/outputs/apk/release/` produces `app-release-unsigned.apk` at `12,982,072` bytes. It is unsigned and cannot be installed or uploaded until a signing keystore is supplied.
- HTTP logging is `BASIC` in debug builds and `NONE` in release builds, so production requests are not logged.
- The debug APK has not been installed on a device or emulator. `adb devices` is
  empty and the cached AVD has no hypervisor acceleration, so sign-in, join,
  verified opt-in, report filing, profile save and background usage sync are not
  yet device-verified.
- `QUERY_ALL_PACKAGES` and `PACKAGE_USAGE_STATS` still need Play policy review.
  `allowBackup` is off, `fullBackupContent` is off, and the extraction rules
  exclude cloud backup and device transfer.
- No production release APK/AAB was produced because no Android signing keystore
  was supplied. The debug APK is not suitable for Play upload.
- Security: only the publishable anon key ships in the client. There is no
  service-role key, secret or token logging; session tokens live in DataStore and
  the remembered email is the only value kept across a sign-out. Both new AI
  prompts and marketing copy avoid claiming whole-device monitoring, automatic
  Play opt-in or automatic payouts.
- The old app source is gone. Any build output or notes that still reference
  `src/TesterLoop.Android` are historical; the canonical Android project is
  `mobile/`.
### Modification 031

Date: 2026-11-03

#### Changes
- Disabled the tester `Join` action when a project has no free seats.
  - `AvailableRow` now carries `SeatsFree` and a `CanJoin` flag.
  - The tester workspace bindings enable `Join` only when `CanJoin` is true,
    and `JoinAsync` refuses a row with zero seats before any network call.
  - The Android tester app now also refuses a zero-seat join in
    `AppVm.join`, not only through the disabled button.
- Version bumped to `0.8.2` for both Windows apps and `1.0.1`
  (`versionCode 10001`) for the Android app.

#### Files / Components
- `src/TesterLoop.Desktop/ViewModels/Rows.cs`,
  `TesterViewModel.cs`, `TesterViewModel.Actions.cs`
- `src/TesterLoop.Desktop/Views/TesterWorkspaceView.xaml`
- `mobile/app/src/main/kotlin/com/testerloop/app/ui/AppVm.Actions.kt`
- `src/TesterLoop.Shared/Core/AppConfig.cs`,
  `src/TesterLoop.Desktop/TesterLoop.Desktop.csproj`,
  `src/TesterLoop.Admin/TesterLoop.Admin.csproj`
- `mobile/app/build.gradle.kts`
- `installer/TesterLoop.iss`, `installer/TesterLoop.Admin.iss`
- `AGENTS.md`, `AGENTS_PLAN.md`, `medial_support.txt`

#### Important Notes
- Root cause: the desktop Join button had no `IsEnabled` binding, so it stayed
  active even when the row said 0 seats free. The server already refuses a full
  join and the dashboard excludes full campaigns after migration `017`, but the
  client did not show that state. The Android client already disabled the button.
- The SQL model is unchanged. The client now mirrors the server rule so a stale or
  unmigrated dashboard cannot offer a seat that does not exist.
- Verification: Release build 0 warnings / 0 errors. Published and packaged
  `0.8.2`:
  - `build/win-x86/TesterLoop.exe` 141,824 bytes, file `0.8.2.0`, PE `0x14C`
  - `build/win-x64/TesterLoop.exe` 172,544 bytes, file `0.8.2.0`, PE `0x8664`
  - `build/admin-win-x86/TesterLoopAdmin.exe` 141,824 bytes, file `0.8.2.0`
  - `build/admin-win-x64/TesterLoopAdmin.exe` 172,544 bytes, file `0.8.2.0`
  - `build/win-x86/TesterLoop-Setup-x86.exe` 45,157,204 bytes
  - `build/win-x64/TesterLoop-Setup-x64.exe` 50,047,704 bytes
  - `build/admin-win-x86/TesterLoop-Admin-Setup-x86.exe` 45,076,131 bytes
  - `build/admin-win-x64/TesterLoop-Admin-Setup-x64.exe` 49,950,121 bytes
  All four executables start, keep responsive windows titled `TesterLoop` /
  `TesterLoop Admin`, and were stopped after the check. All four installers
  report product version `0.8.2`.
- Android: `:app:assembleDebug` and `:app:assembleRelease` succeed.
  `TesterLoop-Mobile-1.0.1-debug.apk` is 18,814,810 bytes and
  `TesterLoop-Mobile-1.0.1-release-unsigned.apk` is 12,982,076 bytes; both are
  in `build/android`. The release APK is unsigned.
- A previous `TesterLoop` instance (pid 7392) held `build/win-x64` open and
  blocked the first publish; it was stopped before republishing.
- Not verified live: the disabled Join with a real 0-seat campaign, because that
  state requires a fully used campaign and a live tester account.
- Security: no secrets, endpoints, RPC grants or validation rules changed. The
  database remains the authority for the 15-seat lifetime limit.

### Modification 032

Date: 2026-11-03

#### Changes
- Developers can delete their own projects from the project detail page and from
  the Completed projects list. The app asks for confirmation, then removes the
  project, its seats, roster and reports.
- A project becomes read-only and undeletable once a tester's opt-in is verified,
  until 14 days after that first verified opt-in. The lock is stored on the
  campaign (`first_opt_in_at`) so it survives a tester opting out, and it is
  enforced in SQL rather than only in the client.
- Added `campaigns.first_opt_in_at` to the schema. `record_verified_opt_in` sets
  it once, using the seat's opt-in timestamp.
- Added `delete_campaign(p_campaign_id uuid)`, developer-only, `security definer`,
  granted only to `authenticated`. It rejects a locked project with the
  unlock date in the message and rejects a project with any `payout_state = 'paid'`
  so recorded tester payouts keep their financial record. A delete writes a
  `campaign.deleted` audit row with the campaign id and tester counts.
- `developer_campaign_json` now returns `first_opt_in_at`, `delete_locked` and
  `delete_unlocks_at`.
- Client: `DeveloperCampaignDto` gained the three fields, `CampaignOption` gained
  `CanDelete` and `DeleteNote`, a new `DeveloperViewModel.Delete.cs` partial holds
  the two delete commands and confirmation dialog, and the detail and completed
  views gained the guarded delete actions.
- Added `sql/migrations/020_developer_delete_projects.sql` for the live project:
  adds the column, backfills it from the earliest verified or attested opt-in,
  replaces `record_verified_opt_in` and `developer_campaign_json`, creates
  `delete_campaign`, revokes it from `public` / `anon`, grants it to
  `authenticated` and reloads the PostgREST schema cache.
- Version bumped to `0.8.3` in `AppConfig`, both projects, both installers and
  `medial_support.txt`.

#### Files / Components
- `sql/schema/001_init.sql`
- `sql/functions/004_queries.sql`, `sql/functions/005_mutations.sql`,
  `sql/functions/006_tester_actions.sql`
- `sql/seed/007_admin_bootstrap.sql`
- `sql/migrations/020_developer_delete_projects.sql` (new)
- `src/TesterLoop.Shared/Core/Data/Contracts.cs`,
  `src/TesterLoop.Shared/Core/Data/SupabaseService.cs`
- `src/TesterLoop.Desktop/ViewModels/DeveloperViewModel.cs`,
  `DeveloperViewModel.Detail.cs`, `DeveloperViewModel.Delete.cs` (new),
  `ViewModels/Rows.cs`
- `src/TesterLoop.Desktop/Views/DeveloperProjectDetailView.xaml`,
  `Views/DeveloperCompletedView.xaml`
- `src/TesterLoop.Shared/Core/AppConfig.cs`,
  `src/TesterLoop.Desktop/TesterLoop.Desktop.csproj`,
  `src/TesterLoop.Admin/TesterLoop.Admin.csproj`
- `installer/TesterLoop.iss`, `installer/TesterLoop.Admin.iss`
- `AGENTS.md`, `AGENTS_PLAN.md`, `medial_support.txt`

#### Important Notes
- "Edit" means the existing closed-test link change. That link is already locked
  from the first join (`IsLinkLocked`), which is stricter than the new 14-day rule,
  and no other project-edit RPC exists. The delete gate is the new 14-day lock.
- A project whose testers were already paid cannot be deleted at all, even after
  the 14 days, so the payout ledger keeps a project to point at. The owner can
  still remove it manually in Supabase if that is ever required.
- Deleting a campaign cascades its seats and reports. The campaign's Google Group
  row is left in place for operations, consistent with the existing manual group
  model.
- The lock is checked at delete time in SQL. A tampered client cannot delete a
  locked project, and the client hides the action so it is not offered.
- Deployment order is now `008` -> ... -> `019` -> `020`. `019` and `020` are still
  owed by the owner; `020` must run after `019` because both touch tester RPCs.
- Verification: Release build 0 warnings / 0 errors. Every C# file stays under 300
  lines (`DeveloperViewModel.cs` 291, `.Detail.cs` 298, `.Delete.cs` 90).
  Published and packaged `0.8.3` for both apps and both architectures:
  - `build/win-x86/TesterLoop.exe` 141,824 bytes, file `0.8.3.0`, PE `0x14C`
  - `build/win-x64/TesterLoop.exe` 172,544 bytes, file `0.8.3.0`, PE `0x8664`
  - `build/admin-win-x86/TesterLoopAdmin.exe` 141,824 bytes, file `0.8.3.0`
  - `build/admin-win-x64/TesterLoopAdmin.exe` 172,544 bytes, file `0.8.3.0`
  - `build/win-x86/TesterLoop-Setup-x86.exe` 45,158,888 bytes
  - `build/win-x64/TesterLoop-Setup-x64.exe` 50,048,882 bytes
  - `build/admin-win-x86/TesterLoop-Admin-Setup-x86.exe` 45,076,434 bytes
  - `build/admin-win-x64/TesterLoop-Admin-Setup-x64.exe` 49,950,600 bytes
  All four executables start, keep responsive windows titled `TesterLoop` /
  `TesterLoop Admin`, and were stopped after the check. All four installers report
  product version `0.8.3`.
- Not verified live: the delete round-trip and the lock, because `020` has not been
  applied and no live developer or tester account was used this round. The new
  XAML was compiled but not exercised through UI Automation.
- SQL was reviewed manually only; no local Postgres, `psql`, `supabase` or `deno`
  CLI is available, so `020` was not executed.
- Security: no secrets or endpoints were added. `delete_campaign` is
  `security definer`, calls `require_developer()` and scopes the row to that
  developer, revokes `public` / `anon` execution and grants only `authenticated`.
  Installers remain unsigned and have not been run end to end.

### Modification 033

Date: 2026-11-03

#### Changes
- Reordered assisted group provisioning so payment comes first. Confirming the
  $15 fee now reserves the campaign's exact group identity; operations then
  creates the group by hand, attests all five settings and attaches the reserved
  address, display name and URL name.
- Added per-developer group numbering and reservation fields to campaigns:
  `group_sequence`, `reserved_group_email`, `reserved_group_url_name`,
  `reserved_group_display_name`, `group_identity_reserved_at`, plus
  `developers.group_sequence_counter`.
- Added `google_groups.display_name`, `settings_confirmed_at` and
  `settings_confirmed_by`.
- Added `reserve_group_identity` and `rotate_group_identity`. Sequence, address,
  display name and URL name are generated server-side; clients cannot choose
  them. `reserve_group_identity` is internal-only and is called by
  `confirm_payment` and `rotate_group_identity`.
- Replaced `attach_group` with a 5-argument version that requires the exact
  reserved email, exact reserved display name, actual URL slug and explicit
  settings confirmation. The old 3-argument overload is dropped.
- `confirm_payment` now accepts `pending` / `awaiting_link` projects with no
  group, marks the fee paid and reserves the identity.
- Added `admin_dashboard.group_setup` for paid projects waiting for a group, and
  widened the unpaid payments queue to `pending` and `awaiting_link`. Groups now
  return display name and settings-confirmed time.
- Added the five-item manual settings checklist to TesterLoop Admin and a
  read-only reserved identity panel with copy actions, attach lock and an
  "Issue next number" rotation action.
- Developer copy now says the fee is due before group setup, and a paid/no-group
  project says operations is creating the group. Reserved identities are not
  exposed to developers.
- Moved `LinkLauncher` into `TesterLoop.Shared` and added
  `TryOpenGroupsHome()`, which opens only `https://groups.google.com/`. The app
  never guesses Google's group-creation URL.
- Rewrote `AdminViewModel.Tabs.cs` to remove corrupted glyph text; removed
  unused reserved fields from `AdminPaymentDto`; updated the admin shell subtitle.
- Added `sql/migrations/021_assisted_group_provisioning.sql`; mirrored the fields
  and functions into the greenfield schema and grants. Version bumped to `0.9.0`.

#### Files / Components
- `sql/migrations/021_assisted_group_provisioning.sql`
- `sql/schema/001_init.sql`, `sql/functions/004_queries.sql`,
  `sql/functions/005_mutations.sql`, `sql/seed/007_admin_bootstrap.sql`
- `src/TesterLoop.Shared/Core/LinkLauncher.cs`,
  `Core/Data/Contracts.cs`, `Core/Data/SupabaseService.cs`,
  `Core/AppConfig.cs`
- `src/TesterLoop.Admin/ViewModels/AdminViewModel.cs`,
  `AdminViewModel.GroupSetup.cs` (new), `AdminViewModel.Payments.cs`,
  `AdminViewModel.Tabs.cs`, `AdminRows.cs`, `AdminShellViewModel.cs`
- `src/TesterLoop.Admin/Views/AdminOperationsView.xaml`
- `src/TesterLoop.Desktop/Core/LinkLauncher.cs` (removed; now shared)
- `src/TesterLoop.Desktop/ViewModels/DeveloperViewModel.Detail.cs`,
  `DeveloperViewModel.Payments.cs`, `DeveloperViewModel.Projects.cs`
- `src/TesterLoop.Desktop/Views/DeveloperProjectDetailView.xaml`
- `src/TesterLoop.Desktop/TesterLoop.Desktop.csproj`,
  `src/TesterLoop.Admin/TesterLoop.Admin.csproj`
- `installer/TesterLoop.iss`, `installer/TesterLoop.Admin.iss`
- `AGENTS.md`, `AGENTS_PLAN.md`, `medial_support.txt`

#### Important Notes
- Group address limit: local part max `63`. Display name limit: `73`. Tokens are
  lower-case ASCII, capped at `23` characters each, with `app` / `company`
  fallbacks.
- Generated address is `[project]_[company]_testteam_[sequence]@googlegroups.com`.
  The sequence is per developer, zero-padded to three digits, and collides are
  auto-incremented. The suggested URL name is the email local part; operations
  may correct it to the real Google Groups slug.
- Google's consumer-group API cannot create or list groups, so the group is still
  manual. Browser automation was rejected for ToS, 2FA/CAPTCHA and credential
  risks.
- "Who can modify group details" has no confirmed Groups Settings API field, so
  the checklist is an operations attestation, not a verification.
- SQL review found no blocking issue. `reserve_group_identity` is revoked from
  `public` / `anon` / `authenticated`; `rotate_group_identity`, `attach_group`
  and `confirm_payment` require admin and are granted only to `authenticated`.
  The all-or-none reservation constraint and unique indexes match the generated
  values. `021` must run after `020`, and the admin client and SQL must deploy
  together because the attach signature changed.
- Verification: Release build 0 warnings / 0 errors. A temporary WPF harness at
  `C:\Users\Nwick\AppData\Local\Temp\opencode\TesterLoop.AdminHarness` loaded
  `AdminView` with seeded group-setup/payment data across all seven tabs and
  reported `BINDING_COUNT=0`.
- Published and packaged `0.9.0` for both apps and both architectures:
  - `build/win-x86/TesterLoop.exe` 141,824 bytes, file `0.9.0.0`, PE `0x14C`
  - `build/win-x64/TesterLoop.exe` 172,544 bytes, file `0.9.0.0`, PE `0x8664`
  - `build/admin-win-x86/TesterLoopAdmin.exe` 141,824 bytes, file `0.9.0.0`
  - `build/admin-win-x64/TesterLoopAdmin.exe` 172,544 bytes, file `0.9.0.0`
  - `build/win-x86/TesterLoop-Setup-x86.exe` 45,159,544 bytes
  - `build/win-x64/TesterLoop-Setup-x64.exe` 50,051,021 bytes
  - `build/admin-win-x86/TesterLoop-Admin-Setup-x86.exe` 45,079,289 bytes
  - `build/admin-win-x64/TesterLoop-Admin-Setup-x64.exe` 49,954,330 bytes
  All four executables start, keep responsive windows titled `TesterLoop` /
  `TesterLoop Admin`, and were stopped after the check. All four installers report
  product version `0.9.0`.
- Not verified live: reservation, rotation, attach lock, settings attestation and
  the developer copy, because `017`-`021` have not been applied and no live
  operations account was used this round. SQL was reviewed statically only; no
  local Postgres, `psql`, `supabase` or `deno` CLI is available.
- Security: no secrets or endpoints were added. The per-developer counter is
  advanced under row locks; the campaign holds the reservation and clients never
  choose a group identity. Installers remain unsigned and have not been run end to
  end.

### Modification 034

Date: 2026-11-03

#### Changes
- Added assisted availability checking and automatic attach for Google Group
  setup. Payment still reserves the exact identity; operations can now check the
  reserved address through the Apps Script checker, open Google's group creation
  page in one click, then verify and attach the group in one action.
- Added campaign provisioning fields `group_provision_state` (`not_checked`,
  `available`, `taken`, `unknown`, `failed`, `created`),
  `group_provision_checked_at` and `group_provision_error`.
- Added the `sync_campaign_group_provision_state` trigger. It resets the check
  state when the reserved identity changes and marks a campaign `created` when a
  group is attached.
- Added admin-only `record_group_check(p_campaign_id, p_state, p_error)`. It
  requires a paid campaign with a reservation, writes the state and an audit row,
  and returns the check result.
- Extended `admin_dashboard.group_setup` with the provisioning fields. Migration
  `022` uses an `admin_dashboard_base()` wrapper instead of copying the large
  dashboard body; the wrapper also works on a fresh install.
- Added Apps Script actions `check_availability` and `verify_group` alongside the
  existing `membership` check. The script now requires `groupName` for every
  action, checks the public group page with redirects disabled, and reports
  `taken`, `available`, `unknown`, `exists` or `missing`.
- Added the `provision-group` Edge Function. It verifies the caller is operations,
  reads the reserved identity with the service role, applies a 10-second check
  cooldown, calls Apps Script, records the check, and attaches the exact reserved
  identity on a successful verify.
- Admin Operations now shows a provisioning status panel with `Check
  availability`, `Open group create page`, `Verify and attach`, `Attach without
  check`, `Issue next number`, a copy action for the reserved URL name and a
  direct link label. The manual attach fallback remains.
- Confirming a payment now triggers an availability check with the returned
  reserved URL name. A check failure does not undo the payment; it leaves the
  paid state intact and appends a toast.
- Added `LinkLauncher.TryOpenGroupCreate()` for
  `https://groups.google.com/g/create`.
- Mirrored the greenfield schema, queries, mutations and grants.
- Version bumped to `0.10.0` in `AppConfig`, both projects and both installers.

#### Files / Components
- `sql/migrations/022_group_provision_automation.sql` (new)
- `sql/schema/001_init.sql`, `sql/functions/004_queries.sql`,
  `sql/functions/005_mutations.sql`, `sql/seed/007_admin_bootstrap.sql`
- `google-apps-script/group-check/Code.gs`, `appsscript.json`, `README.md`
- `supabase/functions/provision-group/index.ts` (new)
- `src/TesterLoop.Shared/Core/Data/Contracts.cs`,
  `src/TesterLoop.Shared/Core/Data/SupabaseService.GroupProvision.cs` (new),
  `src/TesterLoop.Shared/Core/LinkLauncher.cs`
- `src/TesterLoop.Admin/ViewModels/AdminViewModel.GroupAutomation.cs` (new),
  `AdminViewModel.GroupSetup.cs`, `AdminViewModel.Payments.cs`, `AdminRows.cs`
- `src/TesterLoop.Admin/Views/AdminOperationsView.xaml`
- `src/TesterLoop.Shared/Core/AppConfig.cs`,
  `src/TesterLoop.Desktop/TesterLoop.Desktop.csproj`,
  `src/TesterLoop.Admin/TesterLoop.Admin.csproj`
- `installer/TesterLoop.iss`, `installer/TesterLoop.Admin.iss`
- `AGENTS.md`, `AGENTS_PLAN.md`, `medial_support.txt`

#### Important Notes
- Availability is best effort. Google returns 200 for the public create page and
  302 to `/access-error` for an address it will not show. A private existing group
  can therefore appear `available`; the Google create page is the final authority.
- The app still does not create a group automatically. It checks availability,
  opens the Google create page in the default browser, and verifies/attaches after
  operations creates the group by hand.
- The Apps Script account must be able to see the created group. Otherwise
  `verify_group` returns `missing` with instructions to sign in to
  groups.google.com with that account.
- `provision-group` uses `404` only when the function is not deployed; campaign
  missing or missing group is `409`, cooldown is `429`, an unavailable checker is
  `503`, and a bad Google response is `502`.
- `record_group_check` and `admin_dashboard_base` are revoked from clients;
  `record_group_check` is granted to `authenticated` and still calls
  `require_admin()`.
- Deployment: apply `017` -> `018` -> `019` -> `020` -> `021` -> `022`, redeploy
  the Apps Script web app as a new version, then deploy `provision-group` with the
  existing `GROUP_CHECK_URL` and `GROUP_CHECK_SECRET`.
- Verification: Release build 0 warnings / 0 errors. The WPF harness loaded
  `AdminView` with seeded group-setup data and reported `BINDING_COUNT=0`.
  Published all four `0.10.0` executables and compiled all four installers.
- Published outputs: `build/win-x86/TesterLoop.exe` 141,824 bytes (file
  `0.10.0.0`, PE `0x14C`), `build/win-x64/TesterLoop.exe` 172,544 bytes (PE
  `0x8664`), `build/admin-win-x86/TesterLoopAdmin.exe` 141,824 bytes (PE `0x14C`)
  and `build/admin-win-x64/TesterLoopAdmin.exe` 172,544 bytes (PE `0x8664`).
- Installers: `build/win-x86/TesterLoop-Setup-x86.exe` 45,161,257 bytes,
  `build/win-x64/TesterLoop-Setup-x64.exe` 50,052,452 bytes,
  `build/admin-win-x86/TesterLoop-Admin-Setup-x86.exe` 45,084,377 bytes and
  `build/admin-win-x64/TesterLoop-Admin-Setup-x64.exe` 49,957,891 bytes, all
  product version `0.10.0`.
- Not verified live: the check, verify/attach round-trip, post-payment auto-check
  and the new UI, because `017`-`022` have not been applied and `provision-group`
  is not deployed.
- Launch smoke test: all four `0.10.0` executables start, keep responsive windows
  titled `TesterLoop` / `TesterLoop Admin`, and were stopped after the check.
- SQL and Edge Function code were reviewed statically only; no local Postgres,
  `psql`, `supabase` or `deno` CLI is available.
- Security: no secrets were added to a client. `GROUP_CHECK_URL` and
  `GROUP_CHECK_SECRET` remain Edge secrets; the Apps Script secret remains a
  script property. The launcher accepts only validated Google Groups or Play
  URLs. Installers remain unsigned and have not been run end to end.

### Modification 035

Date: 2026-11-03

#### Changes
- Fixed the post-payment hand-off. Confirming the $15 fee now selects that
  project in the group setup queue and opens Google's group creation page in the
  default browser automatically. The reserved address and display name remain on
  screen with copy actions.
- Added the missing explanation to Admin Operations: Google has no create API for
  personal `@gmail.com` groups, so the app cannot create the group itself. The
  payment reserves the identity and opens the one page operations must complete.
- The automatic availability check still runs after payment and is appended to the
  toast; a failed check never undoes the payment.
- Version bumped to `0.10.1` in `AppConfig`, both projects, both installers and
  `medial_support.txt`.

#### Files / Components
- `src/TesterLoop.Admin/ViewModels/AdminViewModel.Payments.cs`
- `src/TesterLoop.Admin/Views/AdminOperationsView.xaml`
- `src/TesterLoop.Shared/Core/AppConfig.cs`
- `src/TesterLoop.Desktop/TesterLoop.Desktop.csproj`,
  `src/TesterLoop.Admin/TesterLoop.Admin.csproj`
- `installer/TesterLoop.iss`, `installer/TesterLoop.Admin.iss`
- `AGENTS.md`, `AGENTS_PLAN.md`, `medial_support.txt`

#### Important Notes
- A consumer `@gmail.com` group cannot be created through any Google API. The
  Admin SDK `groups.insert()` path needs a Google Workspace domain and a
  super-admin; otherwise the create page is the only supported route.
- Auto-opening the browser only happens after the payment RPC succeeds. If the
  browser cannot start, the payment remains recorded and the same page can be
  opened with `Open create page`.
- Verification: Release build 0 warnings / 0 errors. The WPF harness loaded
  `AdminView` with seeded group-setup data and reported `BINDING_COUNT=0`.
- Published and packaged `0.10.1` for both apps and both architectures:
  - `build/win-x86/TesterLoop.exe` 141,824 bytes, file `0.10.1.0`, PE `0x14C`
  - `build/win-x64/TesterLoop.exe` 172,544 bytes, file `0.10.1.0`, PE `0x8664`
  - `build/admin-win-x86/TesterLoopAdmin.exe` 141,824 bytes, file `0.10.1.0`
  - `build/admin-win-x64/TesterLoopAdmin.exe` 172,544 bytes, file `0.10.1.0`
  - `build/win-x86/TesterLoop-Setup-x86.exe` 45,161,455 bytes
  - `build/win-x64/TesterLoop-Setup-x64.exe` 50,052,017 bytes
  - `build/admin-win-x86/TesterLoop-Admin-Setup-x86.exe` 45,084,450 bytes
  - `build/admin-win-x64/TesterLoop-Admin-Setup-x64.exe` 49,958,191 bytes
  All four installers report product version `0.10.1`.
- Launch smoke test: all four executables start, keep responsive windows titled
  `TesterLoop` / `TesterLoop Admin`, and were stopped after the check.
- Not verified live: the post-payment browser hand-off and the `0.10.1` text,
  because no live operations account or payment was used this round.
- No SQL, RPC, Edge Function, deployment or secret changed. Installers remain
  unsigned and have not been run end to end.

### Modification 036

Date: 2026-11-03

#### Changes
- Reverted Google Group availability checking, automatic verification and
  automatic attach. Payment still reserves the exact identity; confirming the fee
  now selects that project in the group-setup queue, and operations completes the
  remaining steps by hand.
- Deleted the local `provision-group` Edge Function. Groups are still created and
  attached manually; the app opens Google's create page but never claims to create
  or verify a group.
- Reduced the Apps Script checker to the `membership` action. Removed
  `check_availability`, `verify_group`, the group-page fetch and the
  `script.external_request` scope.
- Removed `group_provision_state`, `group_provision_checked_at`,
  `group_provision_error`, the sync trigger and `record_group_check` from the
  greenfield schema and functions. Added
  `sql/migrations/023_revert_group_automation.sql` for the live project.
- Marked migration `022` as superseded. Fresh installs run `001`-`007`, `008`-`021`
  and `023`, skipping `022`.
- Removed the provisioning DTO fields, service, command wiring and Operations
  status panel. Kept reservation, rotation, copy actions, settings checklist,
  manual attach and `Open group create page`.
- Corrected the payment helper copy to name the actual `Open create page` button
  and the manual create/confirm/attach hand-off.
- Version bumped to `0.10.2` in `AppConfig`, both projects, both installers and
  `medial_support.txt`.

#### Files / Components
- `sql/migrations/023_revert_group_automation.sql` (new)
- `sql/migrations/022_group_provision_automation.sql` (superseded)
- `sql/schema/001_init.sql`, `sql/functions/004_queries.sql`,
  `sql/functions/005_mutations.sql`, `sql/seed/007_admin_bootstrap.sql`
- `google-apps-script/group-check/Code.gs`, `appsscript.json`, `README.md`
- Removed: `supabase/functions/provision-group/`
- `src/TesterLoop.Shared/Core/Data/Contracts.cs`
- Removed: `src/TesterLoop.Shared/Core/Data/SupabaseService.GroupProvision.cs`
- `src/TesterLoop.Admin/ViewModels/AdminViewModel.cs`,
  `AdminViewModel.GroupSetup.cs`, `AdminViewModel.Payments.cs`, `AdminRows.cs`
- Removed: `src/TesterLoop.Admin/ViewModels/AdminViewModel.GroupAutomation.cs`
- `src/TesterLoop.Admin/Views/AdminOperationsView.xaml`
- `src/TesterLoop.Shared/Core/AppConfig.cs`,
  `src/TesterLoop.Desktop/TesterLoop.Desktop.csproj`,
  `src/TesterLoop.Admin/TesterLoop.Admin.csproj`
- `installer/TesterLoop.iss`, `installer/TesterLoop.Admin.iss`
- `AGENTS.md`, `AGENTS_PLAN.md`, `medial_support.txt`

#### Important Notes
- Confirming the fee no longer opens a browser. It records the payment, selects
  the paid project and tells operations to use `Open group create page`, complete
  the settings checklist and press `Attach group`.
- `023` renames `admin_dashboard_base()` back to `admin_dashboard()` when `022`
  was applied, restores its grants, drops the automation objects, drops the three
  columns and reloads the PostgREST schema cache. It is safe when `022` was never
  applied because every automation drop is `if exists`.
- The owner must run `023` after `021`, redeploy the Apps Script web app as a new
  version and delete the deployed `provision-group` Edge Function. The local
  function folder is already gone.
- `verify-opt-in`, `record_verified_opt_in` and `GROUP_CHECK_URL` /
  `GROUP_CHECK_SECRET` are unchanged. The Apps Script still performs the direct
  membership check.
- Verification: Release build 0 warnings / 0 errors. The WPF harness loaded
  `AdminView` with seeded reservation data and reported `BINDING_COUNT=0`.
- Published and packaged `0.10.2` for both apps and both architectures:
  - `build/win-x86/TesterLoop.exe` 141,824 bytes, file `0.10.2.0`, PE `0x14C`
  - `build/win-x64/TesterLoop.exe` 172,544 bytes, file `0.10.2.0`, PE `0x8664`
  - `build/admin-win-x86/TesterLoopAdmin.exe` 141,824 bytes, file `0.10.2.0`
  - `build/admin-win-x64/TesterLoopAdmin.exe` 172,544 bytes, file `0.10.2.0`
  - `build/win-x86/TesterLoop-Setup-x86.exe` 45,160,200 bytes
  - `build/win-x64/TesterLoop-Setup-x64.exe` 50,050,090 bytes
  - `build/admin-win-x86/TesterLoop-Admin-Setup-x86.exe` 45,081,216 bytes
  - `build/admin-win-x64/TesterLoop-Admin-Setup-x64.exe` 49,954,069 bytes
  All four installers report product version `0.10.2`.
- Launch smoke test: all four executables start, keep responsive windows titled
  `TesterLoop` / `TesterLoop Admin`, and were stopped after the check.
- Not verified live: `023`, the membership-only Apps Script redeploy, deletion of
  the deployed Edge Function and the manual attach flow. SQL and TypeScript were
  reviewed statically only; no local Postgres, `psql`, `supabase` or `deno` CLI is
  available.
- Security: no secrets or endpoints were added. Removing the Edge Function reduces
  the privileged surface. Installers remain unsigned and have not been run end to
  end.

### Modification 037

Date: 2026-11-04

#### Changes
- Fixed the Android tester app "Opt out of this project" failure. Tapping Opt out
  threw `Parameter type must not include a type variable or wildcard:
  java.util.Map<java.lang.String,?> (parameter#3) for method
  SupabaseApi.setOptIn` before any request was sent.
- Cause: `set_opt_in` was the only Retrofit method with a `Map<String, Any>` body.
  Kotlin compiles `Map<String, Any>` to `Map<String, ? extends Object>` because
  `Map` is declared `out V`, and Retrofit refuses wildcard parameter types. The
  error surfaced lazily on first call, so sign-in and the rest of the app worked.
- Added the typed `SetOptInRequest(p_campaign_id, p_opted_in)` Moshi model with
  `@JsonClass(generateAdapter = true)`.
- `SupabaseApi.setOptIn` now takes `SetOptInRequest`, and `AppVm.optOut` sends it.
  `Map<String, String>` bodies elsewhere are unchanged: `String` is final, so
  Kotlin emits `Map<String, String>` with no wildcard (verified with `javap`).
- Android version bumped to `1.0.2` (`versionCode 10002`).

#### Files / Components
- `mobile/app/src/main/kotlin/com/testerloop/app/data/api/Models.kt`
- `mobile/app/src/main/kotlin/com/testerloop/app/data/api/SupabaseApi.kt`
- `mobile/app/src/main/kotlin/com/testerloop/app/ui/AppVm.Actions.kt`
- `mobile/app/build.gradle.kts`
- `AGENTS.md`, `AGENTS_PLAN.md`, `medial_support.txt`

#### Important Notes
- The server RPC was verified directly: an authenticated tester call to
  `set_opt_in` with a random campaign returns `400 "Join this project before
  recording an opt-in."`, so the grant and function are healthy. The failure was
  purely client-side request serialisation.
- Verification: `:app:assembleDebug`, `:app:assembleRelease` and `:app:lintDebug`
  succeed. `javap` on the compiled `SupabaseApi` confirms `setOptIn` now takes
  `SetOptInRequest` (no wildcard) while the remaining `Map<String, String>`
  parameters compile without wildcards.
- Deliverables: `build/android/TesterLoop-Mobile-1.0.2-debug.apk`
  (18,814,810 bytes) and `build/android/TesterLoop-Mobile-1.0.2-release-unsigned.apk`
  (12,982,076 bytes). The debug APK reports package `com.testerloop.app`,
  `versionCode 10002`, `versionName 1.0.2`, `compileSdk`/`targetSdk` 36, label
  `TesterLoop`. The release APK is unsigned.
- The superseded `1.0.1` APK copies were removed from `build/android`.
- Not verified on a device: the opt-out round-trip. No device or accelerated
  emulator is available in this environment.
- QA artefact left in Supabase: tester account `qa.optout.e43aa5a4ee@example.com`
  (`9629c566-2651-453a-bafc-770e091b6112`). It joined no campaign and consumed no
  seat; delete it from the Dashboard when convenient.
- Security: no secrets, endpoints, RPC grants or server rules changed. Only the
  request body type on an existing authenticated RPC changed.

### Modification 038

Date: 2026-11-04

#### Changes
- Made opt-in confirmation mobile-only. The Windows tester workspace no longer
  offers a Confirm opt-in action.
  - `SetOptInAsync` is now a leave action: it asks for confirmation, calls
    `set_opt_in(false)`, removes the seat from `MY CAMPAIGNS`, reloads and shows
    "You left <app>. Your seat is free. Confirm opt-in in the TesterLoop mobile
    app."
  - Joined rows show `Joined` and the note "Confirm opt-in in the TesterLoop
    mobile app"; the button reads `Leave project` until opted in and `Opt out`
    afterwards.
  - The tester workspace caption now points to the mobile app for confirmation.
  - Deleted `SupabaseService.OptIn.cs` and the unused `VerifiedOptInDto`; the
    desktop client no longer calls the `verify-opt-in` Edge Function.
- Removed the Google Group row and `Open Google Group` button from the mobile
  campaign access card. Join still opens the stored group page in the browser,
  which remains the only group hand-off.
- The mobile Confirm opt-in action now requires Usage Access:
  - Without it, the campaign page shows a warning banner and an
    `Allow usage access` button, and `confirmOptIn` refuses with an explanation
    before any network call.
  - Returning from Android settings refreshes the state through the new
    `LifecycleEventEffect(ON_RESUME)` on the campaign page, and entering the page
    re-reads Usage Access and loads the campaign.
- A successful mobile opt-in now reloads the dashboard and opens the campaign's
  Play test link automatically when the stored link is valid, with the message
  "Google Group membership confirmed. Opening the Play test."
- Removed the unused mobile `openGroup` helper; `GroupLink` is still used by Join.
- Version bumped to `1.0.3` (`versionCode 10003`) for Android and `0.10.3` for the
  shared config, both Windows projects and both installers.

#### Files / Components
- `mobile/app/src/main/kotlin/com/testerloop/app/ui/campaign/CampaignSections.kt`
- `mobile/app/src/main/kotlin/com/testerloop/app/ui/campaign/CampaignScreen.kt`
- `mobile/app/src/main/kotlin/com/testerloop/app/ui/AppVm.Actions.kt`
- `mobile/app/build.gradle.kts`
- `src/TesterLoop.Desktop/ViewModels/TesterViewModel.Actions.cs`,
  `TesterViewModel.cs`
- `src/TesterLoop.Desktop/Views/TesterWorkspaceView.xaml`
- Removed: `src/TesterLoop.Shared/Core/Data/SupabaseService.OptIn.cs`
- `src/TesterLoop.Shared/Core/Data/Contracts.cs`
- `src/TesterLoop.Shared/Core/AppConfig.cs`,
  `src/TesterLoop.Desktop/TesterLoop.Desktop.csproj`,
  `src/TesterLoop.Admin/TesterLoop.Admin.csproj`
- `installer/TesterLoop.iss`, `installer/TesterLoop.Admin.iss`
- `AGENTS.md`, `AGENTS_PLAN.md`, `medial_support.txt`

#### Important Notes
- `set_opt_in(false)` accepts both `joined` and `opted_in` seats, so the desktop
  leave path works before and after a verified opt-in. A true attestation is
  still refused server-side; only the Edge Function may confirm a seat.
- The mobile usage gate is a client rule for the confirmation action. Usage
  evidence remains optional for the seat itself; the server still decides
  membership and seat release.
- The campaign page is a separate navigation destination from the shell, so it
  needed its own resume refresh; the shell's existing refresh does not cover it.
- Verification: `dotnet build TesterLoop.sln -c Release` succeeded with 0
  warnings / 0 errors. Android `:app:assembleDebug :app:assembleRelease
  :app:lintDebug` succeeded. Publishing needed one running `TesterLoop` process
  (pid 9856) stopped before `build\win-x64` could be rewritten.
- Artifacts:
  - `build/win-x86/TesterLoop.exe` 141,824 bytes, file `0.10.3.0`, PE `0x14C`
  - `build/win-x64/TesterLoop.exe` 172,544 bytes, file `0.10.3.0`, PE `0x8664`
  - `build/admin-win-x86/TesterLoopAdmin.exe` 141,824 bytes, file `0.10.3.0`,
    PE `0x14C`
  - `build/admin-win-x64/TesterLoopAdmin.exe` 172,544 bytes, file `0.10.3.0`,
    PE `0x8664`
  - `build/win-x86/TesterLoop-Setup-x86.exe` 45,159,011 bytes
  - `build/win-x64/TesterLoop-Setup-x64.exe` 50,049,257 bytes
  - `build/admin-win-x86/TesterLoop-Admin-Setup-x86.exe` 45,079,792 bytes
  - `build/admin-win-x64/TesterLoop-Admin-Setup-x64.exe` 49,952,726 bytes
  All four installers report product version `0.10.3`.
  - `build/android/TesterLoop-Mobile-1.0.3-debug.apk` 18,814,810 bytes and
    `build/android/TesterLoop-Mobile-1.0.3-release-unsigned.apk` 12,982,076
    bytes. The debug APK reports package `com.testerloop.app`,
    `versionCode 10003`, `versionName 1.0.3`, `minSdk 24`, `targetSdk 36`, label
    `TesterLoop`. The release APK is unsigned. The superseded `1.0.2` copies were
    removed.
- Not verified: the mobile Usage Access gate, the automatic Play hand-off and the
  desktop leave action on live data. No device or accelerated emulator is
  available, and `017`-`023` plus the membership-only Apps Script redeploy are
  still owed by the owner.
- No SQL, RPC, Edge Function, grant or secret changed. The only server call
  removed is the desktop's `verify-opt-in` request, which narrows the client
  surface. Testers still see only their own data, and developers still never see
  tester email addresses.
- QA artefact still owed for deletion: tester
  `qa.optout.e43aa5a4ee@example.com` (`9629c566-2651-453a-bafc-770e091b6112`).

### Modification 039

Date: 2026-11-04

#### Changes
- Added a `Sign in as` dropdown to the TesterLoop Windows login with `Developer`
  and `Tester`. One account can use both workspaces; the missing profile is
  created on first use, so a second registration is not needed.
- Added `ensure_account_role(p_role)`, authenticated-only:
  - rejects admins, an unknown role and a missing account/profile;
  - creates the missing `developers` or `testers` row from the existing profile
    name and Google address, with safe defaults;
  - leaves an existing role row untouched;
  - writes `account.role_added` to the audit log.
- `whoami()` now always returns both `developer_id` and `tester_id`. The client
  keeps `profiles.role` as the account's primary role, then overrides
  `Account.Role` with the role chosen at sign-in.
- Windows sign-in gained `SignInAsync(email, password, selectedRole)`. It
  authenticates, reads `whoami`, calls `ensure_account_role` only when the
  selected role id is absent, then reads `whoami` again. Reading `whoami` first
  preserves the existing `claim_profile` repair for auth users with no profile;
  the plain overload stays for TesterLoop Admin.
- TesterLoop Mobile now treats any non-admin account as a tester: it calls
  `ensure_account_role('tester')` when `tester_id` is absent and gates on
  `tester_id` rather than the primary `profile.role`. The mobile UI remains the
  tester workspace only.
- Added Typed `EnsureRoleRequest` for Retrofit; no wildcard request body.
- Added `sql/migrations/024_dual_role_accounts.sql`; mirrored the new function
  and both-role `whoami` into the greenfield SQL and bootstrap grants.
- Version bumped to `0.11.0` desktop and `1.1.0` (`versionCode 10100`) Android.

#### Files / Components
- `sql/functions/003_auth.sql`, `sql/seed/007_admin_bootstrap.sql`
- `sql/migrations/024_dual_role_accounts.sql` (new)
- `src/TesterLoop.Shared/Core/Data/SupabaseService.cs`,
  `SupabaseService.Auth.cs` (new)
- `src/TesterLoop.Desktop/ViewModels/LoginViewModel.cs`,
  `Views/LoginView.xaml`
- `mobile/app/src/main/kotlin/com/testerloop/app/data/api/Models.kt`,
  `SupabaseApi.kt`
- `mobile/app/src/main/kotlin/com/testerloop/app/ui/AppVm.kt`,
  `ui/auth/AuthScreen.kt`
- `src/TesterLoop.Shared/Core/AppConfig.cs`,
  `src/TesterLoop.Desktop/TesterLoop.Desktop.csproj`,
  `src/TesterLoop.Admin/TesterLoop.Admin.csproj`
- `mobile/app/build.gradle.kts`
- `installer/TesterLoop.iss`, `installer/TesterLoop.Admin.iss`
- `AGENTS.md`, `AGENTS_PLAN.md`, `medial_support.txt`

#### Important Notes
- `profiles.role` is unchanged and still records the signup role. It is used for
  display and audit, not for access. `current_developer_id()` and
  `current_tester_id()` already read their own tables, so a dual-role account is
  authorised correctly in SQL.
- `write_audit` still labels actions with the primary `profiles.role`. A tester
  acting as a developer is therefore shown under the tester role in the audit
  log; the role is not a security boundary.
- The tester Google address is unique. If the account's address is already linked
  to another tester, adding tester role fails with
  "That Google account is already linked to another tester." Adding developer
  role is not blocked by the tester table.
- Developer defaults: company name falls back to `<display name> Studio` (or
  `TesterLoop Studio`), contact email to the sign-in email, Google email to the
  account's known Google address.
- Admin accounts cannot add either role and the admin app still uses the plain
  sign-in.
- The new capability is deliberate but broad: any non-admin account can now
  create projects. The existing $15 payment gate and operations activation still
  apply, and no project goes live without review.
- `024` must run after `023`. Until it runs, the login dropdown still authenticates
  but `ensure_account_role` returns `404`, so the app shows that error instead of
  opening the workspace.
- Verification: `dotnet build TesterLoop.sln -c Release` 0 warnings / 0 errors.
  Android `:app:assembleDebug`, `:app:assembleRelease` and `:app:lintDebug`
  succeeded; lint reports 0 errors, 24 warnings and 1 hint. Sign-in helpers were
  moved into `SupabaseService.Auth.cs` so every C# file stays under 300 lines;
  the solution, published apps and both installers were rebuilt after the split
  and again after the claim-preserving sign-in order was added.
- UI Automation on the published x64 app found one ComboBox on the login screen,
  default `Developer`, with exactly `Developer` and `Tester`; selecting `Tester`
  updated the selection.
- Published and packaged `0.11.0` for both apps and both architectures:
  - `build/win-x86/TesterLoop.exe` 141,824 bytes, file `0.11.0.0`, PE `0x14C`
  - `build/win-x64/TesterLoop.exe` 172,544 bytes, file `0.11.0.0`, PE `0x8664`
  - `build/admin-win-x86/TesterLoopAdmin.exe` 141,824 bytes, file `0.11.0.0`,
    PE `0x14C`
  - `build/admin-win-x64/TesterLoopAdmin.exe` 172,544 bytes, file `0.11.0.0`,
    PE `0x8664`
  - `build/win-x86/TesterLoop-Setup-x86.exe` 45,159,117 bytes
  - `build/win-x64/TesterLoop-Setup-x64.exe` 50,049,388 bytes
  - `build/admin-win-x86/TesterLoop-Admin-Setup-x86.exe` 45,079,297 bytes
  - `build/admin-win-x64/TesterLoop-Admin-Setup-x64.exe` 49,953,053 bytes
  All four installers report product version `0.11.0`.
- Android: `build/android/TesterLoop-Mobile-1.1.0-debug.apk` 18,814,810 bytes and
  `build/android/TesterLoop-Mobile-1.1.0-release-unsigned.apk` 12,998,460 bytes.
  The debug APK reports package `com.testerloop.app`, `versionCode 10100`,
  `versionName 1.1.0`, `minSdk 24`, `targetSdk 36`, label `TesterLoop`. The
  release APK is unsigned; the superseded `1.0.3` copies were removed.
- Not verified live: `ensure_account_role`, the dual-role sign-in round-trip and
  mobile tester-role creation, because `024` has not been applied and no device
  or accelerated emulator is available. SQL was reviewed statically only; no
  local Postgres, `psql`, `supabase` or `deno` CLI is available.
- Security: `ensure_account_role` is `security definer`, rejects admins,
  is revoked from `public` / `anon` and granted only to `authenticated`. Only the
  publishable anon key ships. Installers remain unsigned and have not been run
  end to end.
- QA artefact from an earlier round still owed for deletion:
  `qa.optout.e43aa5a4ee@example.com`
  (`9629c566-2651-453a-bafc-770e091b6112`).

### Modification 040

Date: 2026-11-04

#### Changes
- Added a TesterLoop Mobile promotion to the Windows tester workspace. The card
  explains what the mobile app does, records that no public download link is
  configured, and provides `Copy install request` so the tester can send a
  ready-written request to operations.
- Added automatic mobile device capture. TesterLoop Mobile reports a normalised
  `Build.MANUFACTURER` + `Build.MODEL` label through the new authenticated RPC
  `record_tester_device(p_device_name)`.
- Added `testers.mobile_device_name` and `testers.mobile_device_seen_at`. The
  Windows tester workspace and profile now show the phone model read-only, and
  the tester profile page no longer accepts manual device names.
- Desktop report filing now defaults the device from the mobile-captured model
  (falling back to a legacy stored device) and the field is read-only.
- Mobile syncs the device after each dashboard load. A failure is shown on the
  Profile page as `deviceError` instead of failing the dashboard or being
  silently ignored.
- Added `sql/migrations/025_mobile_device_type.sql`; mirrored the columns, RPC,
  dashboard fields and grants in the greenfield SQL and bootstrap.
- Version bumped to `0.11.1` for both Windows apps and `1.1.1`
  (`versionCode 10101`) for Android.

#### Files / Components
- `sql/schema/001_init.sql`
- `sql/functions/004_queries.sql`, `sql/functions/006_tester_actions.sql`
- `sql/seed/007_admin_bootstrap.sql`
- `sql/migrations/025_mobile_device_type.sql` (new)
- `src/TesterLoop.Shared/Core/Data/Contracts.cs`
- `src/TesterLoop.Desktop/ViewModels/TesterViewModel.cs`,
  `TesterViewModel.Mobile.cs` (new), `TesterViewModel.Profile.cs`
- `src/TesterLoop.Desktop/Views/TesterWorkspaceView.xaml`,
  `TesterProfileView.xaml`
- `mobile/app/src/main/kotlin/com/testerloop/app/core/DeviceInfo.kt` (new)
- `mobile/app/src/main/kotlin/com/testerloop/app/data/api/Models.kt`,
  `SupabaseApi.kt`
- `mobile/app/src/main/kotlin/com/testerloop/app/ui/UiState.kt`, `AppVm.kt`,
  `AppVm.Device.kt` (new), `AppVm.Profile.kt`, `profile/ProfileScreen.kt`
- `src/TesterLoop.Shared/Core/AppConfig.cs`,
  `src/TesterLoop.Desktop/TesterLoop.Desktop.csproj`,
  `src/TesterLoop.Admin/TesterLoop.Admin.csproj`
- `mobile/app/build.gradle.kts`
- `installer/TesterLoop.iss`, `installer/TesterLoop.Admin.iss`
- `AGENTS.md`, `AGENTS_PLAN.md`, `medial_support.txt`

#### Important Notes
- `record_tester_device` is authenticated-only, `security definer`, updates the
  seen timestamp on every report, and writes `tester.device_reported` only when
  the label changes. It rejects an empty, over-120-character or control-character
  label.
- Device labels are not a security signal and are not used for access control.
- Scope note: the developer roster and admin tester detail still read legacy
  `devices`. The mobile-captured model is shown on the tester workspace/profile
  and used by desktop report filing.
- No public TesterLoop Mobile download URL exists, so the desktop card must not
  present a fake Play Store link. The copy action tells the tester to request the
  install link from operations.
- `update_tester_profile` still requires `p_devices`; clients now send the
  existing stored list unchanged so legacy data is preserved.
- `mobile/app/src/main/kotlin/com/testerloop/app/ui/profile/ProfileScreen.kt`
  was replaced during editing and then rebuilt with the package declaration,
  real theme components and corrected imports. It compiles; review the file if
  the exact previous copy matters.
- Verification: `dotnet build TesterLoop.sln -c Release` 0 warnings / 0 errors.
  Android `:app:assembleDebug`, `:app:assembleRelease` and `:app:lintDebug`
  succeed; lint reports 0 errors, 24 warnings and 1 hint. `aapt` confirms both
  APKs are `com.testerloop.app`, `versionCode 10101`, `versionName 1.1.1`,
  `minSdk 24`, `targetSdk 36`.
- Published and packaged `0.11.1` for both Windows apps and both architectures:
  - `build/win-x86/TesterLoop.exe` 141,824 bytes, file `0.11.1.0`, PE `0x14C`
  - `build/win-x64/TesterLoop.exe` 172,544 bytes, file `0.11.1.0`, PE `0x8664`
  - `build/admin-win-x86/TesterLoopAdmin.exe` 141,824 bytes, file `0.11.1.0`
  - `build/admin-win-x64/TesterLoopAdmin.exe` 172,544 bytes, file `0.11.1.0`
  - `build/win-x86/TesterLoop-Setup-x86.exe` 45,160,046 bytes
  - `build/win-x64/TesterLoop-Setup-x64.exe` 50,050,623 bytes
  - `build/admin-win-x86/TesterLoop-Admin-Setup-x86.exe` 45,079,666 bytes
  - `build/admin-win-x64/TesterLoop-Admin-Setup-x64.exe` 49,953,484 bytes
  All four installers report product version `0.11.1`.
- Android artifacts: `build/android/TesterLoop-Mobile-1.1.1-debug.apk`
  (18,814,806 bytes) and
  `build/android/TesterLoop-Mobile-1.1.1-release-unsigned.apk` (12,998,456
  bytes). The superseded `1.1.0` copies were removed. The release APK is
  unsigned.
- Launch smoke test: all four `0.11.1` executables start, keep responsive
  windows titled `TesterLoop` / `TesterLoop Admin`, and were stopped after the
  check.
- Deployment: apply `025` after `024`, then rebuild/redeploy nothing else. The
  mobile APK must be installed for automatic device capture to work.
- Not verified live: the device round-trip, the copied install request and the
  mobile install promotion, because `024`/`025` have not been applied and no
  Android device or accelerated emulator is available.
- Security: only the publishable anon key ships. The new RPC is revoked from
  `public` / `anon` and granted only to `authenticated`. Installers remain
  unsigned and have not been run end to end.

### Modification 041

Date: 2026-11-05

#### Changes
- Removed the `Copy install request` button from the tester workspace
  `TEST ON MOBILE` card at the owner's request. The card keeps its description
  and now says "No public download link is configured. Ask operations for the
  install link." with no action button.
- Deleted `CopyInstallRequestCommand`, its `RelayCommand` field and the
  `CopyInstallRequest` clipboard handler from `TesterViewModel.Mobile.cs`, and
  removed the now-unused `System.Windows` and `TesterLoop.Desktop.Core` usings.
- No clipboard text, toast or inline error for this action remains.
- Version bumped to `0.11.2` in `AppConfig`, both projects and both installers.
  Android is unchanged at `1.1.1`.

#### Files / Components
- `src/TesterLoop.Desktop/Views/TesterWorkspaceView.xaml`
- `src/TesterLoop.Desktop/ViewModels/TesterViewModel.Mobile.cs`
- `src/TesterLoop.Shared/Core/AppConfig.cs`,
  `src/TesterLoop.Desktop/TesterLoop.Desktop.csproj`,
  `src/TesterLoop.Admin/TesterLoop.Admin.csproj`
- `installer/TesterLoop.iss`, `installer/TesterLoop.Admin.iss`
- `AGENTS.md`, `AGENTS_PLAN.md`, `medial_support.txt`

#### Important Notes
- Presentation-only change. No SQL, RPC, Edge Function, grant, secret or data
  model changed. The mobile device capture and the rest of the card are
  untouched.
- Verification: `dotnet build TesterLoop.sln -c Release` 0 warnings / 0 errors.
  A search of the two edited files finds no remaining `Copy install request` or
  `CopyInstallRequest` reference.
- Published and packaged `0.11.2` for both apps and both architectures:
  - `build/win-x86/TesterLoop.exe` 141,824 bytes, file `0.11.2.0`, PE `0x14C`
  - `build/win-x64/TesterLoop.exe` 172,544 bytes, file `0.11.2.0`, PE `0x8664`
  - `build/admin-win-x86/TesterLoopAdmin.exe` 141,824 bytes, file `0.11.2.0`,
    PE `0x14C`
  - `build/admin-win-x64/TesterLoopAdmin.exe` 172,544 bytes, file `0.11.2.0`,
    PE `0x8664`
  - `build/win-x86/TesterLoop-Setup-x86.exe` 45,160,019 bytes
  - `build/win-x64/TesterLoop-Setup-x64.exe` 50,049,533 bytes
  - `build/admin-win-x86/TesterLoop-Admin-Setup-x86.exe` 45,079,567 bytes
  - `build/admin-win-x64/TesterLoop-Admin-Setup-x64.exe` 49,953,360 bytes
  All four installers report product version `0.11.2`.
- Launch smoke test: all four `0.11.2` executables start, keep responsive
  windows titled `TesterLoop` / `TesterLoop Admin`, and were stopped after the
  check.
- A leftover `TesterLoop` process (pid 8724) held `build\win-x64` open and was
  stopped before republishing.
- Not verified: the visual result on the live tester workspace, because it needs
  a live tester account. Deployments `017`-`025` and the Android APK are
  unchanged by this round.
- Installers remain unsigned and have not been run end to end.

### Modification 042

Date: 2026-11-05

#### Changes
- Fixed corrupted report separators in the developer project detail. Three
  `Run` elements carried double-encoded mojibake (`U+00C3 U+201A U+00C2
  U+00B7`, rendered as `AA`-style text) instead of a middle dot. They now use
  the `&#183;` entity.
- Added inline feedback for the closed-test link `Open` and `Copy` actions.
  - New `LinkActionNote` / `HasLinkActionNote` on `DeveloperViewModel` and a
    partial file `DeveloperViewModel.Link.cs`.
  - `OpenLink` and `CopyOptIn` now write the failure reason directly under the
    buttons instead of only to the workspace error banner, which can be scrolled
    out of view.
  - The note clears when the selected project changes, on reload, and when a
    link is saved.
- Version bumped to `0.11.3` in `AppConfig`, both projects, both installers and
  `medial_support.txt`. Android stays at `1.1.1`.

#### Files / Components
- `src/TesterLoop.Desktop/Views/DeveloperProjectDetailView.xaml`
- `src/TesterLoop.Desktop/ViewModels/DeveloperViewModel.cs`,
  `DeveloperViewModel.Link.cs` (new)
- `src/TesterLoop.Shared/Core/AppConfig.cs`,
  `src/TesterLoop.Desktop/TesterLoop.Desktop.csproj`,
  `src/TesterLoop.Admin/TesterLoop.Admin.csproj`
- `installer/TesterLoop.iss`, `installer/TesterLoop.Admin.iss`
- `AGENTS.md`, `AGENTS_PLAN.md`, `medial_support.txt`

#### Important Notes
- The `Open` action uses the saved `play_opt_in_url`, not the unsaved text box.
  If no link is saved, the inline note now says "Save a testing link first, then
  press Open." instead of leaving the click with no visible result.
- No SQL, RPC, Edge Function, grant, secret or data model changed.
- Verification: Release build 0 warnings / 0 errors. A repository scan of
  `*.cs,*.xaml,*.kt,*.sql,*.md,*.txt` finds no remaining `U+00C2` / `U+00C3`
  sequences. Published and packaged `0.11.3`:
  - `build/win-x86/TesterLoop.exe` 141,824 bytes, file `0.11.3.0`, PE `0x14C`
  - `build/win-x64/TesterLoop.exe` 172,544 bytes, file `0.11.3.0`, PE `0x8664`
  - `build/admin-win-x86/TesterLoopAdmin.exe` 141,824 bytes, file `0.11.3.0`
  - `build/admin-win-x64/TesterLoopAdmin.exe` 172,544 bytes, file `0.11.3.0`
  - `build/win-x86/TesterLoop-Setup-x86.exe` 45,160,004 bytes
  - `build/win-x64/TesterLoop-Setup-x64.exe` 50,049,891 bytes
  - `build/admin-win-x86/TesterLoop-Admin-Setup-x86.exe` 45,079,101 bytes
  - `build/admin-win-x64/TesterLoop-Admin-Setup-x64.exe` 49,953,418 bytes
  All four installers report product version `0.11.3`.
- Not verified: the inline note and corrected separators on live report data,
  because no live developer account was used this round. Installers remain
  unsigned and have not been run end to end.

### Modification 043

Date: 2026-11-05

#### Changes
- Added `sql/maintenance/purge_test_accounts.sql`, a preview-first cleanup for
  the three documented QA accounts and everything attached to them:
  - `qa.smoke.1101231128@example.com` (tester);
  - `qa.nav.developer.1102@example.com` (developer) and project `Nav QA App`;
  - `qa.optout.e43aa5a4ee@example.com`
    (`9629c566-2651-453a-bafc-770e091b6112`, tester).
- The script targets an explicit list, never an email pattern. Step 1 is
  read-only and prints the accounts, developers, testers, campaigns, groups,
  seats, reports and audit rows that match. Step 2 deletes in one transaction:
  reports, seats, campaigns, Google Group rows, testers, developers, related
  audit rows, profiles, admins and finally `auth.users`. Step 3 verifies that
  every targeted kind is `0`.
- Mobile install/usage rows need no direct delete; they cascade from the deleted
  tester and campaign rows. Audit rows are removed when they were authored by a
  target account or mention a target id, campaign app name, seat, report or
  admin id.
- `notify pgrst, 'reload schema';` runs at the end so PostgREST drops any cached
  references.

#### Files / Components
- `sql/maintenance/purge_test_accounts.sql` (new)
- `AGENTS.md`, `AGENTS_PLAN.md`

#### Important Notes
- This environment has no Supabase service-role key, database connection,
  `psql`, `supabase` CLI or `deno`, so the script was reviewed statically but not
  executed. The owner must run Step 1, review the preview, then Step 2 and Step 3
  in the Supabase SQL Editor as the `postgres` role; Step 3 must report `0`.
- If the SQL Editor uses a new session between Step 1 and Step 2, rerun Step 1
  immediately first, because the temp tables hold the target ids.
- No application build is required. No client source, RPC, grant, Edge Function,
  secret, installer or marketing claim changed; the app version stays at
  `0.11.3`.
- Deletion is permanent and cascades. The preview is the safety check: if a
  target developer owns a campaign that should be kept, remove that developer
  from the target list before running Step 2.

### Modification 044

Date: 2026-11-05

#### Changes
- Added admin-managed payment packages. A package carries a name, a project fee
  and a tester payout. Operations create and edit packages on a new
  `Payment Packages` admin page, and developers choose one active package when
  creating a project.
- `create_campaign(app_name, package_name, payment_package_id)` now requires an
  active package and copies `amount_cents` into `campaigns.payment_amount_cents`
  and `tester_fee_cents` into `campaigns.tester_payout_cents`. The old 2-argument
  `create_campaign(text, text)` is dropped, so an outdated client cannot create an
  unpriced project.
- Added `payment_packages` (name, project fee, tester payout, active flag,
  creator/timestamps) with a case-insensitive unique name, and
  `campaigns.payment_package_id` with `on delete restrict`. The default `Standard`
  package is `$15.00` with a `$0.50` tester payout; existing campaigns are
  backfilled to it and `tester_payout_cents` defaults to `50`.
- Added `save_payment_package` (admin-only create/update, including active/inactive
  and the rule that at least one package stays active) and
  `list_payment_packages` (authenticated read of active packages for developers).
  `admin_dashboard` now returns `packages` with per-package project counts.
- Replaced the OS `MessageBox` alerts with a shared in-app notification layer:
  - success/error toasts stack at the top right and expire after five seconds,
    capped at four visible items;
  - destructive actions use a styled modal confirmation that returns a
    `Task<bool>`;
  - the shared `ShellView` hosts both overlays, so all three workspaces use the
    same behaviour.
- Routed success messages through `NotificationCenter` while keeping inline
  `Error` text for validation. Replaced destructive delete, leave, opt-out and
  group-rotation confirmation dialogs with the in-app confirm.
- Added the `Payment Packages` tab to TesterLoop Admin and the package selector
  plus fee/payout summary to the developer new-project form. A missing
  `list_payment_packages` RPC now shows an actionable "run
  sql/migrations/026_payment_packages.sql" message instead of silently disabling
  project creation.
- Added `sql/migrations/026_payment_packages.sql` for the live project, mirrored
  the table, columns, RPCs, grants and `admin_dashboard` payload in the greenfield
  SQL and bootstrap, and bumped the desktop and admin apps to `0.12.0`.
- Made the `026` dashboard rename safe to rerun: it renames `admin_dashboard`
  only when `admin_dashboard_base` is absent, so a second run cannot turn the
  wrapper into a self-calling base function.
- Refreshed the marketing file for `0.12.0` desktop and `1.1.1` Android.

#### Files / Components
- `sql/migrations/026_payment_packages.sql` (new)
- `sql/schema/001_init.sql`
- `sql/functions/004_queries.sql`, `sql/functions/005_mutations.sql`
- `sql/policies/002_rls.sql`, `sql/seed/007_admin_bootstrap.sql`
- `src/TesterLoop.Shared/Core/Data/Contracts.cs`
- `src/TesterLoop.Shared/Core/Data/SupabaseService.cs`
- `src/TesterLoop.Shared/Core/Notifications/NotificationCenter.cs` (new)
- `src/TesterLoop.Shared/Core/Notifications/NotificationItem.cs` (new)
- `src/TesterLoop.Shared/Views/ShellView.xaml`
- `src/TesterLoop.Desktop/ViewModels/ShellViewModel.cs`
- `src/TesterLoop.Desktop/ViewModels/DeveloperViewModel.cs`,
  `DeveloperViewModel.Projects.cs`, `DeveloperViewModel.Delete.cs`
- `src/TesterLoop.Desktop/ViewModels/TesterViewModel.cs`,
  `TesterViewModel.Actions.cs`
- `src/TesterLoop.Desktop/Views/DeveloperProjectListView.xaml`
- `src/TesterLoop.Admin/ViewModels/AdminShellViewModel.cs`,
  `AdminViewModel.cs`, `AdminViewModel.Packages.cs` (new),
  `AdminViewModel.GroupSetup.cs`
- `src/TesterLoop.Admin/ViewModels/AdminRows.cs`
- `src/TesterLoop.Admin/Views/AdminView.xaml`
- `src/TesterLoop.Admin/Views/AdminPackagesView.xaml` (new),
  `AdminPackagesView.xaml.cs` (new)
- `src/TesterLoop.Shared/Core/AppConfig.cs`,
  `src/TesterLoop.Desktop/TesterLoop.Desktop.csproj`,
  `src/TesterLoop.Admin/TesterLoop.Admin.csproj`
- `installer/TesterLoop.iss`, `installer/TesterLoop.Admin.iss`
- `AGENTS.md`, `AGENTS_PLAN.md`, `medial_support.txt`

#### Important Notes
- Package history is immutable by design: a campaign keeps the amounts copied at
  creation, so editing a package affects only future projects. A package that has
  been used cannot be deleted because the campaign reference is
  `on delete restrict`; operations can deactivate it instead.
- `payment_packages` is server-only. Direct table access is revoked from `public`,
  `anon` and `authenticated`; `save_payment_package` calls `require_admin()`;
  `list_payment_packages` requires an authenticated session and returns only
  active packages.
- Migration `026` renames the current `admin_dashboard` to
  `admin_dashboard_base()` and rebuilds the public function with `jsonb_set`, so
  the large dashboard body is not duplicated. The rename only runs when no base
  function exists, so rerunning `026` preserves the original base instead of
  renaming the wrapper onto itself. On a fresh greenfield install the base
  function already contains `packages`; setting the same key again is harmless.
  `admin_dashboard_base` is revoked from clients.
- `RelayCommand<T>` does not exist in this codebase. Per-row package editing uses
  `AsyncRelayCommand<PaymentPackageRow>` and binds the command through the parent
  `UserControl`.
- The notification overlay lives in the shared shell. `ShellViewModel` and
  `AdminShellViewModel` both create a `NotificationCenter`; the overlay commands
  are bound to that instance.
- The confirm `TaskCompletionSource` is created before `IsConfirmOpen` is raised,
  preventing a re-entrant observer from completing a confirm before the source
  exists.
- Known minor risk: the confirm overlay uses a `Grid.InputBindings` Escape key;
  Escape may not fire until focus is inside the overlay. The confirm and cancel
  buttons remain the guaranteed path.
- Migration `026` has not been run against the live Supabase project, and no local
  Postgres, `psql`, `supabase` or `deno` CLI is available. The owner must run it
  after `025` in the Supabase SQL Editor as `postgres`.
- `sql/maintenance/purge_test_accounts.sql` remains owner-run; the three documented
  QA accounts are still present until Steps 1-3 are run.
- Verification: `dotnet build TesterLoop.sln -c Release` 0 warnings / 0 errors.
  A temporary WPF harness at
  `C:\Users\Nwick\AppData\Local\Temp\opencode\TesterLoop.AdminHarness` loaded the
  shared shell and the admin view in separate modes and reported no binding
  errors (`BINDING_COUNT=0`). The harness is outside the repository.
- Published and packaged `0.12.0` for both apps and both architectures:
  - `build/win-x86/TesterLoop.exe` 141,824 bytes, file `0.12.0.0`, PE `0x14C`
  - `build/win-x64/TesterLoop.exe` 172,544 bytes, file `0.12.0.0`, PE `0x8664`
  - `build/admin-win-x86/TesterLoopAdmin.exe` 141,824 bytes, file `0.12.0.0`,
    PE `0x14C`
  - `build/admin-win-x64/TesterLoopAdmin.exe` 172,544 bytes, file `0.12.0.0`,
    PE `0x8664`
  - `build/win-x86/TesterLoop-Setup-x86.exe` 45,163,967 bytes
  - `build/win-x64/TesterLoop-Setup-x64.exe` 50,053,661 bytes
  - `build/admin-win-x86/TesterLoop-Admin-Setup-x86.exe` 45,084,954 bytes
  - `build/admin-win-x64/TesterLoop-Admin-Setup-x64.exe` 49,958,915 bytes
  All four installers report product version `0.12.0`.
- Launch smoke test: all four published executables start, keep responsive windows
  titled `TesterLoop` / `TesterLoop Admin`, and were stopped after the check.
- Not verified live: package create/edit/select, the campaign fee copy, and the
  toast/confirm overlays against live data. These need `026` applied and live
  developer/operations accounts. Installers remain unsigned and have not been run
  end to end.
- Security: no secrets or endpoints were added. The anon key remains the only
  credential in the clients; package writes are admin-only server-side and package
  reads expose only active pricing, not other accounts' data.

### Modification 045

Date: 2026-11-05

#### Changes
- Reordered TesterLoop Admin's Operations page so `PROJECTS AWAITING PAYMENT`
  comes before `GROUPS TO CREATE`. Operations now records the fee before creating
  and attaching the Google Group.
- Updated the Operations header to "Record the project fee, create the exact
  Google Group, confirm its settings, then attach it." The payment card title is
  now `PROJECTS AWAITING PAYMENT`, and the action button is bound to
  `ConfirmPaymentLabel`, which shows the selected package amount (for example,
  `Confirm $15.00 payment`) instead of fixed `$15` copy.
- Campaign payment status now shows the project's copied amount
  (`$15.00 due`, `$30.00 due`) rather than the default package fee.
- Added hard deletion for unused payment packages:
  - `delete_payment_package(p_id uuid)` is admin-only, rejects a missing package,
    rejects a package referenced by any campaign, rejects the last active package,
    writes `payment_package.deleted` to the audit log and returns a JSON summary.
  - Added `sql/migrations/027_delete_payment_package.sql`, revoked the RPC from
    `public` / `anon` / `authenticated`, granted it only to `authenticated`, and
    reloaded the PostgREST schema cache.
  - Added the grant to `sql/seed/007_admin_bootstrap.sql`.
  - Added `DeletePaymentPackageAsync` to `SupabaseService`.
  - Added `AdminViewModel.Packages.Delete.cs` with the delete command, guard state
    and in-app confirmation. Deletion is available only inside the package editor,
    not as a row action.
  - `AdminPackagesView.xaml` shows a red `Delete package` button and an explanatory
    note. It is disabled for a used package or the last active package.
  - `PaymentPackageRow` now carries `CampaignsUsed`; `AdminViewModel.Packages.cs`
    refreshes and clears delete state when a package is opened, edited, saved or
    closed.
- Version bumped to `0.12.1` in `AppConfig`, both projects, both installers and
  `medial_support.txt`. Android stays at `1.1.1`.

#### Files / Components
- `src/TesterLoop.Admin/Views/AdminOperationsView.xaml`
- `src/TesterLoop.Admin/Views/AdminPackagesView.xaml`
- `src/TesterLoop.Admin/ViewModels/AdminViewModel.cs`,
  `AdminViewModel.Payments.cs`, `AdminViewModel.Packages.cs`,
  `AdminViewModel.Packages.Delete.cs` (new), `AdminViewModel.DeveloperDetail.cs`,
  `AdminRows.cs`
- `src/TesterLoop.Shared/Core/Data/SupabaseService.cs`
- `sql/functions/005_mutations.sql`
- `sql/migrations/027_delete_payment_package.sql` (new)
- `sql/seed/007_admin_bootstrap.sql`
- `src/TesterLoop.Shared/Core/AppConfig.cs`,
  `src/TesterLoop.Desktop/TesterLoop.Desktop.csproj`,
  `src/TesterLoop.Admin/TesterLoop.Admin.csproj`
- `installer/TesterLoop.iss`, `installer/TesterLoop.Admin.iss`
- `AGENTS.md`, `AGENTS_PLAN.md`, `medial_support.txt`

#### Important Notes
- Package history stays immutable. A package that has priced a campaign cannot be
  deleted because the campaign keeps the copied fee and payout; operations can
  deactivate it instead. At least one active package must always remain.
- The SQL remains the authority. A tampered client cannot delete a used package or
  the last active package, and every successful delete writes an audit row.
- Migration order is `026` -> `027`. `027` has not been run against the live
  Supabase project; deletion returns an RPC error until the owner applies it.
- Verification: `dotnet build TesterLoop.sln -c Release` completed with 0 warnings
  and 0 errors. The external WPF harness loaded the admin and shell modes with
  `BINDING_COUNT=0`.
- Published and packaged `0.12.1` for both apps and both architectures:
  - `build/win-x86/TesterLoop.exe` 141,824 bytes, file `0.12.1.0`, PE `0x14C`
  - `build/win-x64/TesterLoop.exe` 172,544 bytes, file `0.12.1.0`, PE `0x8664`
  - `build/admin-win-x86/TesterLoopAdmin.exe` 141,824 bytes, file `0.12.1.0`,
    PE `0x14C`
  - `build/admin-win-x64/TesterLoopAdmin.exe` 172,544 bytes, file `0.12.1.0`,
    PE `0x8664`
  - `build/win-x86/TesterLoop-Setup-x86.exe` 45,163,934 bytes
  - `build/win-x64/TesterLoop-Setup-x64.exe` 50,054,140 bytes
  - `build/admin-win-x86/TesterLoop-Admin-Setup-x86.exe` 45,086,784 bytes
  - `build/admin-win-x64/TesterLoop-Admin-Setup-x64.exe` 49,960,580 bytes
  All four installers report product version `0.12.1`.
- Launch smoke test: all four published executables start, keep responsive windows
  titled `TesterLoop` / `TesterLoop Admin`, and were stopped after the check.
- Not verified live: the Operations order, dynamic confirmation amount, package
  deletion and used/last-active blocks, because `026` / `027` have not been applied
  and no operations account was used this round. Installers remain unsigned and
  have not been run end to end.
- Security: no secrets or endpoints were added. `delete_payment_package` is
  `security definer`, calls `require_admin()`, is revoked from clients other than
  `authenticated`, and does not expose package data to developers.

### Modification 046

Date: 2026-11-05

#### Changes
- Added admin-only mobile usage visibility to `TesterLoop Admin` tester detail
  project rows. Each project now shows a `USAGE` column with install state,
  distinct and continuous day counts, the 14-day requirement state, and the last
  usage date.
- Added `src/TesterLoop.Admin` UI support for the usage summary:
  - `AdminTesterUsageDto` and `AdminTesterDetailDto.UsageAvailable`.
  - `AdminTesterCampaignDto.Usage` JSON mapping.
  - `AdminTesterCampaignRow` fields `UsageStateLabel`, `UsageDaysLabel`,
    `UsageDetail`, `UsageTone` and `UsageTooltip`.
  - `AdminTesterDetail` fields `UsageAvailable`, `HasUsageNotice` and
    `UsageNotice`.
- Added `BuildUsageLabels` in `AdminViewModel.TesterDetail.cs`. Labels use
  `AppConfig.RequiredDays` (`14`) and render `Met`, `In progress`,
  `Not installed`, `Not reported`, `8/14 days`, `Last used yyyy-MM-dd` and
  `No usage yet`.
- The Tester detail table is now `PROJECT, STATE, OPT-IN, USAGE, REPORTS, FEE,
  PAYOUT, REFERENCE, ACTION`, with a new `104`-wide `USAGE` column.
- Added a warning banner when the RPC payload has no usage data. It tells
  operations to run `sql/migrations/028_admin_usage_visibility.sql`, so an
  unmigrated database is visible instead of silently blank.
- Added `sql/migrations/028_admin_usage_visibility.sql`:
  - Preflight checks `to_regclass('public.tester_app_usage_summary')` and raises
    `Run migration 019_tester_app_usage.sql before 028_admin_usage_visibility.sql.`
  - Replaces `admin_tester_detail` with `usage_available: true` and a per-seat
    `usage` object: `installed`, `distinct_days_used`, `continuous_days_used`,
    `meets_usage_requirement`, `last_usage_at`, `first_install_at`.
  - Revokes from `public` / `anon`, grants only to `authenticated`, and reloads
    the PostgREST schema cache.
- Mirrored the updated `admin_tester_detail` into
  `sql/functions/004_queries.sql`.
- Cleaned the touched detail-page text: header separators now use `&#183;`,
  and the view-model fallback labels and project separator no longer contain
  mojibake.
- Version bumped to `0.12.2` in `AppConfig`, both projects and both installers.
  Android stays at `1.1.1`.
- Refreshed `medial_support.txt`: version `0.12.2`, admin usage feature copy,
  tester-benefit copy, designer note, and AI prompt #2 replaced with a tester
  detail USAGE scene.

#### Files / Components
- `sql/migrations/028_admin_usage_visibility.sql` (new)
- `sql/functions/004_queries.sql`
- `src/TesterLoop.Shared/Core/Data/Contracts.AdminDetail.cs`
- `src/TesterLoop.Admin/ViewModels/AdminRows.Detail.cs`,
  `AdminDetails.cs`, `AdminViewModel.TesterDetail.cs`
- `src/TesterLoop.Admin/Views/AdminTesterDetailView.xaml`
- `src/TesterLoop.Shared/Core/AppConfig.cs`,
  `src/TesterLoop.Desktop/TesterLoop.Desktop.csproj`,
  `src/TesterLoop.Admin/TesterLoop.Admin.csproj`
- `installer/TesterLoop.iss`, `installer/TesterLoop.Admin.iss`
- `AGENTS.md`, `AGENTS_PLAN.md`, `medial_support.txt`

#### Important Notes
- Usage is a summary only. The admin page does not expose a daily breakdown; it
  shows installed state, distinct/continuous days, whether the 14-day requirement
  is met, and the last usage date.
- Usage remains scoped to the joined campaign package, not whole-device
  monitoring. The RPC is admin-only, revoked from clients other than
  `authenticated`, and calls `require_admin()`.
- Missing migration fallback: an older `admin_tester_detail` returns no
  `usage_available`; the DTO defaults it to `false` and the UI shows the
  actionable warning instead of failing.
- Deployment: apply `028` after `019` (and after `026` / `027`). `028` only
  replaces `admin_tester_detail`; it does not change usage reporting, opt-in,
  seat, payment or payout rules.
- Verification: `dotnet build TesterLoop.sln -c Release` 0 warnings / 0 errors.
  The external WPF harness loaded `testerdetail`, `testerdetail-missing`, `admin`
  and `shell` modes with `BINDING_COUNT=0`.
- Published and packaged `0.12.2` for both apps and both architectures:
  - `build/win-x86/TesterLoop.exe` 141,824 bytes, file `0.12.2.0`, PE `0x14C`
  - `build/win-x64/TesterLoop.exe` 172,544 bytes, file `0.12.2.0`, PE `0x8664`
  - `build/admin-win-x86/TesterLoopAdmin.exe` 141,824 bytes, file `0.12.2.0`,
    PE `0x14C`
  - `build/admin-win-x64/TesterLoopAdmin.exe` 172,544 bytes, file `0.12.2.0`,
    PE `0x8664`
  - `build/win-x86/TesterLoop-Setup-x86.exe` 45,164,758 bytes
  - `build/win-x64/TesterLoop-Setup-x64.exe` 50,055,663 bytes
  - `build/admin-win-x86/TesterLoop-Admin-Setup-x86.exe` 45,088,412 bytes
  - `build/admin-win-x64/TesterLoop-Admin-Setup-x64.exe` 49,962,760 bytes
  All four installers report product version `0.12.2`.
- Launch smoke test: all four `0.12.2` executables start, keep responsive windows
  titled `TesterLoop` / `TesterLoop Admin`, and were stopped after the check.
- Not verified live: the usage labels and migration-warning banner, because
  `028` has not been applied and no operations account was used. Installers
  remain unsigned and have not been run end to end.
- Security: no secrets or endpoints were added. The new admin payload contains
  per-campaign usage summaries only; tester emails remain admin-only and no
  whole-device usage is exposed.
### Modification 047

Date: 2026-11-05

#### Changes
- Fixed the misaligned project table on the TesterLoop Admin tester detail page.
  The header defined nine columns after adding `USAGE`, but the row template still
  had eight column definitions. The missing `104`-wide usage column is restored,
  so `USAGE`, `REPORTS`, `FEE`, `PAYOUT`, `REFERENCE` and `ACTION` now line up
  with their headers.
- Corrected the `0.12.2` usage layout; the affected admin build was local only and
  had not been committed or released.
- Version bumped to `0.12.3` in `AppConfig`, both projects, both installers and
  `medial_support.txt`. Android stays at `1.1.1`.

#### Files / Components
- `src/TesterLoop.Admin/Views/AdminTesterDetailView.xaml`
- `src/TesterLoop.Shared/Core/AppConfig.cs`
- `src/TesterLoop.Desktop/TesterLoop.Desktop.csproj`
- `src/TesterLoop.Admin/TesterLoop.Admin.csproj`
- `installer/TesterLoop.iss`, `installer/TesterLoop.Admin.iss`
- `AGENTS.md`, `AGENTS_PLAN.md`, `medial_support.txt`

#### Important Notes
- Root cause was a XAML-only column mismatch: the item template's last fixed
  column was `7` (`92` wide), while the action button used `Grid.Column="8"`.
  WPF did not raise a binding error, so the external harness could not catch it.
- No SQL, RPC, Edge Function, grant, secret or data model changed.
- Verification: `dotnet build TesterLoop.sln -c Release` 0 warnings / 0 errors.
  The external WPF harness reported `BINDING_COUNT=0` for `testerdetail`,
  `testerdetail-missing`, `admin` and `shell`.
- Published and packaged `0.12.3` for both apps and both architectures:
  - `build/win-x86/TesterLoop.exe` 141,824 bytes, file `0.12.3.0`, PE `0x14C`
  - `build/win-x64/TesterLoop.exe` 172,544 bytes, file `0.12.3.0`, PE `0x8664`
  - `build/admin-win-x86/TesterLoopAdmin.exe` 141,824 bytes, file `0.12.3.0`,
    PE `0x14C`
  - `build/admin-win-x64/TesterLoopAdmin.exe` 172,544 bytes, file `0.12.3.0`,
    PE `0x8664`
  - `build/win-x86/TesterLoop-Setup-x86.exe` 45,165,142 bytes
  - `build/win-x64/TesterLoop-Setup-x64.exe` 50,054,871 bytes
  - `build/admin-win-x86/TesterLoop-Admin-Setup-x86.exe` 45,089,201 bytes
  - `build/admin-win-x64/TesterLoop-Admin-Setup-x64.exe` 49,962,880 bytes
  All four installers report product version `0.12.3`.
- Launch smoke test: all four `0.12.3` executables start, keep responsive windows
  titled `TesterLoop` / `TesterLoop Admin`, and were stopped after the check.
- Not verified live: the corrected admin layout with real usage data, because
  `028` has not been applied and no operations account was used. Installers remain
  unsigned and have not been run end to end.

### Modification 048

Date: 2026-11-06

#### Changes
- Restored `package_name` and `usage_status` in `tester_dashboard().mine`. The
  package name was still stored in `campaigns.package_name`; migration `025`
  stopped returning it, so the Android install check reported
  "This project has no package name yet. Contact operations." and usage sync
  skipped joined projects.
- Added `sql/migrations/029_restore_tester_dashboard_package_usage.sql`. It
  preflights for `tester_app_usage_summary`, recreates `tester_dashboard()` with
  the current `tester.mobile_device_*` fields plus the restored `mine` fields,
  keeps the function authenticated-only and reloads the PostgREST schema cache.
- Mirrored both `mine` fields into `sql/functions/004_queries.sql` so a greenfield
  or re-run deployment cannot reintroduce the omission.
- Android `openCampaign` now reloads the dashboard when the selected project has
  no package name, so the fixed payload appears without a manual refresh.
- Added shared `ui/components/BackExit.kt` with a two-second double-back exit and
  snackbar hint.
- Android back behavior is now:
  - `ShellScreen`: any non-Home tab returns to Home; Home requires a second back
    press within two seconds to exit.
  - `AuthScreen`: `SignUp` / `Recover` return to `Login`; `RecoverCode` returns to
    `Recover`; `Login` requires a second back press to exit.
  - `CampaignScreen`: system back matches the top-bar back (`closeCampaign` then
    pop) and is disabled while the report sheet or opt-out dialog is visible.
  - `SplashScreen`: consumes back during startup.
- Android version bumped to `1.1.2` (`versionCode 10102`). Windows stays at
  `0.12.3`; no Windows source changed.

#### Files / Components
- `sql/migrations/029_restore_tester_dashboard_package_usage.sql` (new)
- `sql/functions/004_queries.sql`
- `mobile/app/src/main/kotlin/com/testerloop/app/ui/AppVm.kt`
- `mobile/app/src/main/kotlin/com/testerloop/app/ui/components/BackExit.kt` (new)
- `mobile/app/src/main/kotlin/com/testerloop/app/ui/ShellScreen.kt`
- `mobile/app/src/main/kotlin/com/testerloop/app/ui/auth/AuthScreen.kt`
- `mobile/app/src/main/kotlin/com/testerloop/app/ui/campaign/CampaignScreen.kt`
- `mobile/app/src/main/kotlin/com/testerloop/app/ui/splash/SplashScreen.kt`
- `mobile/app/build.gradle.kts`
- `AGENTS.md`, `AGENTS_PLAN.md`, `medial_support.txt`

#### Important Notes
- Deployment: run `029` after `028` (and after `019`). Until it runs, the mobile
  package name remains missing even with the `1.1.2` APK.
- Verification: `dotnet build TesterLoop.sln -c Release` succeeded with 0 warnings
  / 0 errors. Android `:app:assembleDebug`, `:app:assembleRelease` and
  `:app:lintDebug` succeeded; lint reports 0 errors, 24 warnings and 1 hint.
- Artifacts: `build/android/TesterLoop-Mobile-1.1.2-debug.apk` is `18,831,194`
  bytes and `TesterLoop-Mobile-1.1.2-release-unsigned.apk` is `12,998,456` bytes.
  `aapt` reports package `com.testerloop.app`, `versionCode 10102`,
  `versionName 1.1.2`, `minSdk 24`, `targetSdk 36`, label `TesterLoop`. The
  superseded `1.1.1` APKs were removed; the release APK is unsigned.
- Not verified on a device: the back behavior, the restored package name and the
  usage sync. No Android device or accelerated emulator is available in this
  environment.
- Security: no secrets, endpoints or client credentials were added. Migration
  `029` keeps `tester_dashboard` revoked from `public` / `anon` and granted only
  to `authenticated`. Windows installers remain unsigned and were not rebuilt.

### Modification 049

Date: 2026-11-06

#### Changes
- Bug reports now keep the project's install and usage state at filing time. Added
  `bug_reports.usage_snapshot` and `usage_captured_at`; `file_report` reads the
  joined campaign's usage summary server-side, falls back to
  `tester_app_installs` plus the campaign package name, and stores the snapshot
  without blocking the report.
- `tester_dashboard.reports` returns `usage` and `usage_captured_at`. The Windows
  tester MY REPORTS list shows `Usage not captured`, `Usage not reported`,
  `Installed - x/14 days` or `Not installed - x/14 days`.
- Added the admin-only `admin_report_detail(p_report_id)` and a full report page
  in TesterLoop Admin Feedback. It shows severity, status, tester, project,
  device, build, reproduction notes, evidence links, the usage snapshot beside
  current usage, and a package mismatch warning. Evidence links are copy-only.
- Admin Feedback is now a master/detail page with Back. The nested headerless
  `TabControl` follows the existing content-host pattern; duplicate XAML style
  attributes on four labels were removed, and the missing code-behind was added.
- Android: `UsageStatus` gained `available`, `packageName` and `capturedAt`;
  `ReportItem` gained `usage` and `usageCapturedAt`. The report sheet shows an
  "Attached with this report" usage preview, and report rows show a usage label.
- Added `sql/migrations/030_report_usage_snapshot.sql`, mirrored the columns,
  `file_report`, `tester_dashboard` and `admin_report_detail` into the greenfield
  SQL and bootstrap grants, and bumped Windows to `0.13.0` and Android to `1.2.0`
  (`versionCode 10200`).

#### Files / Components
- `sql/migrations/030_report_usage_snapshot.sql` (new)
- `sql/schema/001_init.sql`
- `sql/functions/004_queries.sql`, `sql/functions/006_tester_actions.sql`
- `sql/seed/007_admin_bootstrap.sql`
- `src/TesterLoop.Shared/Core/Data/Contracts.AdminDetail.cs`,
  `Core/Data/Contracts.cs`, `Core/Data/SupabaseService.AdminDetail.cs`
- `src/TesterLoop.Admin/ViewModels/AdminDetails.cs`,
  `AdminViewModel.ReportDetail.cs` (new), `AdminViewModel.cs`,
  `AdminViewModel.Navigation.cs`
- `src/TesterLoop.Admin/Views/AdminFeedbackView.xaml`,
  `AdminReportDetailView.xaml`, `AdminReportDetailView.xaml.cs` (new)
- `src/TesterLoop.Desktop/ViewModels/Rows.cs`,
  `ViewModels/TesterViewModel.cs`, `Views/TesterWorkspaceView.xaml`
- `mobile/app/src/main/kotlin/com/testerloop/app/data/api/Models.kt`
- `mobile/app/src/main/kotlin/com/testerloop/app/ui/campaign/ReportSheet.kt`,
  `ui/campaign/CampaignScreen.kt`, `ui/components/ProjectCards.kt`
- `src/TesterLoop.Shared/Core/AppConfig.cs`,
  `src/TesterLoop.Desktop/TesterLoop.Desktop.csproj`,
  `src/TesterLoop.Admin/TesterLoop.Admin.csproj`
- `mobile/app/build.gradle.kts`
- `installer/TesterLoop.iss`, `installer/TesterLoop.Admin.iss`
- `AGENTS.md`, `AGENTS_PLAN.md`, `medial_support.txt`

#### Important Notes
- The snapshot is written only by SQL. The client sends no usage object, so a
  tampered client cannot invent install or usage evidence. Missing usage is
  stored as an empty object and read as "Not captured".
- `admin_report_detail` is `security definer`, calls `require_admin()`, is revoked
  from `public` / `anon` and granted only to `authenticated`. Developer campaign
  payloads are unchanged, so developers still never receive tester usage detail
  or tester email addresses.
- The package mismatch warning is advisory. It compares the snapshot package name
  with the campaign package name; legacy reports without either field show no
  warning.
- Deployment: run `030` after `029` (and after `019`, `026`-`028`). It preflights
  for `tester_app_usage_summary` and reloads the PostgREST schema cache.
- Verification: `dotnet build TesterLoop.sln -c Release` 0 warnings / 0 errors.
  The external WPF harness reports `BINDING_COUNT=0` for `reportdetail`, `admin`,
  `shell`, `testerdetail` and `testerdetail-missing`. Android
  `:app:assembleDebug`, `:app:assembleRelease` and `:app:lintDebug` succeed; lint
  reports 0 errors, 24 warnings and 1 hint.
- Published and packaged `0.13.0` for both Windows apps and both architectures:
  - `build/win-x86/TesterLoop.exe` 141,824 bytes, file `0.13.0.0`, PE `0x14C`
  - `build/win-x64/TesterLoop.exe` 172,544 bytes, file `0.13.0.0`, PE `0x8664`
  - `build/admin-win-x86/TesterLoopAdmin.exe` 141,824 bytes, file `0.13.0.0`,
    PE `0x14C`
  - `build/admin-win-x64/TesterLoopAdmin.exe` 172,544 bytes, file `0.13.0.0`,
    PE `0x8664`
  - `build/win-x86/TesterLoop-Setup-x86.exe` 45,167,821 bytes
  - `build/win-x64/TesterLoop-Setup-x64.exe` 50,057,087 bytes
  - `build/admin-win-x86/TesterLoop-Admin-Setup-x86.exe` 45,095,203 bytes
  - `build/admin-win-x64/TesterLoop-Admin-Setup-x64.exe` 49,969,502 bytes
  All four executables start, keep responsive windows titled `TesterLoop` /
  `TesterLoop Admin`, and were stopped after the check. All four installers report
  product version `0.13.0`.
- Android artifacts: `build/android/TesterLoop-Mobile-1.2.0-debug.apk`
  (18,831,198 bytes) and
  `build/android/TesterLoop-Mobile-1.2.0-release-unsigned.apk` (12,998,460
  bytes). The superseded `1.1.2` copies were removed. `aapt` reports package
  `com.testerloop.app`, `versionCode 10200`, `versionName 1.2.0`, `minSdk 24`,
  `targetSdk 36`, label `TesterLoop`. The release APK is unsigned.
- Not verified live: the admin report detail, snapshot vs current usage and the
  package warning, because `030` has not been applied and no operations account
  was used. SQL was reviewed statically only; no local Postgres, `psql`, `supabase`
  or `deno` CLI is available.
- Not verified on a device: the report-sheet usage preview and the mobile report
  row label. No Android device or accelerated emulator is available.
- Security: no secrets, endpoints or client credentials were added. Tester usage
  stays admin-only, developer payloads are unchanged, and evidence URLs remain
  copy-only. Installers remain unsigned and have not been run end to end.
- QA purge remains owner-run: execute Steps 1-3 of
  `sql/maintenance/purge_test_accounts.sql`.
### Modification 050

Date: 2026-11-06

#### Changes
- Added a full close test project page to TesterLoop Admin. Selecting a project in
  the Close Test Projects list opens one page with the app and package, developer
  contact, live state, dates, the exact Google Group identity and settings
  confirmation, payment status, fee, reference and Play link, the seat budget,
  report and usage coverage, and payout totals.
- Added the `admin_campaign_detail(p_campaign_id uuid)` RPC. It returns
  `campaign`, `totals`, `testers`, `reports` and `audit`. Tester rows carry seat
  number, opt-in state, report count, payout state and reference plus the nested
  usage summary. Report rows carry the tester, severity, status, evidence links and
  the usage snapshot taken when the report was filed. The audit list is the last 50
  rows whose `detail->>'campaign_id'` matches the project.
- Added `sql/migrations/031_admin_campaign_detail.sql` (preflight for
  `tester_app_usage_summary`, function, revokes, grant, PostgREST reload) and
  mirrored the function into `sql/functions/004_queries.sql` and the bootstrap
  grants.
- Shared types: `AdminCampaignDetailDto`, `AdminCampaignProfileDto`,
  `AdminCampaignTotalsDto`, `AdminCampaignTesterDto`, `AdminCampaignReportDto`,
  and `GetAdminCampaignDetailAsync` on `SupabaseService`.
- Admin UI: `AdminCampaignDetail` plus `AdminCampaignTesterRow` and
  `AdminCampaignReportRow`; a new `AdminViewModel.CampaignDetail.cs` partial with
  open/back/refresh, page index and DTO mapping; the Close Test Projects list is
  now a master/detail `TabControl` using the same pattern as testers, developers and
  feedback. The detail page is split into `AdminCampaignDetailView` (header,
  metrics, group and payment), `AdminCampaignTestersView` (tester table) and
  `AdminCampaignActivityView` (reports and project history) so each XAML file stays
  near the 300-line guideline.
- Version bumped to `0.14.0` in `AppConfig`, both projects, both installers and
  `medial_support.txt`.

#### Files / Components
- `sql/functions/004_queries.sql`
- `sql/migrations/031_admin_campaign_detail.sql` (new)
- `sql/seed/007_admin_bootstrap.sql`
- `src/TesterLoop.Shared/Core/Data/Contracts.AdminDetail.cs`,
  `Core/Data/SupabaseService.AdminDetail.cs`
- `src/TesterLoop.Admin/ViewModels/AdminViewModel.CampaignDetail.cs` (new),
  `AdminViewModel.cs`, `AdminViewModel.Navigation.cs`, `AdminRows.Detail.cs`,
  `AdminDetails.cs`
- `src/TesterLoop.Admin/Views/AdminCampaignsView.xaml`,
  `AdminCampaignDetailView.xaml(.cs)` (new),
  `AdminCampaignTestersView.xaml(.cs)` (new),
  `AdminCampaignActivityView.xaml(.cs)` (new)
- `src/TesterLoop.Shared/Core/AppConfig.cs`,
  `src/TesterLoop.Desktop/TesterLoop.Desktop.csproj`,
  `src/TesterLoop.Admin/TesterLoop.Admin.csproj`
- `installer/TesterLoop.iss`, `installer/TesterLoop.Admin.iss`
- `AGENTS.md`, `AGENTS_PLAN.md`, `medial_support.txt`

#### Important Notes
- The project detail read is admin-only. `admin_campaign_detail` is
  `security definer`, calls `require_admin()`, is revoked from `public` / `anon`
  and granted only to `authenticated`. It exposes tester emails to operations as
  the existing tester roster already does; the developer payloads are unchanged.
- Campaign audit rows have no campaign column; the filter uses
  `audit_log.detail->>'campaign_id'`, so a row that did not record the campaign id
  is not listed.
- The usage section reuses the admin tester-detail label logic. If migration `019`
  has not run, the page shows an actionable notice instead of failing.
- Deployment: apply `031` after `030` (and after `019`). `031` was reviewed
  statically only; no local Postgres, `psql`, `supabase` or `deno` CLI is
  available.
- Verification: `dotnet build TesterLoop.sln -c Release` 0 warnings / 0 errors.
  The external WPF harness reports `BINDING_COUNT=0` for `campaigndetail`,
  `campaignlist`, `admin` and `shell`. Windows `0.14.0` was published and packaged
  for both apps and both architectures:
  - `build/win-x86/TesterLoop.exe` 141,824 bytes, file `0.14.0.0`, PE `0x14C`
  - `build/win-x64/TesterLoop.exe` 172,544 bytes, file `0.14.0.0`, PE `0x8664`
  - `build/admin-win-x86/TesterLoopAdmin.exe` 141,824 bytes, file `0.14.0.0`,
    PE `0x14C`
  - `build/admin-win-x64/TesterLoopAdmin.exe` 172,544 bytes, file `0.14.0.0`,
    PE `0x8664`
  - `build/win-x86/TesterLoop-Setup-x86.exe` 45,172,263 bytes
  - `build/win-x64/TesterLoop-Setup-x64.exe` 50,062,860 bytes
  - `build/admin-win-x86/TesterLoop-Admin-Setup-x86.exe` 45,106,493 bytes
  - `build/admin-win-x64/TesterLoop-Admin-Setup-x64.exe` 49,980,387 bytes
  All four executables start, keep responsive windows titled `TesterLoop` /
  `TesterLoop Admin`, and were stopped after the check. All four installers report
  product version `0.14.0`.
- Not verified live: the project detail page with real data, because `031` has not
  been applied and no operations account was used this round. Installers remain
  unsigned and have not been run end to end.
- Security: no secrets or endpoints were added. The new RPC is admin-only, read
  only, and returns data operations already sees elsewhere. Installers remain
  unsigned.

### Modification 051

Date: 2026-11-08

#### Changes
- Added daily install history across the stack. TesterLoop Mobile now records one
  install check per tester, project and day while the project is live, keeps the
  run locally, uploads it in the background and attaches the whole window to every
  bug report. TesterLoop Admin shows that window on the report detail page.
- New `tester_app_install_daily` table (`tester_id`, `campaign_id`,
  `package_name`, `status_date`, `installed`, `source`, `checked_at`) with a
  unique row per tester/project/day, a touch trigger, RLS self/admin select
  policies and table access revoked from all client roles.
- `bug_reports` gained `install_history`, `install_history_captured_at`,
  `install_window_start` and `install_window_end`.
- Added `report_app_install_daily(campaign_id, date, installed, source)`. It
  requires a tester, accepts only `mobile_daily` / `mobile_manual` from clients,
  rejects future dates, refuses `draft` / `pending` / `awaiting_link` / `cancelled`
  projects, caps a `passed` project at its pass date, requires a joined seat and
  keeps the daily row plus the existing install and usage summary in step.
- Kept `report_app_install_status(campaign_id, installed)` for older APKs. It
  routes live projects through the daily record, clamps passed projects to the
  pass date and returns `recorded: false` for a cancelled project instead of
  failing, so a running 1.2.0 sync loop does not abort.
- `file_report` now captures every day from the seat join date (capped at 365
  days) to the report date as `{'date','installed','checked','checked_at'}`,
  stores the window and returns it plus `usage`.
- `tester_dashboard` `mine` returns `campaign_state` and `joined_at`, and
  `reports` returns the four install-history fields. `admin_report_detail`
  returns them at the top level.
- Android: added `InstallHistoryStore` (DataStore + `org.json`; no Moshi codegen
  dependency), `InstallTracking` active-state predicate, `DailyInstallCheckWorker`,
  `SyncQueue` and a rewritten `UsageSyncWorker`. Dashboard loads and manual checks
  record the day locally first, then upload; 401 is rethrown for the refresh path,
  other 4xx marks the row synced, and transport/5xx failures retry.
- Android UI: install checks stop for closed projects, the campaign card and
  report sheet explain the daily check, and tester report rows show an install
  summary. Local checks are pruned after 45 days once synced.
- Admin UI: `AdminReportDetailDto` and `AdminInstallCheckDto` carry the window;
  a new DAILY INSTALL CHECKS AT FILING card shows Installed daily, Gaps found,
  Not installed or Not checked, the installed/checked-day counts and the window.
- Added `sql/migrations/032_daily_install_history.sql`; mirrored the table,
  columns, RLS, RPCs and read models into the greenfield SQL; added the
  `report_app_install_daily` grant to `sql/seed/007_admin_bootstrap.sql`.
- Version bumped to `0.14.1` desktop / `1.2.1` (`versionCode 10201`) Android.

#### Files / Components
- `sql/migrations/032_daily_install_history.sql` (new)
- `sql/schema/001_init.sql`, `sql/policies/002_rls.sql`,
  `sql/functions/004_queries.sql`, `sql/functions/006_tester_actions.sql`,
  `sql/seed/007_admin_bootstrap.sql`
- `src/TesterLoop.Shared/Core/Data/Contracts.AdminDetail.cs`
- `src/TesterLoop.Admin/ViewModels/AdminDetails.cs`,
  `AdminViewModel.ReportDetail.cs`
- `src/TesterLoop.Admin/Views/AdminReportDetailView.xaml`
- `mobile/app/src/main/kotlin/com/testerloop/app/data/local/InstallHistoryStore.kt`
  (new), `core/InstallTracking.kt` (new), `worker/SyncQueue.kt` (new),
  `worker/DailyInstallCheckWorker.kt` (new), `worker/UsageSyncWorker.kt`
- `mobile/app/src/main/kotlin/com/testerloop/app/data/api/Models.kt`,
  `SupabaseApi.kt`
- `mobile/app/src/main/kotlin/com/testerloop/app/ui/AppVm.kt`,
  `AppVm.Install.kt` (new), `AppVm.Actions.kt`, `campaign/CampaignSections.kt`,
  `campaign/ReportSheet.kt`, `components/ProjectCards.kt`
- `mobile/app/src/main/kotlin/com/testerloop/app/TesterLoopApp.kt`
- `mobile/app/build.gradle.kts`
- `src/TesterLoop.Shared/Core/AppConfig.cs`,
  `src/TesterLoop.Desktop/TesterLoop.Desktop.csproj`,
  `src/TesterLoop.Admin/TesterLoop.Admin.csproj`
- `installer/TesterLoop.iss`, `installer/TesterLoop.Admin.iss`
- `AGENTS.md`, `AGENTS_PLAN.md`, `medial_support.txt`

#### Important Notes
- Daily install checks are not whole-device monitoring. Only the packages of
  projects the tester has joined are checked, one state per day.
- A check recorded while the server is unreachable stays local with
  `synced = false` and is uploaded on the next dashboard load or worker run. A
  rejected 4xx row is dropped so it cannot retry forever; a 401 is left for the
  session refresh path.
- `report_app_install_status` still raises for `draft` / `pending` /
  `awaiting_link`, but a seat cannot exist for those states because
  `join_campaign` only accepts `live` / `at_risk`, so an older APK only reaches it
  for live, at-risk, passed or cancelled projects.
- The report window is capped at 365 days and uses the seat join date; a rejoin
  after opt-out keeps the earlier start because `joined_at` is preserved.
- Deployment: run `032` after `031` (and after `019`). Windows `0.14.1` and
  Android `1.2.1` can be installed before the migration, but the report install
  window and the daily RPC stay unavailable until it runs.
- Verification: `dotnet build TesterLoop.sln -c Release` 0 warnings / 0 errors.
  Android `:app:assembleDebug`, `:app:assembleRelease` and `:app:lintDebug`
  succeed; lint reports 0 errors, 24 warnings and 1 hint.
- Artifacts:
  - `build/win-x86/TesterLoop.exe` 141,824 bytes, file `0.14.1.0`, PE `0x14C`
  - `build/win-x64/TesterLoop.exe` 172,544 bytes, file `0.14.1.0`, PE `0x8664`
  - `build/admin-win-x86/TesterLoopAdmin.exe` 141,824 bytes, file `0.14.1.0`
  - `build/admin-win-x64/TesterLoopAdmin.exe` 172,544 bytes, file `0.14.1.0`
  - `build/win-x86/TesterLoop-Setup-x86.exe` 45,172,559 bytes
  - `build/win-x64/TesterLoop-Setup-x64.exe` 50,063,147 bytes
  - `build/admin-win-x86/TesterLoop-Admin-Setup-x86.exe` 45,107,970 bytes
  - `build/admin-win-x64/TesterLoop-Admin-Setup-x64.exe` 49,981,966 bytes
  All four executables start, keep responsive windows titled `TesterLoop` /
  `TesterLoop Admin`, and were stopped after the check. All four installers
  report product version `0.14.1`.
  - `build/android/TesterLoop-Mobile-1.2.1-debug.apk` 18,863,966 bytes and
    `build/android/TesterLoop-Mobile-1.2.1-release-unsigned.apk` 13,014,844
    bytes. `aapt` reports `com.testerloop.app`, `versionCode 10201`,
    `versionName 1.2.1`, `minSdk 24`, `targetSdk 36`, label `TesterLoop`. The
    release APK is unsigned; the superseded `1.2.0` APKs were removed.
- Not verified live: the daily record, the report window and the admin card,
  because `032` has not been applied and no tester device or accelerated emulator
  is available. SQL was reviewed statically only; no local Postgres, `psql`,
  `supabase` or `deno` CLI is available.
- Security: no secrets or endpoints were added. `tester_app_install_daily` is
  RPC-only, and both install RPCs are tester-scoped and granted only to
  `authenticated`. Tester install history stays admin-only; developer payloads
  are unchanged. Installers remain unsigned and have not been run end to end.
- Still owed from earlier rounds: migrations `017`-`032` and the QA purge in
  `sql/maintenance/purge_test_accounts.sql`.

### Modification 052

Date: 2026-11-08

#### Changes
- Signed the Android release for the first time and shipped it as commit + GitHub
  release.
  - Generated an upload keystore at `.keys/testerloop-upload.jks` (alias
    `testerloop`, RSA 2048, 10000 days, DN `CN=TesterLoop, OU=Mobile,
    O=TesterLoop, L=Colombo, C=LK`); passwords are in `.keys/credentials.txt`.
  - `mobile/app/build.gradle.kts` loads `mobile/keystore.properties` and creates a
    `release` signing config only when that file exists, so a clone without the
    keystore still builds an unsigned release instead of failing.
  - `.keys/` and `keystore.properties` are gitignored; `release/*.apk` and
    `release/*.aab` are re-included so the signed artifacts can be committed.
- Added in-app update checks to TesterLoop Mobile.
  - `core/AppUpdater.kt` reads
    `https://api.github.com/repos/chamarawickramarathne-spec/close-test/releases/latest`,
    prefers the `mobile-version.json` asset (`versionCode` / `versionName`) and
    falls back to parsing the tag when the manifest is missing.
  - A newer `versionCode` downloads the APK to `cacheDir/updates` with a progress
    callback, then opens the Android installer through a `FileProvider`.
  - When "install unknown apps" is off, the app opens
    `Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES` and asks the tester to retry.
  - Profile has a new APP UPDATE card: installed version, update banner, download
    progress, Download and install, Check for updates, inline error and notice.
  - The check runs automatically once per launch after the dashboard loads and
    after a successful sign-in.
- Manifest: added `REQUEST_INSTALL_PACKAGES`, the
  `${applicationId}.fileprovider` FileProvider and `res/xml/file_paths.xml`
  (`cache-path` `updates/`).
- Repository: created public GitHub repo
  `chamarawickramarathne-spec/close-test`, pushed `main`, and published release
  `mobile-v1.2.2` with `TesterLoop-Mobile-1.2.2.apk` (13,043,980 bytes),
  `TesterLoop-Mobile-1.2.2.aab` (12,720,229 bytes) and `mobile-version.json`.
- Android bumped to `1.2.2` (`versionCode 10202`). Windows stays at `0.14.1`.

#### Files / Components
- `.keys/testerloop-upload.jks`, `.keys/credentials.txt` (not in git)
- `mobile/keystore.properties` (not in git)
- `.gitignore`
- `mobile/app/build.gradle.kts`
- `mobile/app/src/main/kotlin/com/testerloop/app/core/AppUpdater.kt` (new),
  `core/AppConfig.kt`
- `mobile/app/src/main/kotlin/com/testerloop/app/ui/AppVm.Update.kt` (new),
  `ui/AppVm.kt`, `ui/AppVm.Auth.kt`, `ui/UiState.kt`, `ui/profile/ProfileScreen.kt`,
  `MainActivity.kt`
- `mobile/app/src/main/AndroidManifest.xml`, `res/xml/file_paths.xml` (new)
- `release/TesterLoop-Mobile-1.2.2.apk`, `release/TesterLoop-Mobile-1.2.2.aab`,
  `release/mobile-version.json`
- `build/android/TesterLoop-Mobile-1.2.2-debug.apk`
- `AGENTS.md`, `AGENTS_PLAN.md`, `medial_support.txt`

#### Important Notes
- The upload keystore is the only way to sign a future build as the same app. It
  is deliberately outside git; back it up. Losing it means a new install identity
  (or a Play upload-key reset), not a silent re-sign.
- The updater reads a public release anonymously. If this repository ever becomes
  private, the updater stops working and must be replaced (signed manifest hosted
  elsewhere) or removed.
- The update check is a convenience, not a security control. It only accepts the
  `api.github.com` release for this repository and only installs a
  `application/vnd.android.package-archive` through the system installer, so the
  user still confirms the install.
- Release naming stays stable-ish per asset name (`TesterLoop-Mobile-<version>`),
  while the tag carries the version (`mobile-v1.2.2`). The updater prefers the
  manifest, so a renamed asset does not break version detection.
- Planned removal: the owner wants the mobile update feature removed from git in a
  later round. When that happens, remove `AppUpdater`, `AppVm.Update.kt`, the
  Profile card, the manifest permission/FileProvider and `file_paths.xml`
  together, and stop publishing `mobile-version.json`. The keystore and signing
  config stay, because signed builds are still needed.
- Verification: `:app:assembleDebug`, `:app:assembleRelease`, `:app:bundleRelease`
  and `:app:lintDebug` succeed with 0 lint errors. `apksigner` reports the APK
  signed with `CN=TesterLoop` (cert SHA-256
  `12f8382ff7f25781a718d438df51eb740858635a42c4e7d3fe3bc4fba3a84fd5`), `aapt`
  reports `com.testerloop.app` / `versionCode 10202` / `versionName 1.2.2` /
  `minSdk 24` / `targetSdk 36`, and `jarsigner -verify` exits 0 for the AAB.
  The published release lists all three assets and `mobile-version.json` returns
  `versionCode 10202`, so a 1.2.2 client correctly reports no update.
- Not verified on a device: the update check, the download, the install prompt and
  the post-install restart. No Android device or accelerated emulator is available
  in this environment.
- `032_daily_install_history.sql` is still not applied to the live Supabase
  project; that remains owner-run.

### Modification 053

Date: 2026-11-08

#### Changes
- Fixed the TesterLoop Admin close-test project page failing on every open with
  `missing FROM-clause entry for table "h"`. `admin_campaign_detail` built the
  campaign block from `h.seats_used`, `h.opted_in`, `h.days_banked`,
  `h.meets_requirement`, `h.eligible_on` and `h.threshold_opt_in_at` but never
  selected from `campaign_health`, so PostgreSQL rejected the statement before any
  row was read.
- The function now fetches `campaign_health` into `v_health` and reads those six
  values from it, so `seats_used`, `opted_in`, `days_banked`, eligibility and the
  clock start come back for the project page.
- Fixed the same defect in `sql/migrations/031_admin_campaign_detail.sql` and in
  the greenfield copy in `sql/functions/004_queries.sql`.
- Added `sql/migrations/033_fix_admin_campaign_detail.sql` (preflight for
  `campaign_health`, corrected function, revokes, grant, PostgREST reload) for the
  live project.

#### Files / Components
- `sql/functions/004_queries.sql`
- `sql/migrations/031_admin_campaign_detail.sql`
- `sql/migrations/033_fix_admin_campaign_detail.sql` (new)
- `AGENTS.md`, `AGENTS_PLAN.md`

#### Important Notes
- SQL-only correction. No client source, RPC signature, DTO or validation rule
  changed, so the Windows apps stay at `0.14.1` and no new build is required.
- Owner must run `033_fix_admin_campaign_detail.sql` in the Supabase SQL Editor as
  `postgres`; it is idempotent and only replaces `admin_campaign_detail`.
- Root cause was a copy error: the surrounding dashboard function joins
  `campaign_health h`, and the alias was reused while writing the new function
  without carrying the join across.
- Verified statically: no remaining `h.` reference in either copy of
  `admin_campaign_detail`; the three other functions that use `h.` still join
  `campaign_health`. No local Postgres, `psql`, `supabase` or `deno` CLI is
  available, so `033` was not executed here.
- Still owed from earlier rounds: `032_daily_install_history.sql` and the QA purge
  in `sql/maintenance/purge_test_accounts.sql`.

### Modification 054

Date: 2026-11-08

#### Changes
- Removed the tester payout amount from the developer workspace. The new-project
  package summary now reads `Project fee $15.00` only; it no longer says
  `tester payout $0.50`.
- The package picker still shows the package name, and the fee shown is the fee
  copied onto the project at creation, so a developer can still choose a package
  and know what they pay.
- TesterLoop Admin is unchanged: operations still sees each package's project fee
  and tester payout on `Payment Packages`, and tester payout amounts on the
  tester and developer detail pages.
- Version bumped to `0.14.2` in `AppConfig`, both projects, both installers and
  `medial_support.txt`. Android stays at `1.2.2`.

#### Files / Components
- `src/TesterLoop.Desktop/ViewModels/DeveloperViewModel.cs`
- `src/TesterLoop.Shared/Core/AppConfig.cs`,
  `src/TesterLoop.Desktop/TesterLoop.Desktop.csproj`,
  `src/TesterLoop.Admin/TesterLoop.Admin.csproj`
- `installer/TesterLoop.iss`, `installer/TesterLoop.Admin.iss`
- `AGENTS.md`, `AGENTS_PLAN.md`, `medial_support.txt`

#### Important Notes
- Presentation-only change. No SQL, RPC, Edge Function, grant, secret or data
  model changed. `list_payment_packages` still returns `tester_fee_cents`; the
  developer client simply no longer displays it.
- Verification: `dotnet build TesterLoop.sln -c Release` 0 warnings / 0 errors.
  A repository search finds no remaining developer-facing use of
  `TesterFeeCents` or `tester payout`.
- Published and packaged `0.14.2` for both apps and both architectures:
  - `build/win-x86/TesterLoop.exe` 141,824 bytes, file `0.14.2.0`, PE `0x14C`
  - `build/win-x64/TesterLoop.exe` 172,544 bytes, file `0.14.2.0`, PE `0x8664`
  - `build/admin-win-x86/TesterLoopAdmin.exe` 141,824 bytes, file `0.14.2.0`
  - `build/admin-win-x64/TesterLoopAdmin.exe` 172,544 bytes, file `0.14.2.0`
  - `build/win-x86/TesterLoop-Setup-x86.exe` 45,173,108 bytes
  - `build/win-x64/TesterLoop-Setup-x64.exe` 50,063,342 bytes
  - `build/admin-win-x86/TesterLoop-Admin-Setup-x86.exe` 45,108,009 bytes
  - `build/admin-win-x64/TesterLoop-Admin-Setup-x64.exe` 49,982,344 bytes
  All four installers report product version `0.14.2`; the published x64 app
  starts, keeps a responsive `TesterLoop` window, and was stopped after the check.
- A leftover `TesterLoopAdmin` process (pid 7612, running from
  `build\admin-win-x64`) locked the admin x64 publish; it was stopped and the
  publish re-ran cleanly.
- Not verified: the developer new-project summary with a live package list,
  because no live developer account was used this round. Installers remain
  unsigned and have not been run end to end.
### Modification 055

Date: 2026-11-08

#### Changes
- Merged the two usage cards on the TesterLoop Admin report detail page. The
  separate `INSTALL AND USAGE AT FILING` and `CURRENT USAGE` cards are now one
  `INSTALL AND USAGE` card with `AT FILING` and `LIVE NOW` columns side by side.
- Placed `DAILY INSTALL CHECKS AT FILING` beside that merged card, so the page
  shows the filing snapshot, the current state and the daily install window in one
  row instead of stacked cards.
- Kept the existing good/warn tone triggers on every label; no view-model or DTO
  changed.
- Version bumped to `0.14.3` in `AppConfig`, both projects and both installers.

#### Files / Components
- `src/TesterLoop.Admin/Views/AdminReportDetailView.xaml`
- `src/TesterLoop.Shared/Core/AppConfig.cs`
- `src/TesterLoop.Desktop/TesterLoop.Desktop.csproj`
- `src/TesterLoop.Admin/TesterLoop.Admin.csproj`
- `installer/TesterLoop.iss`, `installer/TesterLoop.Admin.iss`
- `medial_support.txt`, `AGENTS.md`

#### Important Notes
- Presentation-only change. No SQL, RPC, grant, secret, DTO or validation rule
  changed.
- Verification: `dotnet build TesterLoop.sln -c Release` 0 warnings / 0 errors.
  The external WPF harness reported `BINDING_COUNT=0` for the `reportdetail`
  mode. Published and packaged `0.14.3`:
  - `build/win-x86/TesterLoop.exe` 141,824 bytes, file `0.14.3.0`, PE `0x14C`
  - `build/win-x64/TesterLoop.exe` 172,544 bytes, file `0.14.3.0`, PE `0x8664`
  - `build/admin-win-x86/TesterLoopAdmin.exe` 141,824 bytes, file `0.14.3.0`
  - `build/admin-win-x64/TesterLoopAdmin.exe` 172,544 bytes, file `0.14.3.0`
  - `build/win-x86/TesterLoop-Setup-x86.exe` 45,173,033 bytes
  - `build/win-x64/TesterLoop-Setup-x64.exe` 50,063,243 bytes
  - `build/admin-win-x86/TesterLoop-Admin-Setup-x86.exe` 45,108,416 bytes
  - `build/admin-win-x64/TesterLoop-Admin-Setup-x64.exe` 49,982,067 bytes
  All four executables start, keep responsive windows titled `TesterLoop` /
  `TesterLoop Admin`, and were stopped after the check. All four installers
  report product version `0.14.3`.
- Not verified live: the merged card with real report data, because it needs a
  live operations account. Installers remain unsigned and have not been run end
  to end.

### Modification 056

Date: 2026-11-08

#### Changes
- TesterLoop Mobile now derives the report build version from the installed app
  instead of asking the tester to type it.
  - Added `core/InstalledApp.kt` (`installedBuildLabel`) which reads
    `PackageManager.getPackageInfo` and returns `versionName (versionCode)`, or
    `null` when the package is not installed.
  - The report sheet's optional `Build` text field is gone. It now shows a
    read-only `Build version` card with the detected label, or
    "App not installed on this device", and a note that the value is read
    automatically.
  - `AppVm.submitReport` no longer takes `buildLabel`. It looks up the joined
    project's `packageName` from the dashboard state, detects the installed build
    at submit time and sends that value as `p_build_label`.
  - `CampaignScreen` computes the preview label with
    `remember(packageName) { installedBuildLabel(...) }`, so the card reflects the
    project's package and refreshes when the package changes.
- Android version bumped to `1.2.3` (`versionCode 10203`). Windows stays at
  `0.14.3`, because no Windows source changed for this step.
- Refreshed `release/mobile-version.json` for `1.2.3`.

#### Files / Components
- `mobile/app/src/main/kotlin/com/testerloop/app/core/InstalledApp.kt` (new)
- `mobile/app/src/main/kotlin/com/testerloop/app/ui/AppVm.Actions.kt`
- `mobile/app/src/main/kotlin/com/testerloop/app/ui/campaign/ReportSheet.kt`
- `mobile/app/src/main/kotlin/com/testerloop/app/ui/campaign/CampaignScreen.kt`
- `mobile/app/build.gradle.kts`
- `release/mobile-version.json`
- `build/android/TesterLoop-Mobile-1.2.3-debug.apk`,
  `build/android/TesterLoop-Mobile-1.2.3-release.apk`,
  `release/TesterLoop-Mobile-1.2.3.apk`, `release/TesterLoop-Mobile-1.2.3.aab`
- `medial_support.txt`, `AGENTS.md`, `AGENTS_PLAN.md`

#### Important Notes
- The value is not stored or trusted by the server beyond the existing
  `p_build_label` text field; a tester who never installed the app files a report
  with no build label rather than a guessed one.
- A report filed after uninstalling records no build, and the preview card says so
  until the app is installed again.
- The Windows tester report form is unchanged: a desktop client cannot read an
  Android app's installed build, and the install tracker does not record a version
  yet.
- Verification: `:app:assembleDebug`, `:app:assembleRelease`, `:app:bundleRelease`
  and `:app:lintDebug` succeed with 0 lint errors. `aapt` reports
  `com.testerloop.app`, `versionCode 10203`, `versionName 1.2.3`, `minSdk 24`,
  `targetSdk 36`, label `TesterLoop`.
- Artifacts: `build/android/TesterLoop-Mobile-1.2.3-debug.apk` 18,880,838 bytes and
  `build/android/TesterLoop-Mobile-1.2.3-release.apk` 13,043,980 bytes;
  `release/TesterLoop-Mobile-1.2.3.apk` 13,043,980 bytes and
  `release/TesterLoop-Mobile-1.2.3.aab` 12,720,862 bytes. The superseded `1.2.2`
  files were removed.
- Not verified on a device: the detected build label and the read-only card. No
  Android device or accelerated emulator is available in this environment.
- No SQL, RPC, Edge Function, grant, secret or permission changed. The release APK
  is signed with the existing upload keystore.
- The GitHub release for `mobile-v1.2.3` has not been published, so the in-app
  updater still offers `1.2.2` until it is.

### Modification 057

Date: 2026-11-08

#### Changes
- Added a Tester project activity page to TesterLoop Admin. Selecting `View
  activity` on any project row in a tester's detail page opens that tester's seat
  on that project: seat state, join/opt-in/drop timestamps, last report, first
  verified opt-in, clock start and eligibility date, install and usage summary,
  payout state and reference, and every report that tester filed on the project.
- Report detail navigation is now origin-aware. One shared report page is opened
  from Feedback, from a project's activity page, or from a tester's project
  activity, and its back button returns to the page that opened it:
  `Back to feedback`, `Back to project` or `Back to activity`.
- Project activity report rows and the campaign activity report rows are now
  clickable buttons; selecting one opens the full report detail.
- Added `AdminTesterProjectActivity` and `AdminViewModel.TesterProject.cs` with
  open, refresh, back and report commands plus `MapTesterProject`.
- Added the tester activity and report pages to `AdminTestersView`; added the
  report page to `AdminCampaignsView`.
- Split report usage helpers into `AdminViewModel.ReportDetail.Usage.cs` so the
  report detail partial stays under 300 lines.
- Version bumped to `0.15.0` in `AppConfig`, both projects, both installers and
  `medial_support.txt`. Android stays at `1.2.3`.

#### Files / Components
- `src/TesterLoop.Admin/ViewModels/AdminViewModel.TesterProject.cs` (new)
- `src/TesterLoop.Admin/ViewModels/AdminDetails.TesterProject.cs` (new)
- `src/TesterLoop.Admin/ViewModels/AdminViewModel.ReportDetail.Usage.cs` (new)
- `src/TesterLoop.Admin/ViewModels/AdminViewModel.ReportDetail.cs`,
  `AdminViewModel.CampaignDetail.cs`, `AdminViewModel.Navigation.cs`,
  `AdminViewModel.cs`
- `src/TesterLoop.Admin/Views/AdminTesterProjectView.xaml(.cs)` (new),
  `AdminTestersView.xaml`, `AdminTesterDetailView.xaml`,
  `AdminCampaignsView.xaml`, `AdminCampaignActivityView.xaml`,
  `AdminReportDetailView.xaml`
- `src/TesterLoop.Shared/Core/AppConfig.cs`,
  `src/TesterLoop.Admin/TesterLoop.Admin.csproj`,
  `src/TesterLoop.Desktop/TesterLoop.Desktop.csproj`
- `installer/TesterLoop.iss`, `installer/TesterLoop.Admin.iss`
- `AGENTS.md`, `AGENTS_PLAN.md`, `medial_support.txt`

#### Important Notes
- Page indices: Tester list `0`, tester detail `1`, tester project activity `2`,
  report `3`; campaign list `0`, project detail `1`, report `2`; feedback list
  `0`, report `1`. A side-menu change resets every page, clears the selected
  tester project and resets the report origin to Feedback.
- The page reuses `admin_campaign_detail`; no new RPC, table, grant or migration
  was added. It reads the same admin-only payload operations already sees.
- A tester activity row outside the current roster still opens: the mapper falls
  back to the seat row's stored values and labels the missing seat `Not on
  roster`.
- Usage still depends on migration `028`; when the payload has no usage data the
  page shows the same actionable migration notice as the tester detail page.
- `AdminTesterProjectView.xaml` is 393 lines, above the 300-line guideline. Its
  styles and templates are specific to this page, matching the existing detail
  pages; every C# partial touched here is under 300 lines.
- Verification: `dotnet build TesterLoop.sln -c Release` 0 warnings / 0 errors.
  The external WPF harness loaded `testerproject`, `testerdetail`,
  `reportdetail`, `campaigndetail`, `campaignlist`, `admin` and `shell` with
  `BINDING_COUNT=0`.
- Windows `0.15.0` was published and packaged for both apps and both
  architectures:
  - `build/win-x86/TesterLoop.exe` 141,824 bytes, file `0.15.0.0`, PE `0x14C`
  - `build/win-x64/TesterLoop.exe` 172,544 bytes, file `0.15.0.0`, PE `0x8664`
  - `build/admin-win-x86/TesterLoopAdmin.exe` 141,824 bytes, file `0.15.0.0`
  - `build/admin-win-x64/TesterLoopAdmin.exe` 172,544 bytes, file `0.15.0.0`
  - `build/win-x86/TesterLoop-Setup-x86.exe` 45,173,315 bytes
  - `build/win-x64/TesterLoop-Setup-x64.exe` 50,063,962 bytes
  - `build/admin-win-x86/TesterLoop-Admin-Setup-x86.exe` 45,112,178 bytes
  - `build/admin-win-x64/TesterLoop-Admin-Setup-x64.exe` 49,985,589 bytes
  All four installers report product version `0.15.0`.
- Not verified live: the tester project activity page, the origin-aware back
  button and the clickable report rows, because they need live operations data
  and an operations account. Installers remain unsigned and have not been run end
  to end.
- Security: no secrets, endpoints, RPC grants or validation rules changed. The
  page is read-only and limited to the existing admin-only dashboard payload.
  Installers remain unsigned; `032` and the QA purge remain owner-run.

### Modification 058

Date: 2026-11-08

#### Changes
- Fixed the TesterLoop Admin Operations top cards showing stale zeros. The five
  metric cards (DEVELOPERS, PENDING, ACTIVE PROJECTS, TESTERS, GROUPS) were bound
  to computed properties, but `LoadAsync` replaced `_counts` without raising a
  change notification. The view rendered before the dashboard request completed,
  so the cards kept the initial `0` values even after live counts arrived.
- `LoadAsync` now raises `DeveloperCount`, `PendingCount`, `LiveCount`,
  `TesterCount` and `GroupCount` immediately after `_counts` is assigned, so the
  cards update as soon as the dashboard returns.
- Version bumped to `0.15.1` in `AppConfig`, both projects, both installers and
  `medial_support.txt`.

#### Files / Components
- `src/TesterLoop.Admin/ViewModels/AdminViewModel.cs`
- `src/TesterLoop.Shared/Core/AppConfig.cs`
- `src/TesterLoop.Desktop/TesterLoop.Desktop.csproj`
- `src/TesterLoop.Admin/TesterLoop.Admin.csproj`
- `installer/TesterLoop.iss`, `installer/TesterLoop.Admin.iss`
- `medial_support.txt`, `AGENTS.md`, `AGENTS_PLAN.md`

#### Important Notes
- Root cause was a missing `Raise` call, not a SQL problem. The dashboard counts
  are returned by `admin_dashboard` as `counts.developers`, `pending`, `active`,
  `testers` and `groups`, and deserialize correctly; the cards simply were never
  told the values changed.
- No SQL, RPC, DTO, grant, secret or validation rule changed.
- Verification: `dotnet build TesterLoop.sln -c Release` 0 warnings / 0 errors.
  The external WPF harness reported `BINDING_COUNT=0` for the `admin` mode.
- Published and packaged `0.15.1` for both apps and both architectures:
  - `build/win-x86/TesterLoop.exe` 141,824 bytes, file `0.15.1.0`, PE `0x14C`
  - `build/win-x64/TesterLoop.exe` 172,544 bytes, file `0.15.1.0`, PE `0x8664`
  - `build/admin-win-x86/TesterLoopAdmin.exe` 141,824 bytes, file `0.15.1.0`,
    PE `0x14C`
  - `build/admin-win-x64/TesterLoopAdmin.exe` 172,544 bytes, file `0.15.1.0`,
    PE `0x8664`
  - `build/win-x86/TesterLoop-Setup-x86.exe` 45,172,914 bytes
  - `build/win-x64/TesterLoop-Setup-x64.exe` 50,063,488 bytes
  - `build/admin-win-x86/TesterLoop-Admin-Setup-x86.exe` 45,111,988 bytes
  - `build/admin-win-x64/TesterLoop-Admin-Setup-x64.exe` 49,985,581 bytes
  All four executables start, keep responsive windows titled `TesterLoop` /
  `TesterLoop Admin`, and were stopped after the check. All four installers
  report product version `0.15.1`.
- Not verified live: the cards with a real operations account, because no
  operations credentials were used this round. A leftover `TesterLoopAdmin`
  process (pid 13184) locked `build\admin-win-x64` and was stopped before
  publishing.
- Security: no secrets, endpoints, RPC grants or validation rules changed.
  Installers remain unsigned and have not been run end to end.

### Modification 059

Date: 2026-11-08

#### Changes
- Fixed the tester project clock so the 14-day countdown starts only after 12
  testers have confirmed opt-in, instead of counting from each tester's own
  join or opt-in date.
  - `tester_dashboard().mine` now joins `campaign_health` and returns
    `days = coalesce(ch.days_banked, 0)`, plus `clock_started_at`
    (`ch.threshold_opt_in_at`) and `confirmed_testers` (`ch.opted_in`).
  - `campaign_health` already zeroes `days_banked` until 12 testers are actively
    opted in and resets when the count drops below 12, so the client no longer
    invents its own day count.
- Windows tester workspace: `TesterCampaignDto` gained `ClockStartedAt` and
  `ConfirmedTesters`; the MY CAMPAIGNS row shows `Clock not started` until the
  clock begins, then `X of 14 days`.
- Android: added `core/ProjectClock.kt` with a shared `ProjectClock` and
  `MineItem.projectClock()`. The joined-project card, campaign hero and home
  hero now show `Waiting for N more confirmed testers` with an empty progress
  track before the clock starts, then `X of 14 days`; the home hero is labelled
  `LONGEST PROJECT CLOCK`.
- `MineItem` gained nullable `clockStartedAt` and `confirmedTesters` so a
  pre-migration payload falls back to the previous per-tester day count instead
  of showing a wrong zero.
- Added `sql/migrations/034_tester_project_clock.sql` for the live project:
  preflight for `campaign_health`, corrected `tester_dashboard`, revokes,
  authenticated-only grant and a PostgREST schema reload.
- Version bumped to `0.15.2` desktop and `1.2.4` (`versionCode 10204`) Android.
- This round also commits the previously uncommitted modifications 053-058
  (close-test project page, tester project activity, report usage split and the
  admin count refresh).

#### Files / Components
- `sql/functions/004_queries.sql`
- `sql/migrations/034_tester_project_clock.sql` (new)
- `src/TesterLoop.Shared/Core/Data/Contracts.cs`
- `src/TesterLoop.Desktop/ViewModels/TesterViewModel.cs`
- `mobile/app/src/main/kotlin/com/testerloop/app/core/ProjectClock.kt` (new)
- `mobile/app/src/main/kotlin/com/testerloop/app/data/api/Models.kt`
- `mobile/app/src/main/kotlin/com/testerloop/app/ui/components/ProjectCards.kt`
- `mobile/app/src/main/kotlin/com/testerloop/app/ui/campaign/CampaignSections.kt`
- `mobile/app/src/main/kotlin/com/testerloop/app/ui/home/HomeScreen.kt`
- `mobile/app/build.gradle.kts`
- `src/TesterLoop.Shared/Core/AppConfig.cs`,
  `src/TesterLoop.Desktop/TesterLoop.Desktop.csproj`,
  `src/TesterLoop.Admin/TesterLoop.Admin.csproj`
- `installer/TesterLoop.iss`, `installer/TesterLoop.Admin.iss`
- `release/mobile-version.json`, `release/TesterLoop-Mobile-1.2.4.apk`,
  `release/TesterLoop-Mobile-1.2.4.aab`
- `AGENTS.md`, `AGENTS_PLAN.md`, `medial_support.txt`

#### Important Notes
- The clock is the 12th confirmed opt-in, not a per-tester streak. A tester who
  joins on day one still sees zero until the project has 12 verified members,
  and if the confirmed count drops below 12 the clock returns to zero for
  everyone. That matches the Play rule and the developer view, which already
  used `campaign_health`.
- `campaign_health` is revoked from `anon` and `authenticated`, but
  `tester_dashboard` is `security definer`, so the join is legal and a tester
  still only sees their own joined projects.
- The Android fallback is deliberate: `confirmedTesters` is nullable, and a
  missing value means the live database has not run `034` yet, so the app keeps
  the old behaviour rather than showing "waiting" for an established project.
- Deployment: run `034` after `033` in the Supabase SQL Editor as `postgres`.
  Windows `0.15.2` and Android `1.2.4` work before the migration; they simply
  keep the previous day counts until it runs.
- Verification: `dotnet build TesterLoop.sln -c Release` 0 warnings / 0 errors.
  Android `:app:assembleDebug`, `:app:assembleRelease`, `:app:bundleRelease` and
  `:app:lintDebug` succeed; lint reports 0 errors, 26 warnings and 1 hint (the
  new warnings are dependency and deprecation notices).
- Published and packaged `0.15.2` for both apps and both architectures:
  - `build/win-x86/TesterLoop.exe` 141,824 bytes, file `0.15.2.0`, PE `0x14C`
  - `build/win-x64/TesterLoop.exe` 172,544 bytes, file `0.15.2.0`, PE `0x8664`
  - `build/admin-win-x86/TesterLoopAdmin.exe` 141,824 bytes, file `0.15.2.0`,
    PE `0x14C`
  - `build/admin-win-x64/TesterLoopAdmin.exe` 172,544 bytes, file `0.15.2.0`,
    PE `0x8664`
  - `build/win-x86/TesterLoop-Setup-x86.exe` 45,173,079 bytes
  - `build/win-x64/TesterLoop-Setup-x64.exe` 50,063,495 bytes
  - `build/admin-win-x86/TesterLoop-Admin-Setup-x86.exe` 45,112,220 bytes
  - `build/admin-win-x64/TesterLoop-Admin-Setup-x64.exe` 49,985,540 bytes
  All four installers report product version `0.15.2`.
- Android artifacts: `build/android/TesterLoop-Mobile-1.2.4-debug.apk`
  (19,010,311 bytes) and `build/android/TesterLoop-Mobile-1.2.4-release.apk`
  (13,043,980 bytes); `release/TesterLoop-Mobile-1.2.4.apk` (13,043,980 bytes)
  and `release/TesterLoop-Mobile-1.2.4.aab` (12,722,298 bytes). `aapt` reports
  `com.testerloop.app`, `versionCode 10204`, `versionName 1.2.4`, `minSdk 24`,
  `targetSdk 36`. `apksigner` confirms the existing upload certificate
  (SHA-256 `12f8382ff7f25781a718d438df51eb740858635a42c4e7d3fe3bc4fba3a84fd5`)
  and `jarsigner -verify` exits 0 for the AAB. The superseded `1.2.3` files were
  removed.
- Not verified live: the clock transition and the "waiting" copy, because `034`
  has not been applied and no Android device or accelerated emulator is
  available. SQL was reviewed statically only.
- Security: no secrets, endpoints or RPC grants changed. `tester_dashboard`
  stays revoked from `public` / `anon` and granted only to `authenticated`, and
  the new fields are the tester's own campaign clock, not another account's
  data. Installers remain unsigned and have not been run end to end.

### Modification 060

Date: 2026-11-08

#### Changes
- Fixed the mobile in-app update failing with "The update server answered 504".
  The updater called the GitHub REST API (`api.github.com/.../releases/latest`)
  once; a transient 504 from that endpoint aborted the check with no retry.
- Update checks now read the static release manifest first:
  `https://github.com/<owner>/<repo>/releases/latest/download/mobile-version.json`.
  The APK URL is built from the manifest `apk` field under the same
  `releases/latest/download/` path, so a normal check no longer touches the REST
  API at all. The API path remains as a fallback when the manifest is missing or
  invalid.
- Added retries with backoff to `AppUpdater`: three attempts for 5xx answers and
  transport failures on the check, manifest fetch and APK download. A 5xx now
  reads "The update server is busy (504). Try again in a minute." instead of the
  bare status message.
- Downloads are now verified against `Content-Length`; a truncated file is
  deleted and retried instead of being handed to the installer. Read timeout
  raised to 60 seconds for the ~13 MB APK on slow connections.
- Added `AppConfig.UPDATE_MANIFEST_URL` and `AppConfig.UPDATE_DOWNLOAD_BASE`.
- Android version bumped to `1.2.5` (`versionCode 10205`). Windows stays at
  `0.15.2`; no Windows source changed.

#### Files / Components
- `mobile/app/src/main/kotlin/com/testerloop/app/core/AppUpdater.kt`
- `mobile/app/src/main/kotlin/com/testerloop/app/core/AppConfig.kt`
- `mobile/app/build.gradle.kts`
- `release/mobile-version.json`, `release/TesterLoop-Mobile-1.2.5.apk`,
  `release/TesterLoop-Mobile-1.2.5.aab`
- `build/android/TesterLoop-Mobile-1.2.5-debug.apk`,
  `build/android/TesterLoop-Mobile-1.2.5-release.apk`
- `AGENTS.md`, `AGENTS_PLAN.md`, `medial_support.txt`

#### Important Notes
- Root cause: `api.github.com` answered `504` once and the client had no retry.
  The static manifest URL is served by `github.com` and redirected to the release
  asset, so it avoids the API gateway and its anonymous rate limits.
- The manifest-first path only trusts a version when `versionCode > 0` and the
  `apk` value matches `^[A-Za-z0-9._-]+\.apk$`; anything else falls back to the
  API path, so a malformed manifest cannot point the installer at another URL.
- A release without `mobile-version.json` still updates through the API fallback.
  A missing manifest (404) is treated as "use the API", not an error.
- Verification: `:app:assembleDebug`, `:app:assembleRelease`,
  `:app:bundleRelease` and `:app:lintDebug` succeed with 0 lint errors (26
  warnings, 1 hint, dependency/deprecation only). `aapt` reports
  `com.testerloop.app`, `versionCode 10205`, `versionName 1.2.5`, `minSdk 24`,
  `targetSdk 36`; `apksigner` confirms the existing upload certificate and
  `jarsigner -verify` exits 0 for the AAB.
- Artifacts: `build/android/TesterLoop-Mobile-1.2.5-debug.apk` 18,880,838 bytes,
  `build/android/TesterLoop-Mobile-1.2.5-release.apk` 13,043,980 bytes,
  `release/TesterLoop-Mobile-1.2.5.apk` 13,043,980 bytes and
  `release/TesterLoop-Mobile-1.2.5.aab` 12,723,297 bytes. Superseded `1.2.4`
  copies were removed.
- Not verified on a device: the retry path, the manifest-first check and the
  download integrity check. No Android device or accelerated emulator is
  available in this environment. Both update URLs were confirmed reachable from
  the build machine (HTTP 200, correct content type).
- A device still running `1.2.4` or older keeps the old updater until `1.2.5` is
  installed once; after that, checks use the static manifest and retries.
- Security: no secrets, endpoints or grants were added. The updater still only
  installs through the system package installer after the user confirms, and the
  manifest-derived APK name is validated before it is used.

### Modification 061

Date: 2026-11-08

#### Changes
- Removed the Git/GitHub in-app update feature from TesterLoop Mobile because the
  app is now distributed through Google Play, which owns updates.
  - Deleted `core/AppUpdater.kt` and `ui/AppVm.Update.kt`.
  - Removed the Profile `App update` card, the `update*` `UiState` fields and the
    `UiEvent.OpenInstallPermission` event.
  - Removed `REQUEST_INSTALL_PACKAGES`, the FileProvider provider and
    `res/xml/file_paths.xml`.
  - Removed `GITHUB_*` and `UPDATE_*` constants from `AppConfig`.
  - Deleted `release/mobile-version.json`; no release manifest is published any
    more.
- Renamed the Android application id and Kotlin package from `com.testerloop.app`
  to `lk.closetester.helper` (namespace, applicationId, source tree and all
  imports). This is a new Play listing identity; it is not an update to an app
  previously uploaded under the old id.
- Android bumped to `1.2.6` (`versionCode 10206`). Windows stays at `0.15.2`.
- The upload keystore and release signing config are unchanged.

#### Files / Components
- Removed: `mobile/app/src/main/kotlin/com/testerloop/app/core/AppUpdater.kt`,
  `ui/AppVm.Update.kt`, `mobile/app/src/main/res/xml/file_paths.xml`,
  `release/mobile-version.json`
- Moved: `mobile/app/src/main/kotlin/com/testerloop/app/` ->
  `mobile/app/src/main/kotlin/lk/closetester/helper/`
- `mobile/app/build.gradle.kts`, `mobile/app/src/main/AndroidManifest.xml`
- `mobile/app/src/main/kotlin/lk/closetester/helper/core/AppConfig.kt`,
  `ui/UiState.kt`, `ui/AppVm.kt`, `ui/AppVm.Auth.kt`,
  `ui/profile/ProfileScreen.kt`, `MainActivity.kt`
- `release/TesterLoop-Mobile-1.2.6.apk`, `release/TesterLoop-Mobile-1.2.6.aab`
- `build/android/TesterLoop-Mobile-1.2.6-debug.apk`,
  `build/android/TesterLoop-Mobile-1.2.6-release.apk`
- `AGENTS.md`, `AGENTS_PLAN.md`, `medial_support.txt`

#### Important Notes
- Devices still running 1.2.5 or older keep the old updater code until they are
  replaced by the Play build; the new build neither checks GitHub nor requests
  install permission.
- Verification: clean `:app:assembleDebug`, `:app:assembleRelease`,
  `:app:bundleRelease` and `:app:lintDebug` succeed; lint reports 0 errors and 11
  warnings (dependency/deprecation only). `aapt` reports package
  `lk.closetester.helper`, `versionCode 10206`, `versionName 1.2.6`,
  `minSdk 24`, `targetSdk 36`; `apksigner` confirms the existing upload
  certificate (SHA-256
  `12f8382ff7f25781a718d438df51eb740858635a42c4e7d3fe3bc4fba3a84fd5`) and
  `jarsigner -verify` exits 0 for the AAB. The permission dump no longer lists
  `REQUEST_INSTALL_PACKAGES`.
- Artifacts: `build/android/TesterLoop-Mobile-1.2.6-debug.apk` 18,863,915 bytes,
  `build/android/TesterLoop-Mobile-1.2.6-release.apk` 13,027,140 bytes,
  `release/TesterLoop-Mobile-1.2.6.apk` 13,027,140 bytes and
  `release/TesterLoop-Mobile-1.2.6.aab` 12,716,345 bytes. The superseded 1.2.5
  artifacts and `mobile-version.json` were removed.
- Not verified on a device: sign-in, join, opt-in, reports and usage sync under
  the new package id. No Android device or accelerated emulator is available.
- Security: the removal deletes the download-and-install surface (no
  `REQUEST_INSTALL_PACKAGES`, no FileProvider, no GitHub polling). The only
  network endpoints left are Supabase and the two validated Google links. No
  secrets changed; the upload keystore stays outside git.
- Still owed from earlier rounds: migrations `032`-`034` and the QA purge in
  `sql/maintenance/purge_test_accounts.sql`.

### Modification 062

Date: 2026-11-08

#### Changes
- Developers can now pay the project fee online by card through Lemon Squeezy
  (a Merchant of Record), instead of waiting for operations to confirm a manual
  payment. Operations can still record an offline payment; both paths write the
  same campaign payment state.
- Added `campaigns.payment_paid_via` (`manual` / `online`), `payment_provider`
  and `payment_provider_ref` (the provider order id), and a `payment_intents`
  table that tracks one checkout per attempt with the amount, currency,
  reference, provider checkout url, expiry, test-mode flag and state
  (`open` / `paid` / `expired` / `cancelled`).
- Added SQL functions: `prepare_payment_intent` (developer, 10 second cooldown,
  reuses an open intent), `attach_payment_checkout` (service role),
  `record_provider_payment` (service role; compares the provider order
  **subtotal** with the campaign fee, refuses a test-mode mismatch, marks the
  campaign paid, stamps `payment_paid_via = 'online'`, reserves the group
  identity and writes `payment.paid_online`), `record_provider_refund` (service
  role, audit only) and `expire_stale_payment_intents` (service role).
  `confirm_payment` now stamps `payment_paid_via = 'manual'` and supersedes any
  open intent.
- Added two Supabase Edge Functions: `create-payment` (JWT required, creates or
  reuses the Lemon Squeezy checkout for the caller's own project) and
  `ls-webhook` (HMAC-SHA256 hex signature check with a timing-safe compare,
  `order_created` and `order_refunded`, dedupe on the provider order id, 200 for
  events it does not own, 5xx only for transient database errors).
- Desktop: the project fee card gained `Pay $15.00 online` and
  `Check payment status`. The app opens the hosted checkout in the default
  browser, then polls the developer dashboard every five seconds for up to ten
  minutes and shows `Paid online` with the provider order id. The Play link
  stays locked until the fee is recorded.
- Added shared `PaymentCheckoutDto`, `SupabaseService.Payments.cs`
  (`StartOnlinePaymentAsync`), `CheckoutLink` (only
  `https://<store>.lemonsqueezy.com/checkout/...`), `LinkLauncher.TryOpenCheckout`
  and `DeveloperViewModel.Checkout.cs`.
- Admin: the close test project page shows how the fee was paid and the provider
  order id, so operations can reconcile a card payment with the project.
- Added `sql/migrations/035_online_payments.sql`; mirrored the columns, table,
  RLS, functions and grants into the greenfield SQL and bootstrap.
- Version bumped to `0.16.0` in `AppConfig`, both projects, both installers and
  `medial_support.txt`. Android stays at `1.2.6`; no mobile change was needed.

#### Files / Components
- `sql/migrations/035_online_payments.sql` (new)
- `sql/schema/001_init.sql`, `sql/policies/002_rls.sql`,
  `sql/functions/004_queries.sql`, `sql/functions/005_mutations.sql`,
  `sql/seed/007_admin_bootstrap.sql`
- `supabase/functions/create-payment/index.ts` (new),
  `supabase/functions/ls-webhook/index.ts` (new)
- `src/TesterLoop.Shared/Core/Data/Contracts.Payments.cs` (new),
  `SupabaseService.Payments.cs` (new), `Contracts.cs`,
  `Contracts.AdminDetail.cs`
- `src/TesterLoop.Shared/Core/CheckoutLink.cs` (new), `LinkLauncher.cs`
- `src/TesterLoop.Desktop/ViewModels/DeveloperViewModel.Checkout.cs` (new),
  `DeveloperViewModel.cs`, `DeveloperViewModel.Detail.cs`,
  `DeveloperViewModel.Payments.cs`, `DeveloperViewModel.Projects.cs`
- `src/TesterLoop.Desktop/Views/DeveloperProjectDetailView.xaml`
- `src/TesterLoop.Admin/ViewModels/AdminViewModel.Payments.cs`,
  `AdminViewModel.CampaignDetail.cs`, `AdminDetails.cs`
- `src/TesterLoop.Admin/Views/AdminCampaignDetailView.xaml`
- `src/TesterLoop.Shared/Core/AppConfig.cs`,
  `src/TesterLoop.Desktop/TesterLoop.Desktop.csproj`,
  `src/TesterLoop.Admin/TesterLoop.Admin.csproj`
- `installer/TesterLoop.iss`, `installer/TesterLoop.Admin.iss`
- `AGENTS.md`, `AGENTS_PLAN.md`, `medial_support.txt`

#### Important Notes
- Pricing is unchanged: the developer still pays `$15.00`. Lemon Squeezy keeps
  its fee (5% + 50c) and pays out to the owner's bank account, so the net is
  about `$13.75`. The app never claims the developer pays less or more.
- Tax is added by the provider on top of the price. The webhook therefore
  compares the order **subtotal** with `payment_amount_cents`; the total is
  stored only. An amount mismatch marks the intent paid but refuses to mark the
  campaign paid, so a wrong price cannot silently activate a project.
- A test-mode order can never mark a live campaign paid. `is_test` is compared
  with the `LS_TEST_MODE` Edge secret, and a mismatch returns
  `test_mode_mismatch` without changing the campaign.
- The webhook is the only writer of an online payment. It is verified with the
  `LS_WEBHOOK_SECRET` signature over the raw body, dedupes on
  `payment_intents.provider_order_id`, and records a summary-only audit row
  (event, order id, status, currency, total, test mode) with no customer PII.
  Refunds are audited, never reversed automatically.
- Secrets live only in Edge secrets: `LS_API_KEY`, `LS_STORE_ID`,
  `LS_VARIANT_ID`, `LS_WEBHOOK_SECRET`, `LS_TEST_MODE`. No provider key or
  webhook secret is shipped in a desktop client.
- `payment_intents` and the new service-role functions are revoked from
  `public`, `anon` and `authenticated`; the service-role functions are granted
  only to `service_role`. `prepare_payment_intent` requires the developer role
  and the caller's own campaign. The client cannot choose an amount, currency or
  checkout url.
- The desktop never trusts a browser redirect. It only reloads its own dashboard
  and treats `payment_state = 'paid'` as final, so a forged redirect changes
  nothing.
- Verification: `dotnet build TesterLoop.sln -c Release` 0 warnings / 0 errors.
  Published and packaged `0.16.0` for both apps and both architectures:
  - `build/win-x86/TesterLoop.exe` 141,824 bytes, file `0.16.0.0`, PE `0x14C`
  - `build/win-x64/TesterLoop.exe` 172,544 bytes, file `0.16.0.0`, PE `0x8664`
  - `build/admin-win-x86/TesterLoopAdmin.exe` 141,824 bytes, file `0.16.0.0`,
    PE `0x14C`
  - `build/admin-win-x64/TesterLoopAdmin.exe` 172,544 bytes, file `0.16.0.0`,
    PE `0x8664`
  - `build/win-x86/TesterLoop-Setup-x86.exe` 45,176,963 bytes
  - `build/win-x64/TesterLoop-Setup-x64.exe` 50,066,959 bytes
  - `build/admin-win-x86/TesterLoop-Admin-Setup-x86.exe` 45,114,592 bytes
  - `build/admin-win-x64/TesterLoop-Admin-Setup-x64.exe` 49,988,585 bytes
  All four executables start, keep responsive windows titled `TesterLoop` /
  `TesterLoop Admin`, and were stopped after the check. All four installers
  report product version `0.16.0`.
- Not verified live: the checkout, the webhook, the payment polling and the
  admin method display, because there is no Lemon Squeezy account, no
  `035` deployment and no operations account yet. SQL and TypeScript were
  reviewed statically only; no local Postgres, `psql`, `supabase` or `deno` CLI
  is available.
- Owner tasks before this can take money: create the Lemon Squeezy store,
  product and variant, generate an API key, register the webhook for
  `order_created` and `order_refunded`, set the five `LS_*` secrets, deploy
  `create-payment` and `ls-webhook`, then run `035` in the Supabase SQL editor.
- Known limitation: the updater-style polling stops after ten minutes; a slower
  payment is still recorded by the webhook and appears after a manual
  `Check payment status` or the next dashboard load.

### Modification 063

Date: 2026-11-08

#### Changes
- Added a static product website under `docs/`, publishable from GitHub Pages
  (`main` / `docs`) at
  `https://chamarawickramarathne-spec.github.io/close-test/`. The owner has no
  website, and Lemon Squeezy activation asks for a website URL or a social
  presence, so this site also serves as the merchant-of-record presence.
  - `docs/index.html`: product page with hero, six feature cards, five-step
    "how a project runs", pricing ($15 one-time, taxes by the provider), honest
    limits, seven-question FAQ and downloads link to the GitHub releases page.
  - `docs/terms.html`, `docs/privacy.html`, `docs/refunds.html`: policy pages
    required by a payment provider and useful to customers.
  - `docs/site.css`: one stylesheet, design tokens matching the desktop app
    (`#F7F4ED` background, `#0F766E` teal, `#EA580C` coral), system fonts only,
    no external assets, responsive and reduced-motion aware.
  - `docs/assets/`: logo 1024, icon 512 and icon 114 copied from `media/`,
    because Pages cannot serve files outside the published folder.
  - `docs/.nojekyll`, `docs/README.md` (publish steps, editing rules, placeholders).
- Added `docs/lemonsqueezy-activation.md`: signup without a website, store and
  product/variant creation, copy-paste activation answers, a banned-words table
  (Lemon Squeezy prohibits services and off-platform fulfilment, so the fee is
  described as software activation), identity and payout verification, the five
  `LS_*` values, Supabase secrets, the JWT-on/JWT-off deploy pair, webhook
  registration, test-mode end-to-end checks, go-live steps, a troubleshooting
  table and the fallback order (Paddle, then other MoRs, then the manual path).
- Site copy is deliberately honest: no claim of automatic Google Group creation,
  no guaranteed Play approval, usage scoped to joined project packages, no tester
  payout amount disclosed publicly. No invented Play Store link.
- No application source changed, so no build was required and the version stays
  `0.16.0`.

#### Files / Components
- `docs/index.html`, `docs/terms.html`, `docs/privacy.html`,
  `docs/refunds.html`, `docs/site.css`, `docs/.nojekyll`, `docs/README.md`,
  `docs/lemonsqueezy-activation.md` (new)
- `docs/assets/testerloop-logo-1024.png`,
  `docs/assets/testerloop-icon-512.png`, `docs/assets/testerloop-icon-114.png`
  (copied from `media/`)
- `AGENTS.md`, `AGENTS_PLAN.md`

#### Important Notes
- Every file in `docs/` is ASCII-only with no BOM, so it cannot be corrupted by a
  Windows editor. The site uses no JavaScript, cookies, analytics, CDN fonts or
  third-party scripts.
- The contact address was a placeholder in Modification 063 and was replaced with
  `primesentinel.kandy@gmail.com` in Modification 065.
- The hero image is a CSS mock, not a real screenshot. Real desktop and Android
  screenshots are still outstanding (global AGENTS.md section 10).
- Pages publishing is owner-run; the agent cannot enable it or verify the live
  URL. Verification here was limited to file presence, ASCII/BOM checks and
  balanced-tag checks on all four HTML files.
- Lemon Squeezy signup, activation, secrets, Edge deploys, webhook registration
  and `035` remain owner-run. No secret is stored in the site or the repo.

### Modification 064

Date: 2026-11-08

#### Changes
- Added `PAYMENT_SETUP.md` at the repository root: a checkbox go-live checklist
  with the real Lemon Squeezy identifiers filled in (Store ID `518607`, Variant
  ID `2351612`), the webhook URL, the migration order `032`-`035`, the JWT-on /
  JWT-off deploy pair, test-mode and live-mode steps, a troubleshooting table and
  a security note.
- Kept the file outside `docs/` so it is not published by GitHub Pages.

#### Files / Components
- `PAYMENT_SETUP.md` (new)
- `AGENTS.md`

#### Important Notes
- Store ID and Variant ID are not secrets; they appear in public checkout URLs.
  The API key and webhook signing secret are left blank on purpose and must stay
  in Supabase Edge secrets.
- Documentation only. No application source changed, so no build was required and
  the version stays `0.16.0`.
- ASCII-only, no BOM.

### Modification 065

Date: 2026-11-08

#### Changes
- Replaced the placeholder `support@testerloop.dev` with the owner's real support
  address `primesentinel.kandy@gmail.com` on every page and document:
  `docs/index.html`, `docs/terms.html`, `docs/privacy.html`,
  `docs/refunds.html`, `docs/README.md`, `docs/lemonsqueezy-activation.md` and
  `PAYMENT_SETUP.md`.
- Updated the surrounding wording: `docs/README.md` now states the address
  instead of asking for a replacement; the activation sheet's support-email field
  shows the address; `PAYMENT_SETUP.md` step 2 is now "Support email" with the
  first item ticked.
- Recorded the change in Modification 063 notes and `AGENTS_PLAN.md`.

#### Files / Components
- `docs/index.html`, `docs/terms.html`, `docs/privacy.html`,
  `docs/refunds.html`, `docs/README.md`, `docs/lemonsqueezy-activation.md`
- `PAYMENT_SETUP.md`
- `AGENTS.md`, `AGENTS_PLAN.md`

#### Important Notes
- Documentation only. No application source changed, so no build was required and
  the version stays `0.16.0`.
- The address is a normal Gmail account, not a custom-domain mailbox. The owner
  must confirm it is monitored before the Lemon Squeezy application, because both
  Lemon Squeezy and customers use it.
- No secret was added. All files remain ASCII-only with no BOM.

### Modification 066

Date: 2026-11-08

#### Changes
- Removed the Android build artifacts from Git tracking:
  `release/TesterLoop-Mobile-1.2.6.apk` and
  `release/TesterLoop-Mobile-1.2.6.aab`. The files stay on disk for the Play
  upload but are no longer versioned.
- `.gitignore` now ignores the whole `release/` folder. The earlier
  `!release/*.apk` and `!release/*.aab` exceptions were removed, because Play
  distributes the mobile builds and the repository should not carry binaries.
- Published GitHub release `desktop-v0.16.0` ("TesterLoop Desktop 0.16.0") with
  all four Windows installers: `TesterLoop-Setup-x64.exe`,
  `TesterLoop-Setup-x86.exe`, `TesterLoop-Admin-Setup-x64.exe` and
  `TesterLoop-Admin-Setup-x86.exe`. Stable asset names match the installer
  filenames, so the download URLs only change with the tag.
- The website now has a `#download` section on `docs/index.html` with direct
  64-bit and 32-bit installer buttons plus an "All downloads" link to the
  release tag. The header button points at `#download`, the footer "Downloads"
  link points at the tag, and `docs/README.md` records that those links must be
  bumped with each desktop release.

#### Files / Components
- `.gitignore`
- `docs/index.html`, `docs/README.md`
- Removed from Git: `release/TesterLoop-Mobile-1.2.6.apk`,
  `release/TesterLoop-Mobile-1.2.6.aab`
- GitHub release `desktop-v0.16.0`
- `AGENTS.md`, `AGENTS_PLAN.md`

#### Important Notes
- The release was created from the existing `0.16.0` installers in `build/`;
  no application source changed, so the version stays `0.16.0`.
- Release assets are unsigned, so SmartScreen may warn on first run. The site
  says so instead of implying a signed installer.
- The mobile APK/AAB are no longer recoverable from Git history changes made from
  this point, but earlier commits still contain the 1.2.6 binaries. Removing that
  history would need a rewrite and is not done.
- Verified: all four assets are attached, the two direct installer URLs and the
  tag URL return HTTP 200, and `docs/index.html` is still ASCII-only with no BOM.
- The desktop release tag is `desktop-v0.16.0`; mobile releases use
  `mobile-v*`, so the two do not collide.

### Modification 067

Date: 2026-11-08

#### Changes
- Removed the `Operations app` card from the website download section. The
  public page now offers only the two developer/tester installers; TesterLoop
  Admin is no longer advertised on the site.
- The download section uses a new two-column `.grid-2` layout instead of
  `.grid-3`, so the two cards are centred as a pair and collapse to one column on
  narrow screens.
- Removed the `All downloads` button that lived on the deleted card, and dropped
  the sentence that told visitors the operations app installs separately.

#### Files / Components
- `docs/index.html`, `docs/site.css`
- `AGENTS.md`, `AGENTS_PLAN.md`

#### Important Notes
- Documentation and site only. No application source changed, so no build and no
  version bump (`0.16.0` stays).
- The admin installers remain attached to `desktop-v0.16.0`; they are simply not
  linked from the public page. The footer `Downloads` link still opens the release
  tag, so they are reachable from there.
- Verified: `docs/index.html` has no `Operations app` text, tags balance, and the
  file is ASCII-only with no BOM.

### Modification 068

Date: 2026-11-08

#### Changes
- Replaced the developer card checkout with a single **Free Access** action.
  Pressing it activates the project with the fee waived for now; the normal
  package fee stays on record for when payment is re-enabled.
  - New `claim_free_access(p_campaign_id)` RPC: developer-only, requires a
    `pending` / `awaiting_link` project that is not already paid, marks
    `payment_state = 'paid'`, sets `payment_amount_cents = 0`,
    `payment_paid_via = 'free'`, stamps `paid_at`, reserves the group identity,
    expires any open `payment_intents`, and writes `payment.free_access` to the
    audit log.
  - Relaxed `campaigns_payment_amount_check` to `between 0 and 1000000` and
    `campaigns_payment_paid_via_check` to `('manual','online','free')`.
  - Removed the Lemon Squeezy checkout from the desktop developer flow: the
    `Pay $15.00 online` and `Check payment status` buttons are gone, along with
    the checkout polling. `SupabaseService.ClaimFreeAccessAsync` replaces
    `StartOnlinePaymentAsync` on the desktop side.
  - Developer project page: the payment card is now a single button
    (`FreeAccessButtonLabel` = `Free Access`) with `PROJECT ACCESS` as its
    eyebrow. Copy explains that activation starts group setup without payment
    for now.
  - Project detail, package summary and submit toast now say activation/free
    access rather than "pay the fee".
  - `PaymentAmountLabel` renders `Free access`, state reads
    `Free access activated`, the reference is hidden for a free activation and
    the admin project page labels the method `Free access`.
  - TesterLoop Admin is unchanged: operations can still confirm a manual
    payment, and the payment packages page keeps the normal fees and tester
    payouts.
- Added `sql/migrations/036_free_access.sql` for the live project: constraint
  updates, the new RPC, revokes, authenticated-only grant and a PostgREST schema
  reload.
- Mirrored the constraints, RPC and grant into the greenfield schema, functions
  and bootstrap.
- Refreshed `medial_support.txt` for `0.17.0` and reworded every developer
  payment claim to the free-access state.
- Updated the public site for this release: the pricing block now shows `$0` with
  free access during launch and the standard `$15` fee for when payment returns,
  and the `#download` buttons plus the footer Downloads link now point at
  `desktop-v0.17.0`.
- Version bumped to `0.17.0` in `AppConfig`, both projects and both installers.
  Android stays at `1.2.6`.

#### Files / Components
- `sql/migrations/036_free_access.sql` (new)
- `sql/schema/001_init.sql`, `sql/functions/005_mutations.sql`,
  `sql/seed/007_admin_bootstrap.sql`
- `src/TesterLoop.Shared/Core/Data/SupabaseService.cs`
- `src/TesterLoop.Desktop/ViewModels/DeveloperViewModel.cs`,
  `DeveloperViewModel.Checkout.cs`, `DeveloperViewModel.Payments.cs`,
  `DeveloperViewModel.Detail.cs`, `DeveloperViewModel.Projects.cs`
- `src/TesterLoop.Desktop/Views/DeveloperProjectDetailView.xaml`
- `src/TesterLoop.Shared/Core/AppConfig.cs`,
  `src/TesterLoop.Desktop/TesterLoop.Desktop.csproj`,
  `src/TesterLoop.Admin/TesterLoop.Admin.csproj`
- `installer/TesterLoop.iss`, `installer/TesterLoop.Admin.iss`
- `docs/index.html`
- `AGENTS.md`, `AGENTS_PLAN.md`, `medial_support.txt`

#### Important Notes
- Free access is a deliberate temporary product decision. `save_play_link` still
  requires a paid campaign, so `claim_free_access` writes the same paid state a
  manual confirmation would; only the amount and method differ.
- The Lemon Squeezy Edge Functions and the `payment_intents` model remain in the
  codebase. Nothing calls the checkout from the desktop app any more, so the
  `LS_*` owner setup is no longer needed for a developer to start a project.
- `payment_amount_cents = 0` means historical revenue reports will show a zero
  fee for projects activated during this period. A paid project keeps its real
  amount and is never overwritten by free access.
- Deployment: run `036` after `035` in the Supabase SQL editor as `postgres`.
  Until it runs, the Free Access button returns a 404 and the project stays
  unactivated.
- Verification: `dotnet build TesterLoop.sln -c Release` 0 warnings / 0 errors.
  Published and packaged `0.17.0` for both apps and both architectures:
  - `build/win-x86/TesterLoop.exe` 141,824 bytes, file `0.17.0.0`, PE `0x14C`
  - `build/win-x64/TesterLoop.exe` 172,544 bytes, file `0.17.0.0`, PE `0x8664`
  - `build/admin-win-x86/TesterLoopAdmin.exe` 141,824 bytes, file `0.17.0.0`,
    PE `0x14C`
  - `build/admin-win-x64/TesterLoopAdmin.exe` 172,544 bytes, file `0.17.0.0`,
    PE `0x8664`
  - `build/win-x86/TesterLoop-Setup-x86.exe` 45,175,994 bytes, product `0.17.0`
  - `build/win-x64/TesterLoop-Setup-x64.exe` 50,066,205 bytes, product `0.17.0`
  - `build/admin-win-x86/TesterLoop-Admin-Setup-x86.exe` 45,114,462 bytes,
    product `0.17.0`
  - `build/admin-win-x64/TesterLoop-Admin-Setup-x64.exe` 49,989,064 bytes,
    product `0.17.0`
  All four published executables start, keep responsive windows and were stopped
  after the check.
- Not verified live: the Free Access round-trip, because `036` has not been
  applied and no live developer account was used this round. The XAML was
  compiled but not driven through UI Automation.
- A leftover `TesterLoop` process (pid 12848, owned by another Windows session)
  could not be terminated. The four `build` executables were verified writable and
  publishing succeeded, so it did not affect the build.
- Security: no secrets or endpoints were added. `claim_free_access` is
  `security definer`, calls `require_developer()`, scopes the row to that
  developer's own campaign, is revoked from `public` / `anon` and granted only to
  `authenticated`. The reserved group identity is used for the reservation and
  recorded in the audit row, but it is not returned to the developer client. The
  amount and identity are server-controlled, so a tampered client cannot price or
  reserve a project itself.

### Modification 069

Date: 2026-11-08

#### Changes
- Added a stable desktop updater to both Windows apps. Each app checks a small
  release manifest, compares its own version, downloads the matching
  architecture installer, verifies its SHA-256 and launches it.
- The update URL never contains a version:
  `https://github.com/chamarawickramarathne-spec/close-test/releases/latest/download/desktop-version.json`
  and the installer links use `releases/latest/download/<asset>`. A new release
  replaces the assets behind the same names.
- Added `UpdateProduct`, `UpdateInfo`, `UpdateManifest`, `UpdateInstaller`,
  `UpdateService` and `UpdateCoordinator` in `TesterLoop.Shared/Core`.
- Added a `Check for updates` action and status line to the shared shell header,
  available to both desktop and admin sessions. The app checks once on startup
  after the workspace loads; a manual check reports "You are on the latest
  version." when there is nothing new.
- The coordinator shows `Install update X` when a newer version is found, then
  downloads with SHA-256 verification and starts the installer through the
  operating system, closing the running app first. Failed launches leave the app
  open and show the reason.
- `AppConfig` gained `UpdateManifestUrl`, `UpdateDownloadBase` and
  `ReleasesPageUrl`; version bumped to `0.17.1`.
- `scripts/build-installers.ps1` now writes `build/desktop-version.json` with the
  version, four stable asset names and their SHA-256 values after both installers
  compile.
- `docs/index.html` and `docs/README.md` now use the stable
  `releases/latest/download/...` links, so the download page never needs a version
  edit.
- Version bumped to `0.17.1` in `AppConfig`, both projects and both installers.

#### Files / Components
- `src/TesterLoop.Shared/Core/UpdateProduct.cs`,
  `UpdateInfo.cs`, `UpdateManifest.cs`, `UpdateInstaller.cs`,
  `UpdateService.cs`, `UpdateCoordinator.cs` (new)
- `src/TesterLoop.Shared/Views/ShellView.xaml`
- `src/TesterLoop.Desktop/ViewModels/ShellViewModel.cs`,
  `src/TesterLoop.Admin/ViewModels/AdminShellViewModel.cs`
- `src/TesterLoop.Shared/Core/AppConfig.cs`,
  `src/TesterLoop.Desktop/TesterLoop.Desktop.csproj`,
  `src/TesterLoop.Admin/TesterLoop.Admin.csproj`
- `scripts/build-installers.ps1`
- `docs/index.html`, `docs/README.md`
- `installer/TesterLoop.iss`, `installer/TesterLoop.Admin.iss`
- `AGENTS.md`, `AGENTS_PLAN.md`, `medial_support.txt`

#### Important Notes
- The updater accepts only `https`, a GitHub-hosted installer name matching
  `TesterLoop-Setup-*` or `TesterLoop-Admin-Setup-*`, and a 64-character SHA-256.
  A manifest entry that does not match is ignored rather than launched.
- Architecture is selected from the running process, so an x86 install receives
  the x86 installer and an x64 install receives the x64 installer.
- The startup check is quiet: a missing manifest, offline machine or transient
  failure does not interrupt the workspace. A manual check always reports a
  result.
- The first updater build must be installed by hand; only releases at or above
  `0.17.1` can use the updater.
- Build and packaging: `dotnet build TesterLoop.sln -c Release` 0 warnings /
  0 errors. All four installers compiled and report product version `0.17.1`:
  - `build/win-x86/TesterLoop-Setup-x86.exe` 45,184,104 bytes
  - `build/win-x64/TesterLoop-Setup-x64.exe` 50,074,185 bytes
  - `build/admin-win-x86/TesterLoop-Admin-Setup-x86.exe` 45,122,064 bytes
  - `build/admin-win-x64/TesterLoop-Admin-Setup-x64.exe` 49,996,060 bytes
  The four published executables report file version `0.17.1.0`; all four start,
  stay responsive and were stopped after the check.
- `build/desktop-version.json` lists version `0.17.1`, the four stable asset
  names and their SHA-256 hashes; every hash matches the compiled installer.
- Not verified live: the manifest download and the install hand-off, because the
  `0.17.1` release and its manifest are not published yet. No secrets or
  endpoints were added; the updater reads a public GitHub release.

