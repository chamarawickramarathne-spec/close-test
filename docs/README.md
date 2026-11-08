# TesterLoop website and seller setup

Static site used as the TesterLoop product website and as the policy pages that a
merchant-of-record application asks for (Terms, Privacy, Refund). No build step,
no JavaScript, no cookies, no external fonts or CDNs.

## Files

| File | Purpose |
|---|---|
| `index.html` | Product page: what it is, how a project runs, pricing, honest limits, FAQ |
| `terms.html` | Terms of Service |
| `privacy.html` | Privacy Policy |
| `refunds.html` | Refund Policy |
| `site.css` | The only stylesheet |
| `lemonsqueezy-activation.md` | Seller activation answers plus the full go-live checklist |
| `assets/` | Logo and icon copies (GitHub Pages cannot serve `../media`) |
| `.nojekyll` | Stops GitHub Pages from running Jekyll |

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
- Confirm the download section and footer link point at the current desktop
  release tag (`https://github.com/chamarawickramarathne-spec/close-test/releases/tag/desktop-v0.16.0`).
  Update those links in `index.html` when a new desktop version is published.
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
