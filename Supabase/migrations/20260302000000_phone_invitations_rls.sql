-- Enable RLS on phone_invitations.
--
-- This table stores invited_phone_hash values for unregistered users.
-- Without RLS, any authenticated user can read all rows via the PostgREST
-- REST API (/rest/v1/phone_invitations), exposing phone hashes of every
-- person who was ever invited but hasn't registered yet.
--
-- All legitimate reads and writes go through Edge Functions using the
-- service role key, which bypasses RLS automatically. No explicit policies
-- are needed — enabling RLS with no policies blocks all direct client access
-- while leaving service-role operations untouched.

ALTER TABLE public.phone_invitations ENABLE ROW LEVEL SECURITY;
