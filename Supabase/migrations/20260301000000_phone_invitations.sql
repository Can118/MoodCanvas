-- ── Phone-based deferred invitations ────────────────────────────────────────
-- Stores a pending invite keyed by the invitee's phone hash.
-- When the invitee registers, authenticate() converts these into
-- real group_invitations rows and marks them 'claimed'.
-- This allows non-Moodi users to receive invites before downloading the app.

CREATE TABLE IF NOT EXISTS public.phone_invitations (
  id                 UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id           UUID        NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  invited_by         TEXT        NOT NULL REFERENCES public.users(id)  ON DELETE CASCADE,
  invited_phone_hash TEXT        NOT NULL,
  status             TEXT        NOT NULL DEFAULT 'pending'
                                 CHECK (status IN ('pending', 'claimed')),
  created_at         TIMESTAMPTZ DEFAULT now(),
  UNIQUE (group_id, invited_phone_hash)
);

-- No RLS needed — all reads/writes go through service-role Edge Functions only.
-- Row-level clients never touch this table directly.
