import { createClient } from "jsr:@supabase/supabase-js@2";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function hexToBytes(hex: string): Uint8Array | null {
  if (hex.length === 0 || hex.length % 2 !== 0 || !/^[0-9a-f]+$/i.test(hex)) {
    return null;
  }
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i += 1) {
    out[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  }
  return out;
}

function constantTimeEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i += 1) {
    diff |= a[i] ^ b[i];
  }
  return diff === 0;
}

async function signHex(secret: string, body: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(body));
  return Array.from(new Uint8Array(signature))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "Method not allowed" });

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const webhookSecret = Deno.env.get("LS_WEBHOOK_SECRET");

    if (!supabaseUrl || !serviceRoleKey) {
      return json(500, { error: "Server configuration missing" });
    }
    if (!webhookSecret) {
      return json(503, { error: "Webhook is not configured yet" });
    }

    const raw = await req.text();
    const provided = hexToBytes(req.headers.get("X-Signature") ?? "");
    const expected = hexToBytes(await signHex(webhookSecret, raw));

    if (!provided || !expected || !constantTimeEqual(provided, expected)) {
      return json(401, { error: "Invalid signature" });
    }

    const payload = JSON.parse(raw);
    const eventName = String(payload?.meta?.event_name ?? "");
    const custom = payload?.meta?.custom_data ?? {};
    const intentId = String(custom?.intent_id ?? "");
    const attributes = payload?.data?.attributes ?? {};
    const orderId = String(payload?.data?.id ?? "");

    const admin = createClient(supabaseUrl, serviceRoleKey);

    if (eventName === "order_created") {
      if (attributes?.status !== "paid") {
        return json(200, { received: true, ignored: `status:${attributes?.status ?? "unknown"}` });
      }
      if (!UUID.test(intentId) || !orderId) {
        console.error("order_created without a usable intent or order id");
        return json(200, { received: true, matched: false });
      }

      const summary = {
        event: eventName,
        order_id: orderId,
        status: attributes?.status ?? null,
        currency: attributes?.currency ?? null,
        total: attributes?.total ?? null,
        test_mode: attributes?.test_mode ?? null,
      };

      const { data, error } = await admin.rpc("record_provider_payment", {
        p_intent_id: intentId,
        p_order_id: orderId,
        p_subtotal_cents: Number(attributes?.subtotal ?? 0),
        p_total_cents: Number(attributes?.total ?? 0),
        p_currency: String(attributes?.currency ?? ""),
        p_is_test: Boolean(attributes?.test_mode),
        p_payload: summary,
      });

      if (error) {
        if (/no longer exists/i.test(error.message ?? "")) {
          console.error("record_provider_payment could not match the checkout:", orderId);
          return json(200, { received: true, matched: false });
        }
        console.error("record_provider_payment failed:", error.message);
        return json(500, { error: "Could not record the payment" });
      }

      return json(200, { received: true, status: data?.status ?? "paid" });
    }

    if (eventName === "order_refunded") {
      if (!orderId) {
        return json(200, { received: true, matched: false });
      }

      const { data, error } = await admin.rpc("record_provider_refund", {
        p_order_id: orderId,
        p_amount_cents: Number(attributes?.refunded_amount ?? attributes?.total ?? 0),
        p_payload: {
          event: eventName,
          order_id: orderId,
          status: attributes?.status ?? null,
          currency: attributes?.currency ?? null,
        },
      });

      if (error) {
        console.error("record_provider_refund failed:", error.message);
        return json(500, { error: "Could not record the refund" });
      }

      return json(200, { received: true, status: data?.status ?? "recorded" });
    }

    return json(200, { received: true, ignored: eventName || "unknown" });
  } catch (err) {
    console.error("ls-webhook failed:", err instanceof Error ? err.message : String(err));
    return json(500, { error: "Webhook could not be processed" });
  }
});
