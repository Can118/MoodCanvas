-- ── Fix 1: group_members_delete ──────────────────────────────────────────────
-- Old policy only allowed GROUP CREATORS to delete members, which meant regular
-- members could never leave a group (leaveGroup() silently deleted 0 rows).
-- New policy: a user can delete their OWN membership (leave), AND group creators
-- can still remove any member (kick).
--
-- NOTE: Must use auth_uid() (the project-defined helper) — NOT auth.uid().
-- See Fix 2 comment below for the full explanation.

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


-- ── Fix 2: moods_insert — add group membership check ─────────────────────────
-- Old policy only checked user_id = auth_uid(), allowing any authenticated user
-- to insert mood rows for arbitrary group_ids they are not a member of.
-- New policy also verifies the user is actually in the target group.
--
-- NOTE: Must use auth_uid() (the project-defined helper) — NOT auth.uid().
-- auth.uid() returns `uuid` and tries to cast the JWT sub claim to UUID;
-- Firebase UIDs are not UUIDs so that cast throws a PostgreSQL error for every
-- Firebase user, causing ALL moods upserts to fail silently on the client.

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
