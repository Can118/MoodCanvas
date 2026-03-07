/**
 * authenticate — Edge Function
 *
 * Accepts a Firebase ID token, verifies it with Google, hashes the phone
 * number server-side (HMAC-SHA256), upserts the user, then returns a
 * short-lived Supabase JWT so the client can make authenticated requests.
 *
 * Secrets required (set via `supabase secrets set`):
 *   FIREBASE_WEB_API_KEY   — Firebase Console → Project Settings → General → Web API Key
 *   PHONE_HASH_SECRET      — openssl rand -hex 32
 *   SUPABASE_JWT_SECRET    — auto-provided by Supabase
 *   SUPABASE_SERVICE_ROLE_KEY — auto-provided by Supabase
 */

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { create } from "https://deno.land/x/djwt@v3.0.2/mod.ts";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const JSON_HEADERS = { ...CORS, "Content-Type": "application/json" };

// ── Helpers ──────────────────────────────────────────────────────────────────

async function hmacSha256(message: string, secret: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message));
  return Array.from(new Uint8Array(sig)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function makeSupabaseJWT(uid: string, jwtSecret: string): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(jwtSecret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return create(
    { alg: "HS256", typ: "JWT" },
    {
      sub: uid,
      role: "authenticated",
      iss: "supabase",
      iat: now,
      exp: now + 604800, // 7 days — widget extension cannot refresh its own JWT, so a long TTL
      // keeps the AppGroup copy valid between app opens (7 days covers typical usage).
    },
    key,
  );
}

// ── Handler ──────────────────────────────────────────────────────────────────

serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  try {
    // 1. Parse body
    let body: { firebaseIdToken?: string };
    try {
      body = await req.json();
    } catch {
      return new Response(JSON.stringify({ error: "Invalid JSON body" }), { status: 400, headers: JSON_HEADERS });
    }

    const { firebaseIdToken } = body;
    if (!firebaseIdToken || typeof firebaseIdToken !== "string") {
      return new Response(JSON.stringify({ error: "Missing firebaseIdToken" }), { status: 400, headers: JSON_HEADERS });
    }

    // 2. Verify Firebase ID token via Google's secure token endpoint
    const firebaseApiKey = Deno.env.get("FIREBASE_WEB_API_KEY");
    if (!firebaseApiKey) throw new Error("FIREBASE_WEB_API_KEY not configured");

    const verifyResp = await fetch(
      `https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=${firebaseApiKey}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ idToken: firebaseIdToken }),
        signal: AbortSignal.timeout(8000),
      },
    );

    if (!verifyResp.ok) {
      // Do not expose Google's error details
      console.error("Firebase verify failed:", verifyResp.status);
      return new Response(JSON.stringify({ error: "Invalid or expired token" }), { status: 401, headers: JSON_HEADERS });
    }

    const { users } = await verifyResp.json();
    if (!Array.isArray(users) || users.length === 0) {
      return new Response(JSON.stringify({ error: "Invalid or expired token" }), { status: 401, headers: JSON_HEADERS });
    }

    const firebaseUser = users[0];
    const firebaseUID: string = firebaseUser.localId;
    const rawPhone: string | undefined = firebaseUser.phoneNumber;

    if (!firebaseUID || !rawPhone) {
      return new Response(JSON.stringify({ error: "Incomplete Firebase account" }), { status: 400, headers: JSON_HEADERS });
    }

    // 3. Validate phone is E.164
    if (!/^\+[1-9]\d{6,14}$/.test(rawPhone)) {
      return new Response(JSON.stringify({ error: "Invalid phone number format" }), { status: 400, headers: JSON_HEADERS });
    }

    // 4. Hash phone with HMAC-SHA256 (server secret — never stored plaintext)
    const hashSecret = Deno.env.get("PHONE_HASH_SECRET");
    if (!hashSecret) throw new Error("PHONE_HASH_SECRET not configured");
    const phoneHash = await hmacSha256(rawPhone, hashSecret);

    // 5. Upsert user using service role (bypasses RLS — safe here)
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { persistSession: false } },
    );

    // Remove any stale row that has this phone_hash but a different Firebase UID.
    // This occurs when a device is erased and Firebase assigns a new UID for the
    // same phone number. CASCADE DELETE cleans up orphaned group data automatically.
    await supabase
      .from("users")
      .delete()
      .eq("phone_hash", phoneHash)
      .neq("id", firebaseUID);

    const { error: upsertError } = await supabase
      .from("users")
      .upsert({ id: firebaseUID, phone_hash: phoneHash }, { onConflict: "id" });

    if (upsertError) {
      console.error("Upsert failed:", upsertError.code); // log code only, not message
      throw new Error("Database error");
    }

    // 6. Claim any pending phone invitations for this phone number.
    //    These were created when an existing user sent an iMessage invite to this
    //    phone before it was registered. Convert each one into a group_invitation
    //    now that we know the Firebase UID, then mark them claimed so they never
    //    surface again (idempotent: upsert on group_id,invited_user_id conflict).
    const { data: pendingPhoneInvites } = await supabase
      .from("phone_invitations")
      .select("id, group_id, invited_by")
      .eq("invited_phone_hash", phoneHash)
      .eq("status", "pending");

    if (pendingPhoneInvites && pendingPhoneInvites.length > 0) {
      for (const invite of pendingPhoneInvites) {
        await supabase
          .from("group_invitations")
          .upsert(
            { group_id: invite.group_id, invited_by: invite.invited_by, invited_user_id: firebaseUID },
            { onConflict: "group_id,invited_user_id" },
          );
        await supabase
          .from("phone_invitations")
          .update({ status: "claimed" })
          .eq("id", invite.id);
      }
      console.log(`[authenticate] Claimed ${pendingPhoneInvites.length} phone invitation(s) for new user ${firebaseUID.slice(0, 8)}…`);
    }

    // 7. Create Supabase JWT signed with JWT_SECRET (the project's JWT secret)
    const jwtSecret = Deno.env.get("JWT_SECRET");
    if (!jwtSecret) throw new Error("JWT_SECRET not configured");

    const jwt = await makeSupabaseJWT(firebaseUID, jwtSecret);

    return new Response(JSON.stringify({ jwt, expiresIn: 604800 }), { headers: JSON_HEADERS });
  } catch (err) {
    // Never expose internal error details
    console.error("authenticate error:", (err as Error).message);
    return new Response(JSON.stringify({ error: "Internal server error" }), { status: 500, headers: JSON_HEADERS });
  }
});
