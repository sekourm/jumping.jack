-- Battle Royale — anti-cheat hardening on br_rooms.
--
-- BACKGROUND
--   The previous RLS policy `anon_all_rooms` was `FOR ALL USING (true) WITH
--   CHECK (true)`, which let any anon client PATCH the table directly. It
--   was trivially exploited via a browser-console script that intercepted
--   the room_id from realtime traffic and then PATCHed
--     status='ended', winner_player_id=<my id>
--   on /rest/v1/br_rooms — granting an unearned win on every match.
--
-- WHAT THIS MIGRATION DOES
--   1. Drops the wide-open ALL policy on br_rooms.
--   2. Keeps SELECT open (clients still need to read created_at / status /
--      winner from the lobby + result screens, and Realtime UPDATE events
--      go through SELECT permission).
--   3. Adds three SECURITY DEFINER RPCs that are now the only path to
--      mutate the table: br_start_match, br_end_match, br_leave_room.
--      Each validates that the caller is actually a human player in the
--      room and that the proposed state change is plausible.
--   4. br_end_match enforces a minimum elapsed time since started_at, so
--      "instant win" scripts (the reported cheat fires ~10 s after join)
--      are rejected outright.
--
-- LIMITATIONS
--   Because the game has no real user auth (player_id is generated on
--   each device), a determined cheater who actually queues into a match
--   can still call br_end_match with their own id after the minimum
--   duration. Fully removing that would need a server-authoritative death
--   tracker (an extra table that each death broadcast writes to, then
--   br_end_match would require all non-winners to be recorded dead).
--   That's a bigger redesign — out of scope for this hot-fix.

-- ---------- Tighten RLS on br_rooms ----------
DROP POLICY IF EXISTS "anon_all_rooms" ON br_rooms;

CREATE POLICY "anon_select_rooms" ON br_rooms
  FOR SELECT USING (true);

-- No INSERT/UPDATE/DELETE policy for the anon role on purpose — all
-- writes now have to go through the SECURITY DEFINER RPCs below.

-- ---------- RPC: start the match ----------
-- Called by the room "leader" when the lobby countdown reaches zero.
-- Replaces the client-side UPDATE on br_rooms in BattleRoyaleService.
CREATE OR REPLACE FUNCTION br_start_match(
  p_room_id UUID,
  p_player_id TEXT
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM br_room_players p
    WHERE p.room_id = p_room_id
      AND p.player_id = p_player_id
      AND p.is_bot = FALSE
  ) THEN
    RAISE EXCEPTION 'not_in_room' USING ERRCODE = 'P0001';
  END IF;

  -- started_at is set server-side so clients can't lie about it later
  -- to bypass the duration check in br_end_match.
  UPDATE br_rooms
  SET status = 'playing',
      started_at = NOW()
  WHERE id = p_room_id
    AND status = 'waiting';
END;
$$;

-- ---------- RPC: end the match ----------
-- Validates everything we can validate without server-side gameplay
-- state:
--   • caller is a human player currently in the room,
--   • proposed winner is in the room (any slot — human or bot),
--   • the room is currently 'playing' (idempotent — second call no-ops
--     instead of overwriting a previously-recorded winner),
--   • enough time has elapsed since the match started server-side so
--     scripts that fire seconds after join are rejected.
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

  -- Match must have actually been running for at least 15 s. The
  -- previously-reported cheat fires a PATCH ~10 s after detecting the
  -- room id, so this kills the "queue + instantly win" pattern.
  -- 15 s is well below any realistic BR length but above the in-game
  -- safety window (10 s) plus a couple of arcs.
  SELECT started_at INTO v_started_at FROM br_rooms WHERE id = p_room_id;
  IF v_started_at IS NULL
     OR NOW() - v_started_at < INTERVAL '15 seconds' THEN
    RAISE EXCEPTION 'match_too_short' USING ERRCODE = 'P0001';
  END IF;

  -- AND status = 'playing' makes the row write a one-shot — once the
  -- match is ended, retries (or the cheat) can't overwrite the winner.
  UPDATE br_rooms
  SET status = 'ended',
      ended_at = NOW(),
      winner_player_id = p_winner_player_id
  WHERE id = p_room_id
    AND status = 'playing';
END;
$$;

-- ---------- RPC: leave a room (waiting-phase cleanup) ----------
-- Drops the caller's slot and, if the room becomes empty, removes the
-- waiting row too. Replaces the client-side DELETE on br_rooms that ran
-- in BattleRoyaleService.leaveMatch — that DELETE is now blocked by the
-- tightened RLS.
CREATE OR REPLACE FUNCTION br_leave_room(
  p_room_id UUID,
  p_player_id TEXT,
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
