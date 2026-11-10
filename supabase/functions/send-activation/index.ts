import { createClient } from "jsr:@supabase/supabase-js@2";

const EMAIL = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

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

function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json(405, { error: "Method not allowed" });

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const scriptUrl = Deno.env.get("ACTIVATION_SCRIPT_URL");
    const scriptSecret = Deno.env.get("ACTIVATION_SCRIPT_SECRET");

    if (!supabaseUrl || !anonKey || !serviceRoleKey) {
      return json(500, { error: "Server configuration missing" });
    }
    if (!scriptUrl || !scriptSecret) {
      return json(503, { error: "Account activation email is not configured yet." });
    }

    let endpoint: URL;
    try {
      endpoint = new URL(scriptUrl);
    } catch {
      return json(503, { error: "Account activation email is not configured yet." });
    }
    if (endpoint.protocol !== "https:") {
      return json(503, { error: "Account activation email is not configured yet." });
    }

    const sendEmail = async (email: string, token: string) => {
      let response: Response;
      try {
        response = await fetch(endpoint.toString(), {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            secret: scriptSecret,
            action: "activation",
            email,
            token,
          }),
          signal: AbortSignal.timeout(15000),
        });
      } catch {
        throw new Error("The activation email service is unavailable.");
      }

      const contentType = response.headers.get("content-type") ?? "";
      const text = await response.text().catch(() => "");
      const snippet = text.slice(0, 300);

      if (!response.ok) {
        console.error("activation script http error:", response.status, contentType, snippet);
        throw new Error("The activation email service rejected the request.");
      }

      let result: { status?: string; message?: string } | null = null;
      try {
        result = JSON.parse(text);
      } catch {
        result = null;
      }

      if (!result) {
        console.error("activation script returned non-JSON:", contentType, snippet);
        throw new Error("The activation email could not be sent.");
      }

      if (result.status !== "ok") {
        console.error("activation script error:", result.message ?? "unknown error");
        throw new Error("The activation email could not be sent.");
      }
    };

    const admin = createClient(supabaseUrl, serviceRoleKey);
    const authHeader = req.headers.get("Authorization");
    const body = await req.json().catch(() => null);

    if (authHeader) {
      if (!authHeader.startsWith("Bearer ")) {
        return json(401, { error: "Invalid session" });
      }

      const userClient = createClient(supabaseUrl, anonKey, {
        global: { headers: { Authorization: authHeader } },
      });
      const { data: userData, error: userError } = await userClient.auth.getUser();
      if (userError || !userData?.user) {
        return json(401, { error: "Invalid session" });
      }

      const { data: profile } = await admin
        .from("profiles")
        .select("id, email, status")
        .eq("id", userData.user.id)
        .maybeSingle();

      if (!profile) {
        return json(404, { error: "Your account profile is incomplete. Contact operations." });
      }

      if (profile.status === "active") {
        return json(200, { ok: true, status: "active" });
      }

      const { data: issued, error: issueError } = await admin.rpc("create_activation_token", {
        p_profile_id: profile.id,
      });

      if (issueError) {
        console.error("create_activation_token failed:", issueError.message);
        return json(400, { error: "Could not create an activation link. Try again." });
      }

      if (!issued?.created) {
        return json(429, {
          error: "An activation email was sent recently. Check your inbox and wait a minute before trying again.",
        });
      }

      try {
        await sendEmail(String(profile.email ?? userData.user.email ?? ""), String(issued.token));
      } catch (error) {
        console.error("activation email failed:", error instanceof Error ? error.message : String(error));
        return json(502, { error: "The activation email could not be sent. Try again in a minute." });
      }

      await admin
        .from("account_activations")
        .update({ sent_at: new Date().toISOString() })
        .eq("id", issued.activation_id);

      return json(200, { ok: true, status: "sent" });
    }

    const email = String(body?.email ?? "").trim().toLowerCase();
    if (!EMAIL.test(email)) {
      await sleep(600);
      return json(200, { ok: true });
    }

    const { data: issued, error: issueError } = await admin.rpc("request_activation", {
      p_email: email,
    });

    if (issueError) {
      console.error("request_activation failed:", issueError.message);
      await sleep(600);
      return json(200, { ok: true });
    }

    if (issued?.created && issued.email) {
      try {
        await sendEmail(String(issued.email), String(issued.token));
        await admin
          .from("account_activations")
          .update({ sent_at: new Date().toISOString() })
          .eq("id", issued.activation_id);
      } catch (error) {
        console.error("resend activation email failed:", error instanceof Error ? error.message : String(error));
      }
    }

    await sleep(600);
    return json(200, { ok: true });
  } catch (err) {
    console.error("send-activation failed:", err instanceof Error ? err.message : String(err));
    return json(500, { error: "Could not send the activation email. Try again." });
  }
});
