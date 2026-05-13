-- ============================================================
-- 0001_init  —  Jumping JACK Battle Royale backend, consolidated.
--
-- Single source of truth for the current Supabase schema. Replaces
-- the previous 0001..0012 migration chain after we settled on:
--   • Device-derived player_id (no recovery_code).
--   • Server-side rename validation (blacklist + uniqueness) via
--     the dedicated `set_player_name` RPC.
--   • Stats upsert that doesn't overwrite the chosen name and
--     auto-suffixes the very first INSERT to dedup cross-device
--     `JACK_xxxx` collisions.
--   • `get_my_profile(player_id)` is the boot-time hydration RPC.
--
-- The whole file is idempotent: CREATE TABLE IF NOT EXISTS, ALTER
-- ... ADD COLUMN IF NOT EXISTS, DROP POLICY IF EXISTS before each
-- CREATE POLICY, etc. Safe to re-run against a database already
-- in this end state or to fresh-deploy against an empty project.
-- ============================================================

-- =====================================================================
-- 1. TABLES
-- =====================================================================

-- Active and past matches. Lifecycle: waiting → playing → ended.
CREATE TABLE IF NOT EXISTS br_rooms (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  status            TEXT NOT NULL DEFAULT 'waiting'
                      CHECK (status IN ('waiting', 'playing', 'ended')),
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  started_at        TIMESTAMPTZ,
  ended_at          TIMESTAMPTZ,
  winner_player_id  TEXT
);

CREATE INDEX IF NOT EXISTS idx_br_rooms_status_created
  ON br_rooms (status, created_at DESC);

-- Up to 5 slots per room (humans + bots). `last_seen` is the
-- heartbeat clients bump every 5 s; it gates ghost-player sweeps in
-- the matchmaker and the alive-count check in br_end_match.
CREATE TABLE IF NOT EXISTS br_room_players (
  room_id     UUID NOT NULL REFERENCES br_rooms(id) ON DELETE CASCADE,
  slot_index  INT NOT NULL CHECK (slot_index BETWEEN 0 AND 4),
  player_id   TEXT NOT NULL,
  name        TEXT NOT NULL,
  is_bot      BOOLEAN NOT NULL DEFAULT FALSE,
  joined_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_seen   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (room_id, slot_index)
);

CREATE INDEX IF NOT EXISTS idx_br_room_players_last_seen
  ON br_room_players (last_seen);

-- Per-device persistent profile. Keyed by the IDFV-derived player_id
-- generated client-side. `name` is mutated only by `set_player_name`;
-- `best_score` grows monotonically via `upsert_br_profile`; `br_wins`
-- is server-authoritative (bumped only inside `br_end_match`).
CREATE TABLE IF NOT EXISTS br_profiles (
  player_id   TEXT PRIMARY KEY,
  name        TEXT NOT NULL,
  best_score  INT NOT NULL DEFAULT 0,
  br_wins     INT NOT NULL DEFAULT 0,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Server-side death tracker. `br_end_match` requires every non-winner
-- slot to either have a row here or (for humans) a stale heartbeat
-- before it accepts a winner — closes the "claim victory from the
-- browser console" exploit.
CREATE TABLE IF NOT EXISTS br_player_deaths (
  room_id             UUID NOT NULL REFERENCES br_rooms(id) ON DELETE CASCADE,
  player_id           TEXT NOT NULL,
  died_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  killer_player_id    TEXT,
  reporter_player_id  TEXT NOT NULL,
  PRIMARY KEY (room_id, player_id)
);

CREATE INDEX IF NOT EXISTS idx_br_player_deaths_room
  ON br_player_deaths (room_id);

-- Substring blacklist consulted by `set_player_name`. The table is
-- created here but seeded from the standalone `seed_blacklist.sql`
-- script — keeps schema and content in separate concerns so a
-- vocabulary update doesn't dirty the schema migration.
CREATE TABLE IF NOT EXISTS br_name_blacklist (
  pattern TEXT PRIMARY KEY
);

-- =====================================================================
-- 2. ROW-LEVEL SECURITY
--    Anon has SELECT on the four "match-state" tables (the client
--    reads them directly for live UI) and NO writes anywhere. Every
--    mutation is funnelled through the SECURITY DEFINER RPCs below.
--    br_profiles + br_name_blacklist have no policy at all — even
--    reads go through dedicated RPCs.
-- =====================================================================

ALTER TABLE br_rooms          ENABLE ROW LEVEL SECURITY;
ALTER TABLE br_room_players   ENABLE ROW LEVEL SECURITY;
ALTER TABLE br_profiles       ENABLE ROW LEVEL SECURITY;
ALTER TABLE br_player_deaths  ENABLE ROW LEVEL SECURITY;
ALTER TABLE br_name_blacklist ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_select_rooms"   ON br_rooms;
DROP POLICY IF EXISTS "anon_all_rooms"      ON br_rooms;
CREATE POLICY "anon_select_rooms" ON br_rooms
  FOR SELECT USING (true);

DROP POLICY IF EXISTS "anon_select_players" ON br_room_players;
DROP POLICY IF EXISTS "anon_all_players"    ON br_room_players;
CREATE POLICY "anon_select_players" ON br_room_players
  FOR SELECT USING (true);

DROP POLICY IF EXISTS "anon_select_deaths"  ON br_player_deaths;
CREATE POLICY "anon_select_deaths" ON br_player_deaths
  FOR SELECT USING (true);

-- br_profiles and br_name_blacklist: intentionally NO policy.

-- =====================================================================
-- 3. REALTIME
--    Wrapped so re-runs don't fail when the table is already in the
--    publication.
-- =====================================================================

DO $$
BEGIN
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE br_rooms;
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE br_room_players;
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;
END$$;

-- =====================================================================
-- 4. RPCs — matchmaking & lifecycle
-- =====================================================================

-- Atomic "find a waiting room I fit in, otherwise create one, then
-- claim the lowest free slot". Sweeps ghost players (no heartbeat
-- in 20 s) and empty waiting rooms before the lookup so abandoned
-- lobbies don't trap fresh joiners.
CREATE OR REPLACE FUNCTION join_or_create_br_room(
  p_player_id TEXT,
  p_name      TEXT
) RETURNS TABLE(room_id UUID, slot_index INT)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_room_id          UUID;
  v_slot             INT;
  v_stale_threshold  TIMESTAMPTZ := NOW() - INTERVAL '20 seconds';
BEGIN
  DELETE FROM br_room_players p
  USING br_rooms r
  WHERE p.room_id = r.id
    AND r.status = 'waiting'
    AND p.is_bot = FALSE
    AND p.last_seen < v_stale_threshold;

  DELETE FROM br_rooms r
  WHERE r.status = 'waiting'
    AND NOT EXISTS (
      SELECT 1 FROM br_room_players p WHERE p.room_id = r.id
    );

  -- Prefer fullest non-empty room (faster fill, players land in the
  -- same lobby instead of spawning parallel rooms). Tie-break by
  -- oldest to drain the queue fairly.
  SELECT r.id INTO v_room_id
  FROM br_rooms r
  WHERE r.id IN (
    SELECT r2.id
    FROM br_rooms r2
    LEFT JOIN br_room_players p ON p.room_id = r2.id
    WHERE r2.status = 'waiting'
      AND r2.created_at > NOW() - INTERVAL '5 minutes'
    GROUP BY r2.id, r2.created_at
    HAVING COUNT(p.player_id) BETWEEN 1 AND 4
    ORDER BY COUNT(p.player_id) DESC, r2.created_at ASC
    LIMIT 1
  )
  FOR UPDATE;

  IF v_room_id IS NULL THEN
    INSERT INTO br_rooms DEFAULT VALUES RETURNING id INTO v_room_id;
  END IF;

  SELECT MIN(s) INTO v_slot
  FROM generate_series(0, 4) s
  WHERE s NOT IN (
    SELECT p.slot_index FROM br_room_players p WHERE p.room_id = v_room_id
  );

  IF v_slot IS NULL THEN
    RAISE EXCEPTION 'br_room_full' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO br_room_players
    (room_id, slot_index, player_id, name, last_seen)
  VALUES
    (v_room_id, v_slot, p_player_id, p_name, NOW());

  RETURN QUERY SELECT v_room_id, v_slot;
END;
$$;

GRANT EXECUTE ON FUNCTION join_or_create_br_room(TEXT, TEXT)
  TO anon, authenticated;

-- Heartbeat from the room lifetime. Called every 5 s by clients
-- still in the lobby / match. Cheap.
CREATE OR REPLACE FUNCTION br_heartbeat(
  p_room_id   UUID,
  p_player_id TEXT
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE br_room_players
  SET last_seen = NOW()
  WHERE room_id = p_room_id AND player_id = p_player_id;
END;
$$;

GRANT EXECUTE ON FUNCTION br_heartbeat(UUID, TEXT)
  TO anon, authenticated;

-- "Start the match" — flips status to playing AND seeds the bot rows
-- atomically (the anon role can't INSERT into br_room_players, so
-- bot seeding has to go through a SECURITY DEFINER path).
CREATE OR REPLACE FUNCTION br_start_match(
  p_room_id        UUID,
  p_player_id      TEXT,
  p_bot_slots      INT[]  DEFAULT ARRAY[]::INT[],
  p_bot_player_ids TEXT[] DEFAULT ARRAY[]::TEXT[],
  p_bot_names      TEXT[] DEFAULT ARRAY[]::TEXT[]
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  i INT;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM br_room_players p
    WHERE p.room_id = p_room_id
      AND p.player_id = p_player_id
      AND p.is_bot = FALSE
  ) THEN
    RAISE EXCEPTION 'not_in_room' USING ERRCODE = 'P0001';
  END IF;

  IF array_length(p_bot_slots, 1) IS NOT NULL THEN
    FOR i IN 1 .. array_length(p_bot_slots, 1) LOOP
      INSERT INTO br_room_players
        (room_id, slot_index, player_id, name, is_bot)
      VALUES
        (p_room_id, p_bot_slots[i], p_bot_player_ids[i],
         p_bot_names[i], TRUE)
      ON CONFLICT (room_id, slot_index) DO NOTHING;
    END LOOP;
  END IF;

  UPDATE br_rooms
  SET status = 'playing',
      started_at = NOW()
  WHERE id = p_room_id
    AND status = 'waiting';
END;
$$;

GRANT EXECUTE ON FUNCTION br_start_match(UUID, TEXT, INT[], TEXT[], TEXT[])
  TO anon, authenticated;

-- Idempotent death record. Humans can only flag themselves dead
-- (otherwise a cheater could "kill everyone else" to claim the
-- room); bots can be flagged by any human in the room because the
-- room leader is client-only and a network blip on their device
-- would otherwise deadlock the alive-count check.
CREATE OR REPLACE FUNCTION br_report_death(
  p_room_id            UUID,
  p_dead_player_id     TEXT,
  p_reporter_player_id TEXT,
  p_killer_player_id   TEXT DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_is_bot BOOLEAN;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM br_room_players p
    WHERE p.room_id = p_room_id
      AND p.player_id = p_reporter_player_id
      AND p.is_bot = FALSE
  ) THEN
    RAISE EXCEPTION 'reporter_not_in_room' USING ERRCODE = 'P0001';
  END IF;

  SELECT p.is_bot INTO v_is_bot
  FROM br_room_players p
  WHERE p.room_id = p_room_id
    AND p.player_id = p_dead_player_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'victim_not_in_room' USING ERRCODE = 'P0001';
  END IF;

  IF v_is_bot = FALSE
     AND p_reporter_player_id <> p_dead_player_id THEN
    RAISE EXCEPTION 'cannot_report_other_human' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO br_player_deaths
    (room_id, player_id, killer_player_id, reporter_player_id)
  VALUES
    (p_room_id, p_dead_player_id, p_killer_player_id, p_reporter_player_id)
  ON CONFLICT (room_id, player_id) DO NOTHING;
END;
$$;

GRANT EXECUTE ON FUNCTION br_report_death(UUID, TEXT, TEXT, TEXT)
  TO anon, authenticated;

-- "End the match" — flips status to ended and bumps the winner's
-- br_wins, both inside the same transaction. Rejects:
--   • caller not in the room,
--   • winner not in the room / already dead / disconnected
--     (no human heartbeat in 15 s),
--   • match never actually started server-side,
--   • non-winner slots still alive (no death record + recent
--     heartbeat for humans / no death record for bots).
-- Idempotent: the WHERE status='playing' guard plus the ROW_COUNT
-- check make a retried call a no-op instead of double-incrementing
-- the winner's br_wins.
CREATE OR REPLACE FUNCTION br_end_match(
  p_room_id          UUID,
  p_player_id        TEXT,
  p_winner_player_id TEXT
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_started_at       TIMESTAMPTZ;
  v_alive_non_winner INT;
  v_room_updated     INT;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM br_room_players p
    WHERE p.room_id = p_room_id
      AND p.player_id = p_player_id
      AND p.is_bot = FALSE
  ) THEN
    RAISE EXCEPTION 'not_in_room' USING ERRCODE = 'P0001';
  END IF;

  IF p_winner_player_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM br_room_players p
      WHERE p.room_id = p_room_id
        AND p.player_id = p_winner_player_id
    ) THEN
      RAISE EXCEPTION 'winner_not_in_room' USING ERRCODE = 'P0001';
    END IF;

    IF EXISTS (
      SELECT 1 FROM br_player_deaths d
      WHERE d.room_id = p_room_id
        AND d.player_id = p_winner_player_id
    ) THEN
      RAISE EXCEPTION 'winner_already_dead' USING ERRCODE = 'P0001';
    END IF;

    IF EXISTS (
      SELECT 1 FROM br_room_players p
      WHERE p.room_id = p_room_id
        AND p.player_id = p_winner_player_id
        AND p.is_bot = FALSE
        AND p.last_seen <= NOW() - INTERVAL '15 seconds'
    ) THEN
      RAISE EXCEPTION 'winner_disconnected' USING ERRCODE = 'P0001';
    END IF;
  END IF;

  SELECT started_at INTO v_started_at FROM br_rooms WHERE id = p_room_id;
  IF v_started_at IS NULL THEN
    RAISE EXCEPTION 'match_not_started' USING ERRCODE = 'P0001';
  END IF;

  SELECT COUNT(*) INTO v_alive_non_winner
  FROM br_room_players p
  WHERE p.room_id = p_room_id
    AND p.player_id <> COALESCE(p_winner_player_id, '')
    AND NOT EXISTS (
      SELECT 1 FROM br_player_deaths d
      WHERE d.room_id = p.room_id AND d.player_id = p.player_id
    )
    AND (
      p.is_bot = TRUE
      OR p.last_seen > NOW() - INTERVAL '15 seconds'
    );

  IF v_alive_non_winner > 0 THEN
    RAISE EXCEPTION 'match_not_resolved' USING ERRCODE = 'P0001';
  END IF;

  UPDATE br_rooms
  SET status = 'ended',
      ended_at = NOW(),
      winner_player_id = p_winner_player_id
  WHERE id = p_room_id
    AND status = 'playing';

  GET DIAGNOSTICS v_room_updated = ROW_COUNT;

  -- Bot ids use the `bot_…` prefix and have no profile row.
  IF v_room_updated > 0
     AND p_winner_player_id IS NOT NULL
     AND p_winner_player_id NOT LIKE 'bot\_%' ESCAPE '\' THEN
    UPDATE br_profiles
    SET br_wins    = br_wins + 1,
        updated_at = NOW()
    WHERE player_id = p_winner_player_id;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION br_end_match(UUID, TEXT, TEXT)
  TO anon, authenticated;

-- Leaving from the waiting phase — atomic with the empty-room
-- cleanup so we don't leak abandoned rows.
CREATE OR REPLACE FUNCTION br_leave_room(
  p_room_id    UUID,
  p_player_id  TEXT,
  p_slot_index INT
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  DELETE FROM br_room_players
  WHERE room_id = p_room_id
    AND slot_index = p_slot_index
    AND player_id = p_player_id;

  IF NOT EXISTS (
    SELECT 1 FROM br_room_players WHERE room_id = p_room_id
  ) THEN
    DELETE FROM br_rooms
    WHERE id = p_room_id AND status = 'waiting';
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION br_leave_room(UUID, TEXT, INT)
  TO anon, authenticated;

-- =====================================================================
-- 5. RPCs — profile management
-- =====================================================================

-- Stats sync from the client. Best_score grows monotonically (so a
-- flaky network never regresses progress). br_wins from the client
-- is ignored — it can only be bumped from inside `br_end_match`.
--
-- On a FRESH insert (no row for this player_id) the candidate name
-- is auto-suffixed with `_2`, `_3`, … until it's unique across the
-- table. Solves the bootstrap collision case where two devices
-- locally pick the same `JACK_xxxx`. The returned TEXT is the
-- canonical name actually stored — the client applies it to its
-- local mirror so the BR lobby / leaderboard see the deduped id.
--
-- On an EXISTING row, only the stats are touched. Renames must go
-- through `set_player_name`, which enforces the blacklist + the
-- cross-user uniqueness check (the stats path stays a back door
-- otherwise).
--
-- DROP first because the historical signature returned VOID — in
-- PostgreSQL `CREATE OR REPLACE` can't change return types.
DROP FUNCTION IF EXISTS upsert_br_profile(TEXT, TEXT, INT, INT, TEXT);

CREATE FUNCTION upsert_br_profile(
  p_player_id     TEXT,
  p_name          TEXT,
  p_best_score    INT,
  p_br_wins       INT,
  p_recovery_code TEXT DEFAULT NULL  -- ignored, kept for back-compat
) RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_existing_name TEXT;
  v_candidate     TEXT;
  v_suffix        INT;
  v_capped_score  INT := LEAST(GREATEST(p_best_score, 0), 10000000);
BEGIN
  SELECT name INTO v_existing_name
  FROM   br_profiles
  WHERE  player_id = p_player_id;

  IF v_existing_name IS NOT NULL THEN
    UPDATE br_profiles
    SET    best_score = GREATEST(br_profiles.best_score, v_capped_score),
           updated_at = NOW()
    WHERE  player_id = p_player_id;
    RETURN v_existing_name;
  END IF;

  v_candidate := p_name;
  v_suffix    := 1;
  WHILE EXISTS (
    SELECT 1 FROM br_profiles
    WHERE LOWER(TRIM(name)) = LOWER(TRIM(v_candidate))
  ) LOOP
    v_suffix    := v_suffix + 1;
    v_candidate := p_name || '_' || v_suffix::TEXT;
    EXIT WHEN v_suffix > 9999;  -- safety net
  END LOOP;

  INSERT INTO br_profiles
    (player_id, name, best_score, br_wins, updated_at)
  VALUES
    (p_player_id, v_candidate, v_capped_score, 0, NOW());

  RETURN v_candidate;
END;
$$;

GRANT EXECUTE ON FUNCTION upsert_br_profile(TEXT, TEXT, INT, INT, TEXT)
  TO anon, authenticated;

-- Validated rename. Raises a P0001 exception with one of:
--   name_empty, name_too_short, name_too_long, name_invalid_chars,
--   name_forbidden, name_taken.
-- The client maps these messages to localized inline errors.
CREATE OR REPLACE FUNCTION set_player_name(
  p_player_id     TEXT,
  p_name          TEXT,
  p_recovery_code TEXT DEFAULT NULL  -- ignored, kept for back-compat
) RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_cleaned TEXT;
  v_lower   TEXT;
BEGIN
  v_cleaned := TRIM(p_name);
  IF v_cleaned IS NULL OR length(v_cleaned) = 0 THEN
    RAISE EXCEPTION 'name_empty' USING ERRCODE = 'P0001';
  END IF;
  IF length(v_cleaned) < 2 THEN
    RAISE EXCEPTION 'name_too_short' USING ERRCODE = 'P0001';
  END IF;
  IF length(v_cleaned) > 18 THEN
    RAISE EXCEPTION 'name_too_long' USING ERRCODE = 'P0001';
  END IF;
  IF v_cleaned ~ '[\x00-\x1F\x7F]' THEN
    RAISE EXCEPTION 'name_invalid_chars' USING ERRCODE = 'P0001';
  END IF;

  v_lower := LOWER(v_cleaned);

  IF EXISTS (
    SELECT 1 FROM br_name_blacklist
    WHERE v_lower LIKE '%' || pattern || '%'
  ) THEN
    RAISE EXCEPTION 'name_forbidden' USING ERRCODE = 'P0001';
  END IF;

  IF EXISTS (
    SELECT 1 FROM br_profiles
    WHERE LOWER(TRIM(name)) = v_lower
      AND player_id <> p_player_id
  ) THEN
    RAISE EXCEPTION 'name_taken' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO br_profiles
    (player_id, name, best_score, br_wins, updated_at)
  VALUES
    (p_player_id, v_cleaned, 0, 0, NOW())
  ON CONFLICT (player_id) DO UPDATE
  SET name       = v_cleaned,
      updated_at = NOW();

  RETURN v_cleaned;
END;
$$;

GRANT EXECUTE ON FUNCTION set_player_name(TEXT, TEXT, TEXT)
  TO anon, authenticated;

-- Boot-time hydration: client calls this with its IDFV-derived
-- player_id to pull the row back into local state. The IDFV is
-- hashed + salted client-side, so the value isn't trivially
-- guessable from outside the device — that's identity enough
-- until Google sign-in lands.
CREATE OR REPLACE FUNCTION get_my_profile(p_player_id TEXT)
RETURNS TABLE(player_id TEXT, name TEXT, best_score INT, br_wins INT)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT p.player_id, p.name, p.best_score, p.br_wins
  FROM br_profiles p
  WHERE p.player_id = p_player_id;
END;
$$;

GRANT EXECUTE ON FUNCTION get_my_profile(TEXT) TO anon, authenticated;

-- Lobby reads "🏆 N" beside each room member through this. Returns
-- only the ids the caller already supplied, so it can't be used to
-- dump the table.
CREATE OR REPLACE FUNCTION get_br_wins_for_players(p_player_ids TEXT[])
RETURNS TABLE(player_id TEXT, br_wins INT)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT p.player_id, p.br_wins
  FROM br_profiles p
  WHERE p.player_id = ANY(p_player_ids);
END;
$$;

GRANT EXECUTE ON FUNCTION get_br_wins_for_players(TEXT[])
  TO anon, authenticated;

-- Drop the legacy recovery-code RPC if it's still around from a
-- pre-consolidation deploy. The client no longer calls it; the
-- profile lookup now flows through get_my_profile / device id.
DROP FUNCTION IF EXISTS redeem_recovery_code(TEXT);

-- =====================================================================
-- 6. CRON — scheduled cleanup
--    pg_cron runs `br_cleanup_stale_rooms()` once a minute to drop:
--      • waiting rooms older than 5 minutes
--      • ended rooms older than 1 hour
--    The ON DELETE CASCADE on br_room_players / br_player_deaths
--    takes the rest with them, so death rows don't accumulate either.
-- =====================================================================

CREATE OR REPLACE FUNCTION br_cleanup_stale_rooms()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  DELETE FROM br_rooms
  WHERE (status = 'waiting' AND created_at < NOW() - INTERVAL '5 minutes')
     OR (status = 'ended'   AND COALESCE(ended_at, created_at)
                                < NOW() - INTERVAL '1 hour');
END;
$$;

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
