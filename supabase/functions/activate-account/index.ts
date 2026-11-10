import { createClient } from "jsr:@supabase/supabase-js@2";

const TOKEN = /^[0-9a-f]{64}$/;

const SITE = "https://chamarawickramarathne-spec.github.io/close-test/";

const PAGE = "https://chamarawickramarathne-spec.github.io/close-test/activate.html";

const HEADERS = {
  "Content-Type": "text/html; charset=utf-8",
  "Cache-Control": "no-store",
  "Referrer-Policy": "no-referrer",
  "X-Content-Type-Options": "nosniff",
  "X-Frame-Options": "DENY",
  "Content-Security-Policy":
    "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'",
};

function escapeHtml(value: string) {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function page(status: number, title: string, message: string, token = "") {
  const action = token
    ? `<form method="post" action="">
         <input type="hidden" name="token" value="${escapeHtml(token)}">
         <button type="submit">Activate my account</button>
       </form>`
    : "";
  const site = token
    ? ""
    : `<p class="muted">You can close this page and return to TesterLoop.</p>`;

  const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex,nofollow">
<title>${escapeHtml(title)} - TesterLoop</title>
<style>
  :root { color-scheme: light; }
  * { box-sizing: border-box; }
  body { margin:0; min-height:100vh; display:flex; align-items:center; justify-content:center;
    padding:24px; background:#f7f4ed; color:#12211e;
    font-family:Arial,Helvetica,sans-serif; }
  main { width:100%; max-width:520px; background:#fffdf8; border:1px solid #e3ded2;
    border-radius:18px; padding:32px; }
  .eyebrow { font-size:11px; letter-spacing:.16em; text-transform:uppercase;
    color:#0f766e; font-weight:700; }
  h1 { font-size:26px; line-height:1.2; margin:14px 0 10px; }
  p { font-size:15px; line-height:1.6; color:#5d6b67; margin:0 0 14px; }
  .muted { font-size:13px; color:#7a8783; }
  form { margin-top:24px; }
  button { width:100%; border:0; border-radius:999px; background:#0f766e; color:#fff;
    font-size:15px; font-weight:700; padding:15px 24px; cursor:pointer; }
  button:focus-visible { outline:3px solid #ea580c; outline-offset:3px; }
  a { color:#0f766e; font-weight:700; }
</style>
</head>
<body>
<main>
  <div class="eyebrow">TesterLoop</div>
  <h1>${escapeHtml(title)}</h1>
  <p>${escapeHtml(message)}</p>
  ${action}
  ${site}
  <p class="muted"><a href="${SITE}">TesterLoop website</a></p>
</main>
</body>
</html>`;

  return new Response(html, { status, headers: HEADERS });
}

Deno.serve(async (req) => {
  const url = new URL(req.url);
  let token = (url.searchParams.get("token") ?? "").trim().toLowerCase();

  if (req.method === "GET") {
    const target = PAGE + (TOKEN.test(token) ? "?token=" + encodeURIComponent(token) : "");
    return new Response(null, {
      status: 302,
      headers: {
        Location: target,
        "Cache-Control": "no-store",
        "Referrer-Policy": "no-referrer",
      },
    });
  }

  if (req.method !== "POST") {
    return page(405, "Method not allowed", "Open the activation link from your email instead.");
  }

  try {
    const contentType = req.headers.get("content-type") ?? "";
    if (contentType.includes("application/x-www-form-urlencoded")) {
      const form = await req.formData();
      token = String(form.get("token") ?? token).trim().toLowerCase();
    } else if (contentType.includes("application/json")) {
      const body = await req.json().catch(() => null);
      token = String(body?.token ?? token).trim().toLowerCase();
    }

    if (!TOKEN.test(token)) {
      return page(400, "This link is incomplete", "Open the activation link from your email again, or request a new one from the sign-in screen.");
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !serviceRoleKey) {
      return page(500, "Activation is unavailable", "The server is not configured. Contact operations.");
    }

    const admin = createClient(supabaseUrl, serviceRoleKey);
    const { data, error } = await admin.rpc("activate_account", { p_token: token });

    if (error) {
      const message = error.message ?? "";
      if (/expired/i.test(message)) {
        return page(400, "This link has expired", "Activation links last 24 hours. Request a new one from the TesterLoop sign-in screen.");
      }
      if (/already used/i.test(message)) {
        return page(400, "This link was already used", "Sign in to TesterLoop. If your account still will not open, request a new activation email.");
      }
      if (/not found|not valid/i.test(message)) {
        return page(400, "This link is not valid", "Request a new activation email from the TesterLoop sign-in screen.");
      }
      console.error("activate_account failed:", message);
      return page(400, "Activation did not complete", "Request a new activation email and try again.");
    }

    if (data?.already_active) {
      return page(200, "Your account is already active", "Open TesterLoop and sign in.");
    }

    return page(200, "Your account is activated", "Open TesterLoop and sign in with your email and password.");
  } catch (err) {
    console.error("activate-account failed:", err instanceof Error ? err.message : String(err));
    return page(400, "Activation did not complete", "Request a new activation email and try again.");
  }
});
