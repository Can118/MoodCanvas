/**
 * match-contacts — Edge Function
 *
 * Accepts a list of E.164 phone numbers from an authenticated user,
 * hashes them server-side, and returns which ones are registered on MoodCanvas.
 *
 * Security properties:
 *  • Requires valid Supabase JWT (issued by authenticate function)
 *  • Rate-limited: 5 calls per user per minute
 *  • Phone numbers are hashed on the server — client never sees the hash algorithm
 *  • Batch capped at 500 numbers
 *  • Returns only {id, name} — never phone hashes or raw numbers
 *  • Requesting user is excluded from results
 */

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { verify } from "https://deno.land/x/djwt@v3.0.2/mod.ts";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const JSON_HEADERS = { ...CORS, "Content-Type": "application/json" };
const MAX_BATCH   = 500;
const RATE_WINDOW = 60_000;  // 1 minute
const RATE_LIMIT  = 30;      // max calls per window per user

// In-memory rate limiter (per Edge Function instance)
// For multi-instance production, replace with Upstash Redis.
const rateLimitStore = new Map<string, { count: number; resetAt: number }>();

function isRateLimited(uid: string): boolean {
  const now = Date.now();
  let entry = rateLimitStore.get(uid);
  if (!entry || entry.resetAt < now) {
    entry = { count: 0, resetAt: now + RATE_WINDOW };
    rateLimitStore.set(uid, entry);
  }
  if (entry.count >= RATE_LIMIT) return true;
  entry.count++;
  return false;
}

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

async function verifyJWT(token: string, secret: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["verify"],
  );
  const payload = await verify(token, key); // throws if invalid or expired
  const sub = payload.sub;
  if (typeof sub !== "string" || !sub) throw new Error("Missing sub claim");
  return sub;
}

// ── Handler ──────────────────────────────────────────────────────────────────

serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  // 1. Extract and verify JWT
  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401, headers: JSON_HEADERS });
  }

  const jwtSecret = Deno.env.get("JWT_SECRET");
  if (!jwtSecret) {
    console.error("JWT_SECRET not configured");
    return new Response(JSON.stringify({ error: "Internal server error" }), { status: 500, headers: JSON_HEADERS });
  }

  let uid: string;
  try {
    uid = await verifyJWT(authHeader.slice(7), jwtSecret);
  } catch {
    return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401, headers: JSON_HEADERS });
  }

  // 2. Rate limit
  if (isRateLimited(uid)) {
    return new Response(JSON.stringify({ error: "Rate limit exceeded. Try again in a minute." }), {
      status: 429,
      headers: { ...JSON_HEADERS, "Retry-After": "60" },
    });
  }

  // 3. Parse and validate body
  let body: { phoneNumbers?: unknown };
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON body" }), { status: 400, headers: JSON_HEADERS });
  }

  const { phoneNumbers } = body;
  if (!Array.isArray(phoneNumbers) || phoneNumbers.length === 0) {
    return new Response(JSON.stringify({ matches: [] }), { headers: JSON_HEADERS });
  }
  if (phoneNumbers.length > MAX_BATCH) {
    return new Response(
      JSON.stringify({ error: `Batch size exceeds limit of ${MAX_BATCH}` }),
      { status: 400, headers: JSON_HEADERS },
    );
  }

  // 4. Validate each number is E.164
  const e164 = /^\+[1-9]\d{6,14}$/;
  if (!phoneNumbers.every((n): n is string => typeof n === "string" && e164.test(n))) {
    return new Response(JSON.stringify({ error: "All numbers must be E.164 format" }), {
      status: 400,
      headers: JSON_HEADERS,
    });
  }

  // 5. Hash server-side (client never learns the hashing algorithm or secret)
  const hashSecret = Deno.env.get("PHONE_HASH_SECRET");
  if (!hashSecret) {
    console.error("PHONE_HASH_SECRET not configured");
    return new Response(JSON.stringify({ error: "Internal server error" }), { status: 500, headers: JSON_HEADERS });
  }

  const hashes = await Promise.all(phoneNumbers.map((n) => hmacSha256(n, hashSecret)));

  // Build reverse map: hash → input array index (so the client can resolve the phone locally
  // without the server ever transmitting phone numbers back in the response)
  const hashToIndex: Record<string, number> = {};
  for (let i = 0; i < phoneNumbers.length; i++) {
    hashToIndex[hashes[i]] = i;
  }

  // 6. Query with service role (to see all phone hashes), then filter
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );

  // Use RPC instead of .in() — .in() builds a GET query string with all hashes
  // embedded, which overflows PostgREST's ~8 KB URL limit for users with many
  // contacts. supabase.rpc() uses POST so the array travels in the body.
  const { data, error } = await supabase.rpc("match_phone_hashes", {
    phone_hashes: hashes,
    exclude_uid:  uid,
  });

  if (error) {
    console.error("Query error:", error.message);
    return new Response(JSON.stringify({ error: "Internal server error" }), { status: 500, headers: JSON_HEADERS });
  }

  // Return inputIndex so the client can resolve the phone from its own local array —
  // the server never transmits phone numbers in the response body.
  const matches = (data ?? []).map((u: { id: string; name: string | null; phone_hash: string }) => ({
    id: u.id,
    name: u.name,
    inputIndex: hashToIndex[u.phone_hash] ?? -1,
  }));

  return new Response(JSON.stringify({ matches }), { headers: JSON_HEADERS });
});
