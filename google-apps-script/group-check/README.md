# TesterLoop Google Group check

Apps Script web app used by the `verify-opt-in` Supabase Edge Function. It
reports whether a tester's Google account is a direct member of a campaign's
Google Group.

## Setup

1. Open <https://script.new> while signed in as the Google account that owns or
   manages the campaign groups.
2. Rename the project to `TesterLoop Group Check`.
3. Replace `Code.gs` with the copy in this folder and add `appsscript.json` from
   this folder (Project Settings -> Show "appsscript.json" manifest).
4. Open Project Settings -> Script Properties and add
   `SHARED_SECRET` with a long random value.
5. Add `TEST_GROUP_EMAIL` with a real campaign group address this account can see,
   and optionally `TEST_MEMBER_EMAIL` with the tester address to check.
6. Run `testMembership()` and approve the Google Groups permission. The log shows
   the active/effective account, the groups it can see, and the membership result.
7. Deploy -> New deployment -> Web app.
   - Execute as: `Me`
   - Who has access: `Anyone`
8. Copy the `/exec` URL and the shared secret into the Supabase Edge Function
   secrets `GROUP_CHECK_URL` and `GROUP_CHECK_SECRET`. The URL must be `https`.
9. After changing `Code.gs`, edit the deployment and publish a new version. The
   URL stays the same.

## Membership action

Every request carries `secret`, `group` and `name`. `name` is the group's Google
Groups URL name (the last part of `https://groups.google.com/g/<name>`).
Membership is still looked up by the `group` address; `name` is validated and
echoed back so a mismatched slug is visible.

`membership` is the only action. Add `email` with the tester address.

```json
{
  "secret": "the-shared-secret",
  "action": "membership",
  "group": "hireartist@googlegroups.com",
  "name": "hireartist",
  "email": "tester@gmail.com"
}
```

Returns one of:

```json
{ "status": "active" }
{ "status": "inactive" }
{ "status": "error", "message": "..." }
{ "status": "error", "code": "group_unavailable", "message": "..." }
```

Only `active` may confirm an opt-in. `inactive` is a normal rejection. `error`
means the check could not run and must not confirm anything. `group_unavailable`
means the script account could not read the group or its member list; the Edge
Function turns that into "Contact operations".

## Testing and troubleshooting

- `testMembership()` no longer contains a sample group. It reads
  `TEST_GROUP_EMAIL` and `TEST_MEMBER_EMAIL` from Script Properties, so the same
  script works for every project.
- If you see "An error occurred while looking up roles in the group", the address
  does not exist or the executing account cannot see it. Sign in to
  groups.google.com with that account and confirm the group is listed.
- The log prints the groups the account can see. If the campaign group is not in
  that list, the account does not own or manage it.
- `GroupsApp.getGroupByEmail()` throws instead of returning `null`; the script
  catches that and returns `group_unavailable`.

## Limits

- The deploying Google account must be allowed to view the group's member list.
- `hasUser` checks direct membership only. Pending members and members inherited
  from a nested group are not active.
- The URL is reachable by anyone who has it; the shared secret is the gate.
- Apps Script quotas apply. Do not call the endpoint in a loop.
