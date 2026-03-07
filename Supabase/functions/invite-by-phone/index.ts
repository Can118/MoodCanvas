/**
 * invite-by-phone — Edge Function
 *
 * Called from iOS when the group creator sends an iMessage to a non-Moodi contact.
 * Hashes the phone number server-side and stores a pending phone_invitations row.
 * When the invitee later downloads the app and registers, authenticate() will
 * automatically claim these rows and convert them into group_invitations.
 *
 * Request body: { group_id: string, phone: string }  (phone must be E.164)
 * Auth: Bearer <supabase-jwt>  (the caller's user JWT)
 */

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { verify } from "https://deno.land/x/djwt@v3.0.2/mod.ts";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const JSON_HEADERS = { ...CORS, "Content-Type": "application/json" };

// In-memory rate limiter — 20 invites per user per minute.
// Prevents rapid phone number enumeration ("is this number on MoodCanvas?").
// For multi-instance production, replace with Upstash Redis.
const rateLimitStore = new Map<string, { count: number; resetAt: number }>();
function isRateLimited(uid: string): boolean {
  const now = Date.now();
  let entry = rateLimitStore.get(uid);
  if (!entry || entry.resetAt < now) {
    entry = { count: 0, resetAt: now + 60_000 };
    rateLimitStore.set(uid, entry);
  }
  if (entry.count >= 20) return true;
  entry.count++;
  return false;
}

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

/** Verify the JWT signature and return the sub claim. Throws if invalid or expired. */
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

serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  try {
    // 1. Extract and cryptographically verify JWT
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
      return new Response(JSON.stringify({ error: "Invalid token" }), { status: 401, headers: JSON_HEADERS });
    }

    // 2. Rate limit
    if (isRateLimited(callerId)) {
      return new Response(
        JSON.stringify({ error: "Rate limit exceeded. Try again in a minute." }),
        { status: 429, headers: { ...JSON_HEADERS, "Retry-After": "60" } },
      );
    }

    // 3. Parse and validate body
    let body: { group_id?: string; phone?: string };
    try { body = await req.json(); } catch {
      return new Response(JSON.stringify({ error: "Invalid JSON" }), { status: 400, headers: JSON_HEADERS });
    }
    const { group_id, phone } = body;
    if (!group_id || !phone) {
      return new Response(JSON.stringify({ error: "Missing group_id or phone" }), { status: 400, headers: JSON_HEADERS });
    }
    if (!/^\+[1-9]\d{6,14}$/.test(phone)) {
      return new Response(JSON.stringify({ error: "Invalid phone format (must be E.164)" }), { status: 400, headers: JSON_HEADERS });
    }

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { persistSession: false } },
    );

    // 3. Verify caller is a member of the group (prevents spoofing)
    const { data: membership } = await admin
      .from("group_members")
      .select("user_id")
      .eq("group_id", group_id)
      .eq("user_id", callerId)
      .maybeSingle();

    if (!membership) {
      return new Response(JSON.stringify({ error: "Not a member of this group" }), { status: 403, headers: JSON_HEADERS });
    }

    // 4. Hash phone server-side (same secret used in authenticate)
    const hashSecret = Deno.env.get("PHONE_HASH_SECRET");
    if (!hashSecret) throw new Error("PHONE_HASH_SECRET not configured");
    const phoneHash = await hmacSha256(phone, hashSecret);

    // 5. Check if this phone is already a registered user — if so, send a
    //    direct group_invitation instead of a deferred phone_invitation.
    const { data: existingUser } = await admin
      .from("users")
      .select("id")
      .eq("phone_hash", phoneHash)
      .maybeSingle();

    if (existingUser) {
      // User already exists: create a regular invitation
      const { error: invErr } = await admin
        .from("group_invitations")
        .upsert(
          { group_id, invited_by: callerId, invited_user_id: existingUser.id },
          { onConflict: "group_id,invited_user_id" },
        );
      if (invErr) {
        console.error("group_invitations insert error:", invErr.code);
        throw new Error("Database error");
      }
      return new Response(JSON.stringify({ ok: true, mode: "direct" }), { headers: JSON_HEADERS });
    }

    // 6. User doesn't exist yet: store deferred phone invitation
    const { error: insertErr } = await admin
      .from("phone_invitations")
      .upsert(
        { group_id, invited_by: callerId, invited_phone_hash: phoneHash, status: "pending" },
        { onConflict: "group_id,invited_phone_hash" },
      );
    if (insertErr) {
      console.error("phone_invitations insert error:", insertErr.code);
      throw new Error("Database error");
    }

    return new Response(JSON.stringify({ ok: true, mode: "deferred" }), { headers: JSON_HEADERS });
  } catch (err) {
    console.error("invite-by-phone error:", (err as Error).message);
    return new Response(JSON.stringify({ error: "Internal server error" }), { status: 500, headers: JSON_HEADERS });
  }
});
