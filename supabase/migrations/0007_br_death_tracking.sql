-- Battle Royale — full server-side death tracking + alive-count gate on
-- match end. Builds on 0006 to close the last remaining cheat path.
--
-- BACKGROUND
--   0006 stopped the trivial "PATCH br_rooms" exploit, but a player who
--   actually queues into a real match could still call br_end_match with
--   themselves as the winner after the 15 s min-duration window — the
--   server had no way to tell whether the other players had really lost.
--
-- WHAT THIS MIGRATION ADDS
--   1. Table `br_player_deaths` — one row per (room, victim) recording
--      who died, when, who killed them, and which client reported it.
--   2. RPC `br_report_death` — validates the reporter, then inserts a
--      death idempotently. Humans can only report themselves dead; bots
--      can be reported by any human in the room (bots are simulated
--      client-side and there is no leader identity server-side).
--   3. `br_end_match` now requires every non-winner slot in the room
--      either to have a death record OR (for humans) to have a stale
--      heartbeat. A cheater can no longer claim victory until reality
--      catches up.
--   4. `br_room_players` is locked to SELECT-only for the anon role so
--      the cheater can't DELETE opponents or UPDATE them to is_bot=TRUE
--      to dodge the new check. The previously-allowed bot upsert moves
--      into `br_start_match`, which now seeds bots atomically alongside
--      the status flip (both happen inside the same SECURITY DEFINER
--      transaction).
--
-- LIMITATIONS
--   Multi-device "boosting" (two accounts coordinating, one throwing the
--   match to the other) is still possible — but that requires real
--   social effort, not a one-liner in the browser console.

-- ---------- Death-record table ----------
CREATE TABLE IF NOT EXISTS br_player_deaths (
  room_id UUID NOT NULL REFERENCES br_rooms(id) ON DELETE CASCADE,
  player_id TEXT NOT NULL,
  died_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  killer_player_id TEXT,
  reporter_player_id TEXT NOT NULL,
  PRIMARY KEY (room_id, player_id)
);

CREATE INDEX IF NOT EXISTS idx_br_player_deaths_room
  ON br_player_deaths (room_id);

ALTER TABLE br_player_deaths ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_select_deaths" ON br_player_deaths;
CREATE POLICY "anon_select_deaths" ON br_player_deaths
  FOR SELECT USING (true);

-- No INSERT/UPDATE/DELETE for anon: deaths land via br_report_death.

-- ---------- Lock br_room_players writes ----------
DROP POLICY IF EXISTS "anon_all_players" ON br_room_players;
DROP POLICY IF EXISTS "anon_select_players" ON br_room_players;

CREATE POLICY "anon_select_players" ON br_room_players
  FOR SELECT USING (true);

-- All br_room_players writes now flow through SECURITY DEFINER RPCs:
--   • join_or_create_br_room — claim a slot
--   • br_start_match         — seed bot slots + flip status to playing
--   • br_heartbeat           — bump last_seen
--   • br_leave_room          — release a slot

-- ---------- br_start_match (now atomic with bot seeding) ----------
-- Old signature kept by name (overload by parameter list). Existing
-- clients pass empty arrays; new ones pass the bot rows so they land
-- inside the same SECURITY DEFINER transaction as the status flip.
CREATE OR REPLACE FUNCTION br_start_match(
  p_room_id UUID,
  p_player_id TEXT,
  p_bot_slots INT[] DEFAULT ARRAY[]::INT[],
  p_bot_player_ids TEXT[] DEFAULT ARRAY[]::TEXT[],
  p_bot_names TEXT[] DEFAULT ARRAY[]::TEXT[]
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

  -- Idempotent bot seeding: PK conflict on (room_id, slot_index) means a
  -- racing leader's second call quietly no-ops instead of double-inserting.
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

-- ---------- br_report_death ----------
CREATE OR REPLACE FUNCTION br_report_death(
  p_room_id UUID,
  p_dead_player_id TEXT,
  p_reporter_player_id TEXT,
  p_killer_player_id TEXT DEFAULT NULL
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

  -- Humans can only flag themselves dead. This is what blocks the
  -- cheater from spamming "everyone is dead" to satisfy br_end_match —
  -- they can only forge their own death, which doesn't help them win.
  -- Bots are simulated locally by the room leader and the server has no
  -- leader identity, so any human room member can flag bot deaths
  -- (otherwise a leader's network blip would deadlock the match).
  IF v_is_bot = FALSE
     AND p_reporter_player_id <> p_dead_player_id THEN
    RAISE EXCEPTION 'cannot_report_other_human' USING ERRCODE = 'P0001';
  END IF;

  -- Idempotent: a retry, the leader's own echo of a crush kill, or a
  -- watchdog from another client all collapse to the first row.
  INSERT INTO br_player_deaths
    (room_id, player_id, killer_player_id, reporter_player_id)
  VALUES
    (p_room_id, p_dead_player_id, p_killer_player_id, p_reporter_player_id)
  ON CONFLICT (room_id, player_id) DO NOTHING;
END;
$$;

-- ---------- br_end_match (now alive-count gated) ----------
CREATE OR REPLACE FUNCTION br_end_match(
  p_room_id UUID,
  p_player_id TEXT,
  p_winner_player_id TEXT
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_started_at TIMESTAMPTZ;
  v_alive_non_winner INT;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM br_room_players p
    WHERE p.room_id = p_room_id
      AND p.player_id = p_player_id
      AND p.is_bot = FALSE
  ) THEN
    RAISE EXCEPTION 'not_in_room' USING ERRCODE = 'P0001';
  END IF;

  IF p_winner_player_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM br_room_players p
    WHERE p.room_id = p_room_id
      AND p.player_id = p_winner_player_id
  ) THEN
    RAISE EXCEPTION 'winner_not_in_room' USING ERRCODE = 'P0001';
  END IF;

  SELECT started_at INTO v_started_at FROM br_rooms WHERE id = p_room_id;
  IF v_started_at IS NULL
     OR NOW() - v_started_at < INTERVAL '15 seconds' THEN
    RAISE EXCEPTION 'match_too_short' USING ERRCODE = 'P0001';
  END IF;

  -- A non-winner slot is "still alive" from the server's viewpoint if
  -- it has NO death record AND (for humans) heartbeated in the last 15s.
  -- Bots stay alive until an explicit death is recorded. A stale human
  -- heartbeat means the device crashed / closed the tab → treat as dead
  -- so a single abandon doesn't deadlock the match.
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
END;
$$;

-- ---------- Optional cleanup of stale deaths ----------
-- Extends the existing br_cleanup_stale_rooms cron job's intent: when
-- rooms get pruned, the ON DELETE CASCADE on br_player_deaths drops the
-- death rows too, so we don't accumulate orphans.
