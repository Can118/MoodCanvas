/**
 * send-mood-push — Edge Function
 *
 * Sends a silent APNs push to every group member except the person who
 * just updated their mood. The push carries only content-available:1 so
 * iOS wakes the app in the background and WidgetKit reloads all timelines.
 *
 * Secrets required (set via `supabase secrets set`):
 *   APNS_AUTH_KEY    — contents of the .p8 file from Apple Developer portal
 *   APNS_KEY_ID      — 10-character Key ID shown next to the .p8 download
 *   APNS_TEAM_ID     — 10-character Team ID from Apple Developer account page
 *   APNS_BUNDLE_ID   — com.huseyinturkay.moodcanvas.app  (or override)
 *   APNS_ENVIRONMENT — "sandbox" (default, for dev builds) or "production"
 */

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const JSON_HEADERS = { ...CORS, "Content-Type": "application/json" };

// ── APNs JWT (ES256) ─────────────────────────────────────────────────────────

async function makeApnsJWT(
  teamId: string,
  keyId: string,
  privateKeyPem: string,
): Promise<string> {
  // Normalise PEM — secrets are sometimes stored with literal \n escapes
  const pem = privateKeyPem.replace(/\\n/g, "\n");
  const pemContent = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");

  const keyData = Uint8Array.from(atob(pemContent), (c) => c.charCodeAt(0));

  const key = await crypto.subtle.importKey(
    "pkcs8",
    keyData.buffer,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );

  const now = Math.floor(Date.now() / 1000);

  const b64url = (str: string) =>
    btoa(str).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");

  const header  = b64url(JSON.stringify({ alg: "ES256", kid: keyId }));
  const payload = b64url(JSON.stringify({ iss: teamId, iat: now }));
  const message = `${header}.${payload}`;

  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(message),
  );

  const sig = btoa(String.fromCharCode(...new Uint8Array(signature)))
    .replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");

  return `${message}.${sig}`;
}

// ── Handler ──────────────────────────────────────────────────────────────────

serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  try {
    const { group_id, updated_by } = await req.json();
    if (!group_id || !updated_by) {
      return new Response(
        JSON.stringify({ error: "Missing group_id or updated_by" }),
        { status: 400, headers: JSON_HEADERS },
      );
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { persistSession: false } },
    );

    // 1. Get all group members except the person who changed their mood
    const { data: members, error: membersErr } = await supabase
      .from("group_members")
      .select("user_id")
      .eq("group_id", group_id)
      .neq("user_id", updated_by);

    if (membersErr) throw membersErr;
    if (!members || members.length === 0) {
      return new Response(JSON.stringify({ sent: 0 }), { headers: JSON_HEADERS });
    }

    // 2. Look up their device tokens
    const userIds = members.map((m: { user_id: string }) => m.user_id);
    const { data: tokenRows, error: tokensErr } = await supabase
      .from("device_tokens")
      .select("token")
      .in("user_id", userIds);

    if (tokensErr) throw tokensErr;
    if (!tokenRows || tokenRows.length === 0) {
      return new Response(JSON.stringify({ sent: 0 }), { headers: JSON_HEADERS });
    }

    // 3. Build APNs auth JWT
    const teamId   = Deno.env.get("APNS_TEAM_ID");
    const keyId    = Deno.env.get("APNS_KEY_ID");
    const authKey  = Deno.env.get("APNS_AUTH_KEY");
    const bundleId = Deno.env.get("APNS_BUNDLE_ID") ?? "com.huseyinturkay.moodcanvas.app";
    const apnsHost = Deno.env.get("APNS_ENVIRONMENT") === "production"
      ? "api.push.apple.com"
      : "api.sandbox.push.apple.com";

    if (!teamId || !keyId || !authKey) {
      throw new Error("APNS_TEAM_ID, APNS_KEY_ID, or APNS_AUTH_KEY secret not configured");
    }

    const apnsJWT = await makeApnsJWT(teamId, keyId, authKey);
    // Include a custom "mood-update" key so the iOS AppDelegate can identify
    // this push before Firebase's canHandleNotification() has a chance to
    // consume it. Firebase 11 silently swallows any content-available:1 push
    // that reaches canHandleNotification() first — the custom key lets us
    // short-circuit that check.
    const pushPayload = JSON.stringify({ aps: { "content-available": 1 }, "mood-update": 1 });

    // 4. Send silent push to each device
    let sent = 0;
    for (const { token } of tokenRows) {
      try {
        const res = await fetch(`https://${apnsHost}/3/device/${token}`, {
          method: "POST",
          headers: {
            "authorization": `bearer ${apnsJWT}`,
            "apns-topic":     bundleId,
            "apns-push-type": "background",
            "apns-priority":  "5",          // 5 = normal priority, required for background
            "content-type":   "application/json",
          },
          body: pushPayload,
        });

        if (res.ok) {
          sent++;
          console.log(`APNs accepted token (sent=${sent})`);
        } else {
          const body = await res.text();
          console.error(`APNs rejected token (${res.status}): ${body}`);
          // 410 = Unregistered: app was uninstalled. Safe to remove — the token
          // is permanently dead and the user would re-register on reinstall.
          //
          // 400 BadDeviceToken is intentionally NOT deleted here. It can mean:
          //   a) APNS_ENVIRONMENT secret is wrong (sandbox vs production mismatch)
          //   b) The token is from a very recent rotation that APNs hasn't propagated yet
          // In both cases, deleting the token permanently breaks push notifications until
          // the user reopens the app. Leaving it means we try once per push cycle, which
          // is acceptable. Fix the APNS_ENVIRONMENT secret to resolve case (a).
          if (res.status === 410) {
            const { error: deleteErr } = await supabase
              .from("device_tokens")
              .delete()
              .eq("token", token);
            if (deleteErr) {
              console.error(`Failed to remove unregistered token: ${deleteErr.message}`);
            } else {
              console.log(`Removed unregistered APNs token (410) from database`);
            }
          }
        }
      } catch (e) {
        console.error("APNs fetch failed:", (e as Error).message);
      }
    }

    return new Response(JSON.stringify({ sent }), { headers: JSON_HEADERS });
  } catch (err) {
    console.error("send-mood-push error:", (err as Error).message);
    return new Response(
      JSON.stringify({ error: "Internal server error" }),
      { status: 500, headers: JSON_HEADERS },
    );
  }
});
