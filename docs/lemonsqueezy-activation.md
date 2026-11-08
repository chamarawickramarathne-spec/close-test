# Lemon Squeezy activation and go-live checklist

This sheet gets TesterLoop from "no Lemon Squeezy account" to "a developer can pay
$15 by card and the project unlocks". It assumes you have **no website of your
own** - the marketing site in this folder is enough.

Everything here is done by the owner. The TesterLoop apps are already built for
this; no code change is needed at any step.

---

## 0. What you need before you start

- An email address you check (this becomes the seller login).
- Passport or national ID card, plus one proof of address (bank statement or
  utility bill, dated in the last 3 months).
- A Sri Lankan bank account in your own name for payouts.
- This repository published on GitHub Pages (step 1) so you have a website URL.

Current live values used later in this sheet:

| Item | Value |
|---|---|
| Supabase project | `https://omlhddzyitzjbcgrxvbn.supabase.co` |
| Webhook URL | `https://omlhddzyitzjbcgrxvbn.supabase.co/functions/v1/ls-webhook` |
| Project fee | USD 15.00 (1500 cents) |
| Site URL (after step 1) | `https://chamarawickramarathne-spec.github.io/close-test/` |

---

## 1. Publish the website (5 minutes)

The site lives in `docs/` so GitHub Pages can serve it directly.

1. Push this repository to GitHub (`main` branch).
2. Repository -> **Settings** -> **Pages**.
3. Source: **Deploy from a branch**. Branch: **main**. Folder: **/docs**. Save.
4. Wait 1-2 minutes, then open
   `https://chamarawickramarathne-spec.github.io/close-test/`.

Check that the logo loads and that Terms, Privacy and Refunds open. If a page
404s, confirm the file is inside `docs/` and the folder setting is `/docs`, not
`/docs/docs`.

Optional but recommended: buy a short domain later and point it at Pages. Not
required for Lemon Squeezy activation.

---

## 2. Create the Lemon Squeezy account

You do **not** need a website to sign up.

1. Go to `https://app.lemonsqueezy.com/register`.
2. Sign up with your email and a strong password, then verify the email.
3. When asked to create a store, use the store name **TesterLoop** and pick a
   subdomain such as `testerloop` - this gives you
   `https://testerloop.lemonsqueezy.com`. **That hosted storefront is a website**
   and it is enough for activation.
4. Turn on two-factor authentication in account settings.

Note: Stripe now owns Lemon Squeezy and may offer Stripe Managed Payments
instead during onboarding. You may take that path if it is offered and available
in Sri Lanka; if not, continue with Lemon Squeezy as described here.

---

## 3. Create the product and variant

1. **Products** -> **New product**.
2. Name: `TesterLoop project activation`.
3. Type: **Digital product** (no physical shipping, no license keys - TesterLoop
   grants access itself).
4. Price: **$15.00 USD**, one-time. Keep this equal to the fee the app sends, so
   the checkout and the order subtotal always match.
5. Save. Open the product's single **variant** and copy two numbers from the
   browser URL or the API panel:
   - **Store ID**
   - **Variant ID**

Keep these for step 6.

---

## 4. Activation form - copy/paste answers

Lemon Squeezy asks for a website URL **or** a social presence. You have both now;
fill in as many fields as it shows.

| Field | Answer |
|---|---|
| Store name | TesterLoop |
| Website URL | `https://chamarawickramarathne-spec.github.io/close-test/` |
| Social media | Your GitHub profile URL, plus Facebook/Instagram/LinkedIn if you have one |
| Country | Sri Lanka |
| Product category | Software / Business tools |
| What do you sell? | Digital software access |
| Product description | See the paragraph below |
| How is it fulfilled? | Digitally, inside the customer's TesterLoop account, immediately after payment |
| Support email | `primesentinel.kandy@gmail.com` |

**Product description (copy this):**

> TesterLoop is a Windows and Android software service that helps Android
> developers run a Google Play closed test. A one-time project activation fee
> unlocks a project workspace, assisted setup of a dedicated Google Group on our
> account, tester seat and 14-day clock tracking, Google Group membership
> verification for testers, and bug reports with install and usage evidence.
> Access is delivered digitally inside the customer's TesterLoop account
> immediately after payment.

If a free-text "tell us about your business" box appears, add:

> I am an independent software developer based in Sri Lanka. I sell software
> access to my own product, TesterLoop. Customers pay once per project, then use
> the desktop and Android apps. There is no physical delivery and no consulting
> work. Refunds follow the published policy on the site.

### Words to avoid

Lemon Squeezy prohibits "services of any kind" and anything fulfilled outside
Lemon Squeezy. Describe the fee as **software activation**, never as a service
you perform for the customer.

| Do not write | Write instead |
|---|---|
| testing service | software for closed testing |
| we test your app | your project workspace |
| we create groups for you | assisted group setup included with the software |
| manual service / done for you | activation fee per project |
| consulting / agency | software product |

Do not claim Google affiliation, guaranteed Play approval, or automatic group
creation.

---

## 5. Identity and payout verification

1. Complete the seller identity form: legal name, address, date of birth.
2. Upload passport/NIC and proof of address.
3. Add the Sri Lankan bank account for payouts.
4. Approval usually takes **2-3 business days**. Test mode works the whole time,
   so you can finish steps 6-10 while you wait.

---

## 6. Collect the five values

From the Lemon Squeezy dashboard:

| Value | Where |
|---|---|
| `LS_API_KEY` | Settings -> API -> create key (test mode key first) |
| `LS_STORE_ID` | Store settings / product URL (step 3) |
| `LS_VARIANT_ID` | Product variant (step 3) |
| `LS_WEBHOOK_SECRET` | Settings -> Webhooks -> signing secret (step 9) |
| `LS_TEST_MODE` | `true` while testing, `false` when live |

Never paste these into a client app, a commit, or a chat message.

---

## 7. Add the Supabase Edge secrets

Supabase Dashboard -> Project Settings -> Edge Functions -> Secrets (or the
Supabase CLI `supabase secrets set`):

```
LS_API_KEY=<test mode API key>
LS_STORE_ID=<store id>
LS_VARIANT_ID=<variant id>
LS_WEBHOOK_SECRET=<webhook signing secret>
LS_TEST_MODE=true
```

`SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` are provided
by Supabase automatically; do not add them manually.

---

## 8. Deploy the two Edge Functions

The two functions have **different JWT settings**. Getting this wrong is the most
common failure.

| Function | Verify JWT | Why |
|---|---|---|
| `create-payment` | **ON** | It must know which developer is paying |
| `ls-webhook` | **OFF** | Lemon Squeezy sends no Supabase JWT |

Dashboard: Edge Functions -> Deploy new function -> paste
`supabase/functions/create-payment/index.ts`, leave "Verify JWT" enabled ->
Deploy. Repeat for `ls-webhook` with "Verify JWT" **disabled**.

CLI:

```
supabase functions deploy create-payment
supabase functions deploy ls-webhook --no-verify-jwt
```

Then run `sql/migrations/035_online_payments.sql` in the SQL Editor as `postgres`
(after 034). Until it runs, the pay button reports that online payment is not
deployed.

---

## 9. Register the webhook

1. Lemon Squeezy -> Settings -> Webhooks -> **New webhook**.
2. Callback URL:
   `https://omlhddzyitzjbcgrxvbn.supabase.co/functions/v1/ls-webhook`
3. Signing secret: generate one, save it as `LS_WEBHOOK_SECRET` (step 7), and
   redeploy if you set it after step 8.
4. Events: tick **order_created** and **order_refunded**. Nothing else.
5. Save. Lemon Squeezy sends a test event; a healthy function answers `200`.

---

## 10. Test mode end to end

1. In TesterLoop, sign in as a developer, create a project, open the fee card.
2. Press **Pay $15.00 online**. The browser opens the hosted checkout.
3. Pay with the Lemon Squeezy test card `4242 4242 4242 4242`, any future expiry,
   any CVC and postcode.
4. Back in TesterLoop, the card should move to **Paid online** within about five
   seconds (the app polls for up to ten minutes). If it does not, press
   **Check payment status**.
5. Confirm in Supabase (SQL Editor):

```
select payment_state, payment_paid_via, payment_provider, payment_provider_ref
from public.campaigns where id = '<campaign id>';

select state, is_test, provider_order_id, amount_cents, currency
from public.payment_intents where campaign_id = '<campaign id>';
```

Expected: campaign `paid` / `online` / `lemonsqueezy` / the order id, and the
intent `paid` with `is_test = true`.

6. Open the project in TesterLoop Admin and check the PAYMENT card shows the
   method and order id.

Test a refund too: refund the order in Lemon Squeezy, then confirm the webhook
answered 200 and `order_refunded` was logged. Refunds are recorded, never
auto-reversed.

---

## 11. Go live

1. Create a **live mode** API key in Lemon Squeezy.
2. Create a **live mode** webhook with the same callback URL and a live signing
   secret.
3. Update the secrets: `LS_API_KEY` (live key), `LS_WEBHOOK_SECRET` (live secret),
   `LS_TEST_MODE=false`.
4. Redeploy both functions if the dashboard does not pick up secrets
   automatically.
5. Repeat step 10 with a real card for a small real order, then refund it if you
   do not want to keep it.

After this, a developer's card payment marks the project paid, reserves the
Google Group identity, and operations continues with group setup.

---

## 12. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Webhook returns `401` | `ls-webhook` deployed with JWT verification on, or wrong signing secret | Redeploy with `--no-verify-jwt`; re-copy the secret |
| Webhook returns `503` | `LS_WEBHOOK_SECRET` missing | Add the secret, redeploy |
| Payment succeeds but project stays unpaid | `amount_mismatch` or `test_mode_mismatch` | Compare order **subtotal** with the project fee; check `LS_TEST_MODE` matches the order mode |
| Pay button says online payment is not deployed | `035` not applied, or `create-payment` not deployed | Run the migration; deploy the function |
| Checkout does not open | Store URL or variant ID wrong | Recheck `LS_STORE_ID` / `LS_VARIANT_ID`; only `*.lemonsqueezy.com/checkout/...` links are allowed |
| Status stuck after paying | Polling expired (10 minutes) | Press **Check payment status**, or let operations record the fee |

---

## 13. If Lemon Squeezy rejects the application

Fallback order:

1. **Paddle** - software-only merchant of record, accepts Sri Lanka. Needs a real
   site with pricing, Terms, Privacy and Refund pages; this `docs/` site already
   has them. Approval usually 5-7 days. Requires a small integration change.
2. **Creem, Dodo Payments or Polar** - verify Sri Lankan payout support before
   committing; each needs its own integration.
3. **Keep the shipped manual path** - operations records the $15 fee with
   `confirm_payment`; developers see "Pay in person" instructions. No online
   card payment, but the product still works.

Never move the fee collection into the desktop app itself. Card data must stay
with a merchant of record.
