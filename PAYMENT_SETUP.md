# TesterLoop - payment go-live checklist

Owner working copy. Fill in the two blanks at step 3 by hand; never commit the
API key or the webhook signing secret.

Known values:

| Item | Value |
|---|---|
| Lemon Squeezy store | TesterLoop |
| **Store ID** | `518607` |
| **Variant ID** | `2351612` |
| Price | USD 15.00 one-time |
| Supabase project | `https://omlhddzyitzjbcgrxvbn.supabase.co` |
| Webhook URL | `https://omlhddzyitzjbcgrxvbn.supabase.co/functions/v1/ls-webhook` |
| Site URL | `https://chamarawickramarathne-spec.github.io/close-test/` |

---

## 1. Publish the website

- [ ] GitHub repo -> Settings -> Pages
- [ ] Source: Deploy from a branch
- [ ] Branch: `main`, Folder: `/docs`
- [ ] Save, wait 1 minute
- [ ] Open `https://chamarawickramarathne-spec.github.io/close-test/`
- [ ] Check logo, Terms, Privacy, Refunds all load

## 2. Support email

- [x] Support email set to `primesentinel.kandy@gmail.com` on every page
- [ ] Confirm that inbox is monitored (Lemon Squeezy and customers use it)
- [ ] Commit and push (Pages updates automatically)

## 3. Lemon Squeezy account and activation

- [ ] Sign up at `https://app.lemonsqueezy.com/register`
- [ ] Verify email, enable 2FA
- [ ] Store name `TesterLoop`, subdomain `testerloop`
- [ ] Product `TesterLoop project activation`, Digital product, no license keys
- [ ] Price $15.00 USD, one-time
- [ ] Confirm Store ID `518607` and Variant ID `2351612` match the product
- [ ] Submit activation with the answers in `docs/lemonsqueezy-activation.md` section 4
      (website = Pages URL, social = GitHub profile)
- [ ] Upload passport/NIC + proof of address
- [ ] Add Sri Lankan bank account for payouts
- [ ] Wait for approval (usually 2-3 business days; test mode works now)

## 4. Edge secrets (test mode)

Supabase Dashboard -> Project Settings -> Edge Functions -> Secrets:

- [ ] `LS_API_KEY` = test mode API key (paste, do not save in this file)
- [ ] `LS_STORE_ID` = `518607`
- [ ] `LS_VARIANT_ID` = `2351612`
- [ ] `LS_WEBHOOK_SECRET` = test mode webhook signing secret (paste, do not save here)
- [ ] `LS_TEST_MODE` = `true`

Do not add `SUPABASE_URL`, `SUPABASE_ANON_KEY` or `SUPABASE_SERVICE_ROLE_KEY`;
Supabase provides them.

## 5. Deploy the Edge Functions

- [ ] Deploy `supabase/functions/create-payment/index.ts` with **Verify JWT ON**
- [ ] Deploy `supabase/functions/ls-webhook/index.ts` with **Verify JWT OFF**

CLI form:

```
supabase functions deploy create-payment
supabase functions deploy ls-webhook --no-verify-jwt
```

## 6. Database migrations

Run in the Supabase SQL Editor as `postgres`, in this order:

- [ ] `sql/migrations/032_daily_install_history.sql`
- [ ] `sql/migrations/033_fix_admin_campaign_detail.sql`
- [ ] `sql/migrations/034_tester_project_clock.sql`
- [ ] `sql/migrations/035_online_payments.sql`

Each should end with a PostgREST schema reload and report success.

## 7. Webhook

- [ ] Lemon Squeezy -> Settings -> Webhooks -> New webhook
- [ ] URL: `https://omlhddzyitzjbcgrxvbn.supabase.co/functions/v1/ls-webhook`
- [ ] Generate signing secret, save as `LS_WEBHOOK_SECRET`, redeploy `ls-webhook`
- [ ] Events: `order_created` and `order_refunded` only
- [ ] Save, confirm the test event returns 200

## 8. Test mode end to end

- [ ] Sign in to TesterLoop as a developer
- [ ] Create a project
- [ ] Open the fee card, press **Pay $15.00 online**
- [ ] Checkout opens in the browser
- [ ] Pay with `4242 4242 4242 4242`, future expiry, any CVC
- [ ] Project shows **Paid online** within about 5 seconds
      (or press **Check payment status**)

Verify in SQL:

```
select payment_state, payment_paid_via, payment_provider, payment_provider_ref
from public.campaigns where id = '<campaign id>';

select state, is_test, provider_order_id, amount_cents, currency
from public.payment_intents where campaign_id = '<campaign id>';
```

- [ ] Campaign: `paid` / `online` / `lemonsqueezy` / order id
- [ ] Intent: `paid`, `is_test = true`
- [ ] Admin project page PAYMENT card shows method and order id
- [ ] Refund the test order in Lemon Squeezy, confirm webhook 200 and audit row

## 9. Go live

- [ ] Create live mode API key
- [ ] Create live mode webhook (same URL, new signing secret)
- [ ] Update `LS_API_KEY` to the live key
- [ ] Update `LS_WEBHOOK_SECRET` to the live secret
- [ ] Set `LS_TEST_MODE` = `false`
- [ ] Redeploy both functions
- [ ] Run one small real card payment
- [ ] Refund it if not keeping it
- [ ] Confirm campaign shows `paid` / `online` / order id

## 10. If it does not work

| Symptom | Fix |
|---|---|
| Webhook `401` | `ls-webhook` has JWT verification on, or wrong signing secret |
| Webhook `503` | `LS_WEBHOOK_SECRET` missing; add it and redeploy |
| Paid but project stays unpaid | `amount_mismatch` (order subtotal != 1500) or `test_mode_mismatch` |
| "Online payment is not deployed" | Migration `035` not run, or `create-payment` not deployed |
| Checkout will not open | Wrong store/variant ID; only `*.lemonsqueezy.com/checkout/...` is allowed |
| Status stuck | Polling expired after 10 minutes; press **Check payment status** |

Full details: `docs/lemonsqueezy-activation.md`.

---

## Security notes

- Store ID and Variant ID are not secrets; they appear in public checkout URLs.
- `LS_API_KEY` and `LS_WEBHOOK_SECRET` are secrets. They belong only in Supabase
  Edge secrets. Never paste them into this file, a client app, or a commit.
- Refunds are recorded, never reversed automatically.
- A test-mode order can never mark a live project paid.
