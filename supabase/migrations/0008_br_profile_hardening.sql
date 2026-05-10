-- Battle Royale — profile anti-cheat. Builds on 0006 / 0007.
--
-- BACKGROUND
--   Two open doors remained on br_profiles:
--     1. `upsert_br_profile` accepted any (player_id, name, best_score,
--        br_wins) combo from the anon role, so a browser console PATCH
--        forged huge win counts, inflated best_score, or renamed any
--        other user.
--     2. RLS on br_profiles was `FOR ALL USING (true)`, letting the same
--        anon key dump every row via `GET /rest/v1/br_profiles?select=*`.
--
-- WHAT THIS MIGRATION ADDS
--   1. SELECT is removed from br_profiles entirely — anon now has zero
--      direct access. The lobby's legitimate "show 🏆 N next to room
--      members" path uses the new RPC `get_br_wins_for_players` which
--      returns only (player_id, br_wins) and only for ids the caller
--      already knows about.
--   2. `upsert_br_profile` is rewritten to:
--        • cap best_score at 10_000_000 (saturating),
--        • ignore p_br_wins (server-authoritative now — see below),
--        • require the caller-provided recovery_code to match the
--          stored one when the profile already has one. This is the
--          poor-man's "you can only edit yourself" guard: a cheater
--          knows their own code but not anyone else's.
--   3. `br_end_match` (last seen in 0007) now also:
--        • rejects winners that are dead, disconnected, or bots,
--        • increments the winner's br_wins inside the same transaction
--          as the room flip. Idempotent via the `WHERE status='playing'`
--          guard + a ROW_COUNT check, so a retried call doesn't
--          double-count.
--   4. One-time clamp of any pre-existing inflated br_wins to 200 — well
--      above any plausible legitimate count at this game's age.

-- ---------- 1. Lock SELECT on br_profiles ----------
DROP POLICY IF EXISTS "anon_all_profiles" ON br_profiles;
-- Intentionally NO policy. Reads happen through SECURITY DEFINER RPCs
-- (`get_br_wins_for_players`, `redeem_recovery_code`); writes happen
-- through `upsert_br_profile`. The anon role has no direct path.

-- ---------- 2. One-time clamp on inflated wins ----------
UPDATE br_profiles
SET br_wins = 200,
    updated_at = NOW()
WHERE br_wins > 200;

-- ---------- 3. upsert_br_profile (recovery_code gated) ----------
CREATE OR REPLACE FUNCTION upsert_br_profile(
  p_player_id     TEXT,
  p_name          TEXT,
  p_best_score    INT,
  p_br_wins       INT,            -- ignored — kept for backward compat
  p_recovery_code TEXT DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_stored_code  TEXT;
  v_capped_score INT := LEAST(GREATEST(p_best_score, 0), 10000000);
BEGIN
  SELECT recovery_code INTO v_stored_code
  FROM br_profiles
  WHERE player_id = p_player_id;

  -- If a profile already exists AND it has a recovery code, subsequent
  -- writes must present the same code. Blocks the browser-console
  -- forgery from renaming / re-statting other players, since the cheater
  -- doesn't have anyone else's code.
  IF v_stored_code IS NOT NULL
     AND (p_recovery_code IS NULL OR p_recovery_code <> v_stored_code) THEN
    RAISE EXCEPTION 'recovery_code_mismatch' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO br_profiles
    (player_id, name, best_score, br_wins, recovery_code, updated_at)
  VALUES
    (p_player_id, p_name, v_capped_score, 0, p_recovery_code, NOW())
  ON CONFLICT (player_id) DO UPDATE
  SET name          = EXCLUDED.name,
      best_score    = GREATEST(br_profiles.best_score, EXCLUDED.best_score),
      -- br_wins is NOT updated here: it's bumped server-side from
      -- br_end_match only, so a client cannot forge wins anymore.
      recovery_code = COALESCE(br_profiles.recovery_code, EXCLUDED.recovery_code),
      updated_at    = NOW();
END;
$$;

GRANT EXECUTE ON FUNCTION upsert_br_profile(TEXT, TEXT, INT, INT, TEXT)
  TO anon, authenticated;

-- ---------- 4. get_br_wins_for_players ----------
-- Lobby uses this to show "🏆 N" next to room members. Returns only the
-- minimum needed — no recovery_code, no best_score, no timestamps — and
-- only for ids the caller already knows about (i.e. it cannot be used
-- to enumerate the table).
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

-- ---------- 5. br_end_match (now bumps winner's profile) ----------
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
  IF v_started_at IS NULL
     OR NOW() - v_started_at < INTERVAL '15 seconds' THEN
    RAISE EXCEPTION 'match_too_short' USING ERRCODE = 'P0001';
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

  -- Bump the winner's br_wins atomically with the room flip. The
  -- ROW_COUNT guard makes the bump idempotent: a retried br_end_match
  -- on an already-ended room sees v_room_updated = 0 and skips it. Bot
  -- ids (prefix `bot_`) never get a profile row, so they're excluded.
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
