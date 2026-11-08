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
    const groupCheckUrl = Deno.env.get("GROUP_CHECK_URL");
    const groupCheckSecret = Deno.env.get("GROUP_CHECK_SECRET");

    if (!supabaseUrl || !anonKey || !serviceRoleKey) {
      return json(500, { error: "Server configuration missing" });
    }
    if (!groupCheckUrl || !groupCheckSecret) {
      return json(503, { error: "Google Group check is not configured yet" });
    }

    let checkEndpoint: URL;
    try {
      checkEndpoint = new URL(groupCheckUrl);
    } catch {
      return json(503, { error: "Google Group check is not configured yet" });
    }
    if (checkEndpoint.protocol !== "https:") {
      return json(503, { error: "Google Group check is not configured yet" });
    }

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userError } = await userClient.auth.getUser();
    if (userError || !userData?.user) {
      return json(401, { error: "Invalid session" });
    }

    const admin = createClient(supabaseUrl, serviceRoleKey);

    const { data: tester } = await admin
      .from("testers")
      .select("id, google_email")
      .eq("auth_user_id", userData.user.id)
      .maybeSingle();

    if (!tester) {
      return json(403, { error: "Only testers can confirm opt-in" });
    }

    const body = await req.json().catch(() => null);
    const campaignId = String(body?.campaign_id ?? "").trim();
    if (!campaignId) {
      return json(400, { error: "campaign_id is required" });
    }
    if (!UUID.test(campaignId)) {
      return json(400, { error: "campaign_id is not valid" });
    }

    const { data: seat } = await admin
      .from("campaign_seats")
      .select("id, state")
      .eq("campaign_id", campaignId)
      .eq("tester_id", tester.id)
      .maybeSingle();

    if (!seat) {
      return json(403, { error: "Join this project before confirming opt-in" });
    }
    if (seat.state !== "joined" && seat.state !== "opted_in") {
      return json(400, { error: "This seat is not eligible for opt-in" });
    }

    const { data: campaign } = await admin
      .from("campaigns")
      .select("id, group_id")
      .eq("id", campaignId)
      .maybeSingle();

    if (!campaign) {
      return json(404, { error: "Project not found" });
    }
    if (!campaign.group_id) {
      return json(400, { error: "This project has no Google Group attached yet" });
    }

    const { data: group } = await admin
      .from("google_groups")
      .select("email, name")
      .eq("id", campaign.group_id)
      .maybeSingle();

    const groupEmail = group?.email?.trim().toLowerCase();
    const groupName = group?.name?.trim().toLowerCase();
    const testerEmail = tester.google_email?.trim().toLowerCase();

    if (!groupEmail || !groupName || !testerEmail) {
      return json(400, { error: "The group address, group name or Google account email is missing" });
    }

    const releaseSeat = async (): Promise<boolean> => {
      const { error } = await admin.rpc("release_unverified_seat", {
        p_tester_id: tester.id,
        p_campaign_id: campaignId,
      });
      if (error) {
        console.error("release_unverified_seat failed:", error.message);
        return false;
      }
      return true;
    };

    let checkRes: Response;
    try {
      checkRes = await fetch(checkEndpoint.toString(), {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          secret: groupCheckSecret,
          group: groupEmail,
          name: groupName,
          email: testerEmail,
        }),
        signal: AbortSignal.timeout(15000),
      });
    } catch {
      const released = await releaseSeat();
      return json(503, {
        error: released
          ? "Google Group check is unavailable. You were removed from this project so you can try again."
          : "Google Group check is unavailable. Try again in a moment.",
      });
    }

    if (!checkRes.ok) {
      const released = await releaseSeat();
      return json(503, {
        error: released
          ? "Google Group check is unavailable. You were removed from this project so you can try again."
          : "Google Group check is unavailable. Try again in a moment.",
      });
    }

    const check = await checkRes.json().catch(() => null);

    if (check?.status === "error") {
      const released = await releaseSeat();
      const suffix = released ? " You were removed from this project so you can try again." : "";
      if (check?.code === "group_unavailable") {
        console.error("Group check cannot read group:", groupEmail);
        return json(503, {
          error: `The Google Group check cannot read this project's group. Contact operations.${suffix}`,
        });
      }
      return json(503, { error: `Google Group check failed. Try again in a moment.${suffix}` });
    }
    if (check?.status !== "active") {
      const released = await releaseSeat();
      return json(403, {
        error: released
          ? `You are not listed as an active member of ${groupEmail}. You were removed from this project, so add ${testerEmail} to that Google Group and join again.`
          : `You are not listed as an active member of ${groupEmail}. Add ${testerEmail} to that Google Group and confirm again.`,
      });
    }

    const { data: result, error: rpcError } = await admin.rpc("record_verified_opt_in", {
      p_tester_id: tester.id,
      p_campaign_id: campaignId,
    });

    if (rpcError) {
      console.error("record_verified_opt_in failed:", rpcError.message);
      return json(400, { error: "Could not record the confirmed opt-in. Try again." });
    }

    return json(200, result);
  } catch (err) {
    console.error("verify-opt-in failed:", err instanceof Error ? err.message : String(err));
    return json(500, { error: "Could not complete the Google Group check. Try again." });
  }
});
