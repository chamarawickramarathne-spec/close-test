# TesterLoop account activation email

This Apps Script web app sends the activation email for TesterLoop. It runs as
the Gmail account that owns it and is called only by the `send-activation`
Supabase Edge Function.

## Setup

1. Create a standalone Apps Script project at <https://script.google.com>.
2. Replace `Code.gs` with the file in this folder and `appsscript.json` with the
   manifest here.
3. Open **Project Settings > Script Properties** and add:
   - `SHARED_SECRET` - a long random value, also used as
     `ACTIVATION_SCRIPT_SECRET` in Supabase.
   - `ACTIVATION_LINK_BASE` -
     `https://omlhddzyitzjbcgrxvbn.supabase.co/functions/v1/activate-account`.
   - `SENDER_NAME` - optional sender name, for example `TesterLoop`.
4. Deploy as **Web app**, execute as **Me**, access **Anyone**.
5. Authorise the Gmail send scope when Google asks.
6. Copy the web app URL into the Supabase Edge secret
   `ACTIVATION_SCRIPT_URL`.
7. Deploy the `send-activation` and `activate-account` Edge Functions with
   `--no-verify-jwt`.

## Behaviour

- Only `POST` requests with the shared secret and `action: "activation"` are
  accepted.
- The message includes a 24-hour, single-use activation link built from
  `ACTIVATION_LINK_BASE` plus `?token=<64 hex>`.
- The function never logs the token and never returns it.
- `doGet` returns a health response only.
- `testSend` uses the `TEST_EMAIL` script property and a fake token. It is a
  delivery test, not a working activation link.

## Limits and rules

- Consumer Gmail sending from Apps Script is limited to roughly 100 recipients
  per day. Watch the quota before a large launch.
- Keep the script and sender address on the same Google account. Do not use a
  consumer Gmail address that does not match the sender.
- Do not put the shared secret in a desktop or mobile client.
- Do not remove the `https://` check on `ACTIVATION_LINK_BASE`.
- The activation page only activates after the user presses the button, so an
  email scanner that opens the link cannot consume it.
