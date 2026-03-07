/**
 * send-invite-push — Edge Function
 *
 * Sends a silent APNs push to a user who has just been invited to a group,
 * waking their app so fetchPendingInvitations() runs and the invitation
 * card appears in real-time without requiring a manual app restart.
 *
 * Request body: { group_id: string, invited_user_id: string }
 * Auth:         Bearer <supabase-jwt>  (caller must be a member of group_id)
 *
 * Uses the same "mood-update" payload key as send-mood-push so AppDelegate's
 * existing handler wakes the app, syncs the JWT, and posts moodUpdateReceived
 * — which triggers fetchGroups() + fetchPendingInvitations() on the recipient.
 */

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { verify } from "https://deno.land/x/djwt@v3.0.2/mod.ts";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const JSON_HEADERS = { ...CORS, "Content-Type": "application/json" };

// ── Rate limiter: 30 invite pushes per user per minute ───────────────────────
const rateLimitStore = new Map<string, { count: number; resetAt: number }>();
function isRateLimited(uid: string): boolean {
  const now = Date.now();
  let entry = rateLimitStore.get(uid);
  if (!entry || entry.resetAt < now) {
    entry = { count: 0, resetAt: now + 60_000 };
    rateLimitStore.set(uid, entry);
  }
  if (entry.count >= 30) return true;
  entry.count++;
  return false;
}

// ── APNs ES256 JWT ────────────────────────────────────────────────────────────
async function makeApnsJWT(
  teamId: string,
  keyId: string,
  privateKeyPem: string,
): Promise<string> {
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

// ── JWT verification ──────────────────────────────────────────────────────────
async function verifyJWT(token: string, secret: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["verify"],
  );
  const payload = await verify(token, key);
  const sub = payload.sub;
  if (typeof sub !== "string" || !sub) throw new Error("Missing sub claim");
  return sub;
}

// ── Handler ───────────────────────────────────────────────────────────────────
serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  try {
    // 1. Verify JWT
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader.startsWith("Bearer ")) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401, headers: JSON_HEADERS });
    }
    const jwtSecret = Deno.env.get("JWT_SECRET");
    if (!jwtSecret) throw new Error("JWT_SECRET not configured");
    let callerId: string;
    try {
      callerId = await verifyJWT(authHeader.slice(7), jwtSecret);
    } catch {
      return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401, headers: JSON_HEADERS });
    }

    // 2. Rate limit
    if (isRateLimited(callerId)) {
      return new Response(
        JSON.stringify({ error: "Rate limit exceeded. Try again in a minute." }),
        { status: 429, headers: { ...JSON_HEADERS, "Retry-After": "60" } },
      );
    }

    // 3. Parse body
    let body: { group_id?: string; invited_user_id?: string };
    try { body = await req.json(); } catch {
      return new Response(JSON.stringify({ error: "Invalid JSON" }), { status: 400, headers: JSON_HEADERS });
    }
    const { group_id, invited_user_id } = body;
    if (!group_id || !invited_user_id) {
      return new Response(JSON.stringify({ error: "Missing group_id or invited_user_id" }), { status: 400, headers: JSON_HEADERS });
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { persistSession: false } },
    );

    // 4. Verify caller is a member of the group (prevents pushing arbitrary users)
    const { data: membership } = await supabase
      .from("group_members")
      .select("user_id")
      .eq("group_id", group_id)
      .eq("user_id", callerId)
      .maybeSingle();

    if (!membership) {
      return new Response(JSON.stringify({ error: "Forbidden" }), { status: 403, headers: JSON_HEADERS });
    }

    // 5. Get invited user's device token
    //    If they haven't opened the app yet there's no token — that's fine.
    //    They'll see the invitation on next launch (scenePhase → active → fetchPendingInvitations).
    const { data: tokenRow } = await supabase
      .from("device_tokens")
      .select("token")
      .eq("user_id", invited_user_id)
      .maybeSingle();

    if (!tokenRow?.token) {
      return new Response(JSON.stringify({ sent: 0 }), { headers: JSON_HEADERS });
    }

    // 6. Build APNs auth JWT
    const teamId   = Deno.env.get("APNS_TEAM_ID");
    const keyId    = Deno.env.get("APNS_KEY_ID");
    const authKey  = Deno.env.get("APNS_AUTH_KEY");
    const bundleId = Deno.env.get("APNS_BUNDLE_ID") ?? "com.huseyinturkay.moodcanvas.app";
    const apnsHost = Deno.env.get("APNS_ENVIRONMENT") === "production"
      ? "api.push.apple.com"
      : "api.sandbox.push.apple.com";

    if (!teamId || !keyId || !authKey) {
      throw new Error("APNS_TEAM_ID, APNS_KEY_ID, or APNS_AUTH_KEY not configured");
    }

    const apnsJWT = await makeApnsJWT(teamId, keyId, authKey);
    // Reuse the existing "mood-update" key so AppDelegate's current handler
    // claims the push, syncs the JWT, and posts moodUpdateReceived without
    // any AppDelegate changes needed.
    const pushPayload = JSON.stringify({ aps: { "content-available": 1 }, "mood-update": 1 });

    // 7. Send push
    try {
      const res = await fetch(`https://${apnsHost}/3/device/${tokenRow.token}`, {
        method: "POST",
        headers: {
          "authorization": `bearer ${apnsJWT}`,
          "apns-topic":     bundleId,
          "apns-push-type": "background",
          "apns-priority":  "5",
          "content-type":   "application/json",
        },
        body: pushPayload,
      });

      if (res.ok) {
        console.log(`APNs accepted invite push for user ${invited_user_id.slice(0, 8)}…`);
        return new Response(JSON.stringify({ sent: 1 }), { headers: JSON_HEADERS });
      } else {
        const resBody = await res.text();
        console.error(`APNs rejected invite push (${res.status}): ${resBody}`);
        // Only delete on 410 (Unregistered) — never on 400 (could be env mismatch)
        if (res.status === 410) {
          await supabase.from("device_tokens").delete().eq("token", tokenRow.token);
          console.log("Removed unregistered APNs token (410)");
        }
        return new Response(JSON.stringify({ sent: 0 }), { headers: JSON_HEADERS });
      }
    } catch (e) {
      console.error("APNs fetch failed:", (e as Error).message);
      return new Response(JSON.stringify({ sent: 0 }), { headers: JSON_HEADERS });
    }

  } catch (err) {
    console.error("send-invite-push error:", (err as Error).message);
    return new Response(JSON.stringify({ error: "Internal server error" }), { status: 500, headers: JSON_HEADERS });
  }
});
