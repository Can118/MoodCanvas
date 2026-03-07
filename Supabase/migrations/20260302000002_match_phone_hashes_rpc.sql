-- ── match_phone_hashes RPC ───────────────────────────────────────────────────
-- The match-contacts edge function previously used PostgREST's .in() filter,
-- which embeds all SHA-256 hashes into the GET query string. With a real device
-- contact list (hundreds of contacts × 64 chars/hash), the URL exceeds
-- PostgREST's ~8 KB limit and returns 400 Bad Request.
--
-- This RPC is invoked via supabase.rpc() which uses POST — the hash array
-- travels in the request body so there is no length cap.

CREATE OR REPLACE FUNCTION public.match_phone_hashes(
  phone_hashes text[],
  exclude_uid  text
)
RETURNS TABLE(id text, name text, phone_hash text)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT id, name, phone_hash
  FROM users
  WHERE phone_hash = ANY(phone_hashes)
    AND id != exclude_uid;
$$;
