-- ── Fix auth.uid() → auth_uid() in two RLS policies ─────────────────────────
--
-- Migration 20260302000001_fix_rls_policies.sql introduced a critical bug:
-- it used `(auth.uid())::text` in the moods_insert and group_members_delete
-- policies.  auth.uid() is Supabase's built-in function whose return type is
-- `uuid`; it internally tries to cast the JWT `sub` claim to a PostgreSQL UUID.
-- Firebase UIDs are arbitrary alphanumeric strings — they are NOT UUIDs.
-- The cast throws `invalid input syntax for type uuid` for every Firebase user,
-- which means:
--   • ALL moods upserts fail (PostgreSQL evaluates the INSERT WITH CHECK even
--     when an ON CONFLICT DO UPDATE is triggered, per SQL standard).
--   • leaveGroup() / kick silently deletes 0 rows.
--
-- The fix: replace (auth.uid())::text with auth_uid(), the project-specific
-- helper (defined in schema.sql) that reads auth.jwt()->>'sub' as TEXT.
-- This is consistent with every other RLS policy in the schema.

-- ── moods_insert ─────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS moods_insert ON public.moods;

CREATE POLICY moods_insert ON public.moods
  FOR INSERT
  WITH CHECK (
    (user_id = auth_uid())
    AND (group_id IN (
      SELECT group_id FROM public.group_members
      WHERE user_id = auth_uid()
    ))
  );

-- ── group_members_delete ─────────────────────────────────────────────────────
DROP POLICY IF EXISTS group_members_delete ON public.group_members;

CREATE POLICY group_members_delete ON public.group_members
  FOR DELETE
  USING (
    -- Any member can remove themselves (leave group)
    (user_id = auth_uid())
    -- Group creator can remove any member (kick)
    OR (group_id IN (
      SELECT id FROM public.groups WHERE created_by = auth_uid()
    ))
  );
