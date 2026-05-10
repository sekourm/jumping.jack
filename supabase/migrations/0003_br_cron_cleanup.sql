-- Battle Royale — scheduled cleanup of stale rooms.
--
-- Activates the `pg_cron` extension (Supabase ships it pre-installed but
-- not enabled), then registers a job that calls br_cleanup_stale_rooms()
-- once a minute. The function itself drops:
--   • waiting rooms older than 5 minutes
--   • ended rooms older than 1 hour
-- so the database doesn't accumulate match history forever.
--
-- Idempotent: re-running the migration unschedules any previous instance
-- of the job before re-creating it. Run this with the **Run** button in
-- the Supabase SQL Editor — not "Explain", which only accepts a single
-- statement.

CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA extensions;

DO $$
DECLARE
  v_job_id BIGINT;
BEGIN
  SELECT jobid INTO v_job_id
  FROM cron.job
  WHERE jobname = 'br_cleanup_stale_rooms_minutely';
  IF v_job_id IS NOT NULL THEN
    PERFORM cron.unschedule(v_job_id);
  END IF;

  PERFORM cron.schedule(
    'br_cleanup_stale_rooms_minutely',
    '* * * * *',
    'SELECT public.br_cleanup_stale_rooms();'
  );
END$$;
