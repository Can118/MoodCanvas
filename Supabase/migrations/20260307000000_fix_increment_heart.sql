-- ── Fix increment_heart: ensure function + permissions exist in production ──────
--
-- Root cause: couple_hearts table is empty despite client calls because either
-- (a) increment_heart was never deployed to production, or
-- (b) GRANT EXECUTE was applied before/without the function body being present.
--
-- This migration is idempotent: safe to run even if partially applied before.

-- 1. Ensure couple_hearts table exists (in case schema.sql wasn't fully run)
CREATE TABLE IF NOT EXISTS public.couple_hearts (
  group_id   UUID PRIMARY KEY REFERENCES public.groups(id) ON DELETE CASCADE,
  count      INTEGER NOT NULL DEFAULT 0
);

ALTER TABLE public.couple_hearts ENABLE ROW LEVEL SECURITY;

-- 2. Re-create RLS policy with correct auth_uid() helper (not auth.uid())
DROP POLICY IF EXISTS "couple_hearts_select" ON public.couple_hearts;
DROP POLICY IF EXISTS "hearts_select"        ON public.couple_hearts;  -- old broken name

CREATE POLICY "couple_hearts_select" ON public.couple_hearts
  FOR SELECT USING (
    group_id IN (
      SELECT group_id FROM public.group_members WHERE user_id = auth_uid()
    )
  );

-- 3. Re-create increment_heart with explicit search_path (security best practice)
--    SECURITY DEFINER means the function runs as the DB owner and bypasses RLS,
--    so no INSERT/UPDATE policy on couple_hearts is needed for clients.
CREATE OR REPLACE FUNCTION public.increment_heart(p_group_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count integer;
BEGIN
  INSERT INTO public.couple_hearts (group_id, count)
  VALUES (p_group_id, 1)
  ON CONFLICT (group_id) DO UPDATE
    SET count = couple_hearts.count + 1
  RETURNING count INTO v_count;
  RETURN v_count;
END;
$$;

-- 4. Grant EXECUTE to authenticated users
GRANT EXECUTE ON FUNCTION public.increment_heart(uuid) TO authenticated;

-- ── Diagnostic: run these SELECTs after applying to verify ───────────────────
-- SELECT proname, prosrc FROM pg_proc WHERE proname = 'increment_heart';
-- SELECT grantee, privilege_type FROM information_schema.role_routine_grants WHERE routine_name = 'increment_heart';
-- SELECT * FROM public.couple_hearts;
