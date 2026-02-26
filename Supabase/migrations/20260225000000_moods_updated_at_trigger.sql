-- Auto-update moods.updated_at on every UPDATE.
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
