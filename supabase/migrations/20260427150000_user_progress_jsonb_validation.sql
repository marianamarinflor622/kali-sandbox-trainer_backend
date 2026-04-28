-- user_progress: tabla base (proyectos que solo aplican migraciones del backend) + validación JSONB y checks.

CREATE TABLE IF NOT EXISTS public.user_progress (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  commands_used jsonb NOT NULL DEFAULT '[]'::jsonb,
  challenges_completed jsonb NOT NULL DEFAULT '[]'::jsonb,
  streak_days integer NOT NULL DEFAULT 0,
  last_activity date,
  xp integer NOT NULL DEFAULT 0,
  created_at timestamptz DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS user_progress_user_id_key ON public.user_progress (user_id);

ALTER TABLE public.user_progress ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "own" ON public.user_progress;
DROP POLICY IF EXISTS "user_progress_select_own" ON public.user_progress;
DROP POLICY IF EXISTS "user_progress_insert_own" ON public.user_progress;
DROP POLICY IF EXISTS "user_progress_update_own" ON public.user_progress;
DROP POLICY IF EXISTS "user_progress_delete_own" ON public.user_progress;

CREATE POLICY "user_progress_select_own"
  ON public.user_progress
  FOR SELECT
  USING (user_id = auth.uid());

CREATE POLICY "user_progress_insert_own"
  ON public.user_progress
  FOR INSERT
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "user_progress_update_own"
  ON public.user_progress
  FOR UPDATE
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "user_progress_delete_own"
  ON public.user_progress
  FOR DELETE
  USING (user_id = auth.uid());

ALTER TABLE public.user_progress DROP CONSTRAINT IF EXISTS commands_used_is_array;
ALTER TABLE public.user_progress
  ADD CONSTRAINT commands_used_is_array
  CHECK (jsonb_typeof(commands_used) = 'array');

ALTER TABLE public.user_progress DROP CONSTRAINT IF EXISTS challenges_completed_is_array;
ALTER TABLE public.user_progress
  ADD CONSTRAINT challenges_completed_is_array
  CHECK (jsonb_typeof(challenges_completed) = 'array');

ALTER TABLE public.user_progress DROP CONSTRAINT IF EXISTS xp_non_negative;
ALTER TABLE public.user_progress
  ADD CONSTRAINT xp_non_negative
  CHECK (xp >= 0);

ALTER TABLE public.user_progress DROP CONSTRAINT IF EXISTS streak_non_negative;
ALTER TABLE public.user_progress
  ADD CONSTRAINT streak_non_negative
  CHECK (streak_days >= 0);

ALTER TABLE public.user_progress DROP CONSTRAINT IF EXISTS last_activity_not_future;
ALTER TABLE public.user_progress
  ADD CONSTRAINT last_activity_not_future
  CHECK (last_activity IS NULL OR last_activity <= CURRENT_DATE);
