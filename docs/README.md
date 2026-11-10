# TesterLoop website and seller setup

Static site used as the TesterLoop product website and as the policy pages that a
merchant-of-record application asks for (Terms, Privacy, Refund). No build step,
no cookies, no external fonts or CDNs. Every page is plain HTML except
`activate.html`, which uses one small inline script to read the activation token
from the link.

## Files

| File | Purpose |
|---|---|
| `index.html` | Product page: what it is, how a project runs, pricing, honest limits, FAQ |
| `terms.html` | Terms of Service |
| `privacy.html` | Privacy Policy |
| `refunds.html` | Refund Policy |
| `activate.html` | Account activation confirmation page; posts the token to the `activate-account` Edge Function |
| `site.css` | The only stylesheet |
| `lemonsqueezy-activation.md` | Seller activation answers plus the full go-live checklist |
| `assets/` | Logo and icon copies (GitHub Pages cannot serve `../media`) |
| `.nojekyll` | Stops GitHub Pages from running Jekyll |

`activate.html` is the only page with JavaScript. It exists because Supabase
rewrites the HTML of GET responses from Edge Functions to `text/plain`, so the
activation confirmation page cannot be served by the function itself. Keep its
form action pointed at
`https://omlhddzyitzjbcgrxvbn.supabase.co/functions/v1/activate-account`, and
keep the token handling in step with the function's 64-hex rule.

`lemonsqueezy-activation.md` is internal. It is not linked from the site.

## Publish

1. Push `main`.
2. Repository -> Settings -> Pages -> Source: **Deploy from a branch**, branch
   **main**, folder **/docs**.
3. Site appears at `https://chamarawickramarathne-spec.github.io/close-test/`.

Any change to a file in `docs/` goes live on the next push.

## Before you submit a payment application

- Support email is `primesentinel.kandy@gmail.com` on every page. Lemon Squeezy
  and customers both use it; change it in all four HTML files if it ever moves.
- Confirm the download section and footer link use the stable `releases/latest`
  paths (`https://github.com/chamarawickramarathne-spec/close-test/releases/latest`
  and `.../releases/latest/download/TesterLoop-Setup-x64.exe`). They never need a
  version bump.
- Every desktop release must attach `desktop-version.json` beside the four
  installers. The Windows in-app updater reads
  `releases/latest/download/desktop-version.json`, so a release without it cannot
  be discovered automatically.
- `releases/latest` must stay on a desktop release. Publish any non-desktop
  GitHub release as a pre-release, otherwise `latest` moves away and the updater
  receives a 404.
- Confirm the fee text is `$15` and that the Refund Policy matches what you will
  honour.
- If you later add a real Play Store listing, add that link; do not invent one.

## Editing rules

- Keep the files **ASCII-only**. Do not paste curly quotes, em dashes or
  non-Latin characters; use HTML entities such as `&middot;` if needed. This
  avoids mojibake on Windows editors.
- Do not add analytics, tracking pixels, chat widgets or external scripts.
- Do not add fonts or CSS from a CDN; the system font stack is deliberate.
- Do not claim automatic Google Group creation, guaranteed Google Play approval,
  whole-device monitoring, or a specific tester payout amount.
- Keep `assets/` in sync with `media/logos` and `media/icons` when branding
  changes.

## Outstanding

- Real product screenshots are not in the site yet. The hero uses a CSS mock.
  Capture the desktop workspace at 1280x800 and the Android campaign screen, then
  replace the mock with `<img>` elements in `docs/assets/`.
- No custom domain. Optional; add a `CNAME` file here if you buy one.
