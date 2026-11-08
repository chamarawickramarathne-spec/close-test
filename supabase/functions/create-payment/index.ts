import { createClient } from "jsr:@supabase/supabase-js@2";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json(405, { error: "Method not allowed" });

  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader.startsWith("Bearer ")) {
      return json(401, { error: "Missing authorization" });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const apiKey = Deno.env.get("LS_API_KEY");
    const storeId = Deno.env.get("LS_STORE_ID");
    const variantId = Deno.env.get("LS_VARIANT_ID");
    const testMode = (Deno.env.get("LS_TEST_MODE") ?? "false").toLowerCase() === "true";

    if (!supabaseUrl || !anonKey || !serviceRoleKey) {
      return json(500, { error: "Server configuration missing" });
    }
    if (!apiKey || !storeId || !variantId) {
      return json(503, {
        error: "Online payment is not configured yet. Ask operations to confirm your fee.",
      });
    }

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userError } = await userClient.auth.getUser();
    if (userError || !userData?.user) {
      return json(401, { error: "Invalid session" });
    }

    const body = await req.json().catch(() => null);
    const campaignId = String(body?.campaign_id ?? "").trim();
    if (!UUID.test(campaignId)) {
      return json(400, { error: "campaign_id is not valid" });
    }

    const { data: intent, error: intentError } = await userClient.rpc(
      "prepare_payment_intent",
      { p_campaign_id: campaignId },
    );

    if (intentError) {
      const message = intentError.message ?? "Could not start the checkout.";
      const status = /already paid|not waiting/i.test(message) ? 409 : 400;
      return json(status, { error: message });
    }

    if (!intent) {
      return json(500, { error: "Could not start the checkout. Try again." });
    }

    if (intent.checkout_url) {
      return json(200, {
        checkout_url: intent.checkout_url,
        intent_id: intent.intent_id,
        expires_at: intent.expires_at,
        amount_cents: intent.amount_cents,
        currency: intent.currency,
      });
    }

    const productName = `Project fee - ${String(intent.app_name ?? "").trim()}`.slice(0, 90);

    const checkoutBody = {
      data: {
        type: "checkouts",
        attributes: {
          custom_price: Number(intent.amount_cents),
          product_options: { name: productName },
          checkout_data: {
            email: intent.developer_email ?? undefined,
            name: intent.developer_name || undefined,
            custom: {
              intent_id: intent.intent_id,
              campaign_id: campaignId,
            },
          },
          expires_at: intent.expires_at ?? undefined,
          test_mode: testMode,
        },
        relationships: {
          store: { data: { type: "stores", id: String(storeId) } },
          variant: { data: { type: "variants", id: String(variantId) } },
        },
      },
    };

    let checkoutRes: Response;
    try {
      checkoutRes = await fetch("https://api.lemonsqueezy.com/v1/checkouts", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${apiKey}`,
          Accept: "application/vnd.api+json",
          "Content-Type": "application/vnd.api+json",
        },
        body: JSON.stringify(checkoutBody),
        signal: AbortSignal.timeout(20000),
      });
    } catch {
      return json(502, {
        error: "The payment provider did not answer. Try again in a moment.",
      });
    }

    if (!checkoutRes.ok) {
      const detail = (await checkoutRes.text().catch(() => "")).slice(0, 300);
      console.error("Lemon Squeezy checkout failed:", checkoutRes.status, detail);
      return json(502, {
        error: "The payment provider rejected the checkout. Try again or ask operations.",
      });
    }

    const checkout = await checkoutRes.json().catch(() => null);
    const checkoutId = checkout?.data?.id;
    const checkoutUrl = checkout?.data?.attributes?.url;
    const checkoutExpires = checkout?.data?.attributes?.expires_at ?? intent.expires_at;

    if (!checkoutId || !checkoutUrl) {
      console.error("Lemon Squeezy checkout response was malformed");
      return json(502, {
        error: "The payment provider returned an unexpected answer. Try again.",
      });
    }

    const admin = createClient(supabaseUrl, serviceRoleKey);
    const { data: attached, error: attachError } = await admin.rpc(
      "attach_payment_checkout",
      {
        p_intent_id: intent.intent_id,
        p_checkout_id: String(checkoutId),
        p_checkout_url: String(checkoutUrl),
        p_expires_at: checkoutExpires ?? null,
        p_is_test: testMode,
      },
    );

    if (attachError) {
      console.error("attach_payment_checkout failed:", attachError.message);
      return json(500, { error: "Could not save the checkout. Try again." });
    }

    return json(200, {
      checkout_url: attached?.checkout_url ?? String(checkoutUrl),
      intent_id: intent.intent_id,
      expires_at: attached?.expires_at ?? checkoutExpires ?? null,
      amount_cents: intent.amount_cents,
      currency: intent.currency,
    });
  } catch (err) {
    console.error("create-payment failed:", err instanceof Error ? err.message : String(err));
    return json(500, { error: "Could not start the checkout. Try again." });
  }
});
