-- ============================================================
-- MoodCanvas – Supabase Database Schema (Security Hardened)
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================
-- NOTE: auth.jwt() ->> 'sub' is used instead of auth.uid()
-- because Firebase UIDs are arbitrary strings, not UUIDs.
-- ============================================================

-- ── Tables ──────────────────────────────────────────────────

-- Users: keyed by Firebase UID, phone stored as HMAC hash only
create table if not exists public.users (
  id         text primary key,           -- Firebase UID
  phone_hash text unique not null,       -- HMAC-SHA256(E.164, SERVER_SECRET) — never plaintext
  name       text,
  created_at timestamptz default now()
);

-- Groups
create table if not exists public.groups (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  type       text not null check (type in ('couple', 'bff', 'family')),
  created_by text not null references public.users(id) on delete cascade,
  created_at timestamptz default now()
);

-- Group membership (many-to-many)
create table if not exists public.group_members (
  group_id  uuid references public.groups(id) on delete cascade,
  user_id   text references public.users(id) on delete cascade,
  joined_at timestamptz default now(),
  primary key (group_id, user_id)
);

-- Moods (one per user per group, upserted on change)
create table if not exists public.moods (
  user_id    text references public.users(id) on delete cascade,
  group_id   uuid references public.groups(id) on delete cascade,
  mood       text not null check (mood in ('happy','sad','excited','chill','tired','angry')),
  updated_at timestamptz default now(),
  primary key (user_id, group_id)
);

-- ── Indexes ─────────────────────────────────────────────────

create index if not exists idx_group_members_user  on public.group_members (user_id);
create index if not exists idx_group_members_group on public.group_members (group_id);
create index if not exists idx_moods_group         on public.moods (group_id);
create index if not exists idx_moods_user          on public.moods (user_id);

-- ── Row Level Security ───────────────────────────────────────

alter table public.users         enable row level security;
alter table public.groups        enable row level security;
alter table public.group_members enable row level security;
alter table public.moods         enable row level security;

-- Helper: returns the authenticated user's Firebase UID from the JWT sub claim
create or replace function auth_uid() returns text language sql stable as $$
  select auth.jwt() ->> 'sub'
$$;

-- ── RLS: users ───────────────────────────────────────────────

-- Users can see themselves + other members of shared groups
create policy "users_select" on public.users for select using (
  id = auth_uid()
  or id in (
    select gm2.user_id
    from   public.group_members gm1
    join   public.group_members gm2 on gm1.group_id = gm2.group_id
    where  gm1.user_id = auth_uid()
  )
);

-- Users can update only their own name
create policy "users_update_own" on public.users for update
  using  (id = auth_uid())
  with check (id = auth_uid());

-- Insert / upsert is only performed by the authenticate Edge Function
-- (which uses the service role key and bypasses RLS)

-- ── RLS: groups ──────────────────────────────────────────────

-- Members can see groups they belong to
create policy "groups_select" on public.groups for select using (
  id in (
    select group_id from public.group_members where user_id = auth_uid()
  )
);

-- Authenticated users can create groups (they must be the creator)
create policy "groups_insert" on public.groups for insert
  with check (created_by = auth_uid());

-- Only the group creator can rename the group
create policy "groups_update" on public.groups for update
  using  (created_by = auth_uid())
  with check (created_by = auth_uid());

-- Only the group creator can delete the group
create policy "groups_delete" on public.groups for delete
  using (created_by = auth_uid());

-- ── RLS: group_members ───────────────────────────────────────

-- Members can see the membership list of groups they're in
create policy "group_members_select" on public.group_members for select using (
  group_id in (
    select group_id from public.group_members where user_id = auth_uid()
  )
);

-- Only the group creator can add/remove members
create policy "group_members_insert" on public.group_members for insert
  with check (
    group_id in (
      select id from public.groups where created_by = auth_uid()
    )
  );

create policy "group_members_delete" on public.group_members for delete
  using (
    group_id in (
      select id from public.groups where created_by = auth_uid()
    )
  );

-- ── RLS: moods ───────────────────────────────────────────────

-- Members can see all moods within their groups
create policy "moods_select" on public.moods for select using (
  group_id in (
    select group_id from public.group_members where user_id = auth_uid()
  )
);

-- Users can only insert/update their own mood
create policy "moods_insert" on public.moods for insert
  with check (user_id = auth_uid());

create policy "moods_update" on public.moods for update
  using  (user_id = auth_uid())
  with check (user_id = auth_uid());

-- ── Group Invitations ────────────────────────────────────────

CREATE TABLE public.group_invitations (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id        UUID NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  invited_by      TEXT NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  invited_user_id TEXT NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  status          TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','accepted','rejected')),
  created_at      TIMESTAMPTZ DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now(),
  UNIQUE (group_id, invited_user_id)
);

ALTER TABLE public.group_invitations ENABLE ROW LEVEL SECURITY;

-- Only creator of the group can send invitations
CREATE POLICY "invitations_insert" ON public.group_invitations FOR INSERT
  WITH CHECK (
    invited_by = auth_uid()
    AND group_id IN (SELECT id FROM public.groups WHERE created_by = auth_uid())
  );

-- Inviter and invited user can read
CREATE POLICY "invitations_select" ON public.group_invitations FOR SELECT USING (
  invited_user_id = auth_uid() OR invited_by = auth_uid()
);

-- Invited users can also see groups they've been invited to (needed to fetch group name/type)
CREATE POLICY "groups_select_invited" ON public.groups FOR SELECT USING (
  id IN (
    SELECT group_id FROM public.group_invitations
    WHERE invited_user_id = auth_uid() AND status = 'pending'
  )
);

-- Can see inviters who sent you invitations (needed to show "invited by [name]")
CREATE POLICY "users_select_inviters" ON public.users FOR SELECT USING (
  id IN (
    SELECT invited_by FROM public.group_invitations
    WHERE invited_user_id = auth_uid() AND status = 'pending'
  )
);

-- ── SECURITY DEFINER functions ───────────────────────────────

-- Atomically accept invitation + insert into group_members
CREATE OR REPLACE FUNCTION public.accept_group_invitation(p_invitation_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_group_id uuid;
  v_user_id  text;
BEGIN
  SELECT group_id, invited_user_id INTO v_group_id, v_user_id
  FROM public.group_invitations
  WHERE id = p_invitation_id AND invited_user_id = auth_uid() AND status = 'pending';
  IF NOT FOUND THEN RAISE EXCEPTION 'Invitation not found'; END IF;
  UPDATE public.group_invitations SET status = 'accepted', updated_at = now() WHERE id = p_invitation_id;
  INSERT INTO public.group_members (group_id, user_id) VALUES (v_group_id, v_user_id) ON CONFLICT DO NOTHING;
END;
$$;

-- Reject invitation
CREATE OR REPLACE FUNCTION public.reject_group_invitation(p_invitation_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE public.group_invitations SET status = 'rejected', updated_at = now()
  WHERE id = p_invitation_id AND invited_user_id = auth_uid() AND status = 'pending';
  IF NOT FOUND THEN RAISE EXCEPTION 'Invitation not found'; END IF;
END;
$$;

-- ── Device Tokens (APNs silent push) ────────────────────────

-- One token per user; replaced on each app launch to stay fresh
CREATE TABLE IF NOT EXISTS public.device_tokens (
  user_id    TEXT PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  token      TEXT NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.device_tokens ENABLE ROW LEVEL SECURITY;

-- Users can only manage their own token
CREATE POLICY "device_tokens_select" ON public.device_tokens
  FOR SELECT USING (user_id = auth_uid());

CREATE POLICY "device_tokens_insert" ON public.device_tokens
  FOR INSERT WITH CHECK (user_id = auth_uid());

CREATE POLICY "device_tokens_update" ON public.device_tokens
  FOR UPDATE USING (user_id = auth_uid()) WITH CHECK (user_id = auth_uid());

-- ── Moods updated_at trigger ─────────────────────────────────

-- Automatically refresh moods.updated_at on every UPDATE.
-- The column DEFAULT now() only fires on INSERT; without this trigger
-- the timestamp stays frozen at the original insert time forever.
CREATE OR REPLACE FUNCTION public.set_moods_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER moods_updated_at
BEFORE UPDATE ON public.moods
FOR EACH ROW EXECUTE FUNCTION public.set_moods_updated_at();

-- ── Widget Data ──────────────────────────────────────────────

-- Returns all groups for the current user with members, currentMoods,
-- and moodTimestamps (ISO-8601 strings from moods.updated_at).
CREATE OR REPLACE FUNCTION public.get_widget_data()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER AS $function$
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id',        g.id::text,
      'name',      g.name,
      'type',      g.type,
      'createdBy', g.created_by,
      'members', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'id',          u.id,
          'name',        COALESCE(u.name, 'Unknown'),
          'phoneNumber', ''
        ))
        FROM group_members gm2
        JOIN users u ON u.id = gm2.user_id
        WHERE gm2.group_id = g.id
      ), '[]'::jsonb),
      'currentMoods', COALESCE((
        SELECT jsonb_object_agg(m.user_id, m.mood)
        FROM moods m
        WHERE m.group_id = g.id
      ), '{}'::jsonb),
      'moodTimestamps', COALESCE((
        SELECT jsonb_object_agg(m.user_id, to_jsonb(m.updated_at))
        FROM moods m
        WHERE m.group_id = g.id
      ), '{}'::jsonb)
    )
  ), '[]'::jsonb)
  FROM groups g
  WHERE g.id IN (
    SELECT gm.group_id FROM group_members gm WHERE gm.user_id = auth_uid()
  )
$function$;

-- ── Couple Hearts ────────────────────────────────────────────

-- Cumulative heart count per couple group (hearts never decrement)
CREATE TABLE IF NOT EXISTS public.couple_hearts (
  group_id   UUID PRIMARY KEY REFERENCES public.groups(id) ON DELETE CASCADE,
  count      INTEGER NOT NULL DEFAULT 0
);

ALTER TABLE public.couple_hearts ENABLE ROW LEVEL SECURITY;

-- Members of the couple group can read and write the heart count
CREATE POLICY "couple_hearts_select" ON public.couple_hearts
  FOR SELECT USING (
    group_id IN (SELECT group_id FROM public.group_members WHERE user_id = auth_uid())
  );

-- Increments are handled exclusively through the increment_heart RPC (SECURITY DEFINER)
-- so no direct INSERT/UPDATE policies are needed for clients.

-- Atomically creates the row on first heart, then increments; returns new count.
CREATE OR REPLACE FUNCTION public.increment_heart(p_group_id uuid)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER AS $$
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

-- ── Search ───────────────────────────────────────────────────

-- Search any registered MoodCanvas user by name (case-insensitive, partial match).
-- SECURITY DEFINER so it can bypass the users RLS which only exposes group-mates.
CREATE OR REPLACE FUNCTION public.search_users(query text)
RETURNS TABLE(id text, name text) LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  RETURN QUERY
  SELECT u.id, u.name
  FROM public.users u
  WHERE u.id != auth_uid()
    AND u.name ILIKE '%' || query || '%'
  LIMIT 20;
END;
$$;
