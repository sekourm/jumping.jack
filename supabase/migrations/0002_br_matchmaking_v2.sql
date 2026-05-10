-- Battle Royale matchmaking — production-grade revision.
--
-- Adds:
--   • `last_seen` heartbeat column on br_room_players for liveness.
--   • A pre-join sweep that:
--       - drops human players whose last_seen is older than 20s (ghosts
--         — closed tabs, dead network),
--       - deletes empty waiting rooms left behind.
--   • A "prefer fullest room" join strategy so players land in the same
--     lobby instead of spawning new rooms in parallel.
--   • A `br_heartbeat` RPC clients call every 5s to keep their slot.
--
-- Patterns inspired by typical Brawl Stars / Among Us style matchmaking
-- (atomic slot reservation, heartbeat-based liveness, fairness toward the
-- oldest pending lobby).

-- ---------- Schema ----------
ALTER TABLE br_room_players
  ADD COLUMN IF NOT EXISTS last_seen TIMESTAMPTZ NOT NULL DEFAULT NOW();

CREATE INDEX IF NOT EXISTS idx_br_room_players_last_seen
  ON br_room_players (last_seen);

-- ---------- Matchmaking ----------
CREATE OR REPLACE FUNCTION join_or_create_br_room(
  p_player_id TEXT,
  p_name TEXT
) RETURNS TABLE(room_id UUID, slot_index INT)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_room_id UUID;
  v_slot INT;
  v_stale_threshold TIMESTAMPTZ := NOW() - INTERVAL '20 seconds';
BEGIN
  -- Step 1 — drop ghost players (no heartbeat in 20s, never bots).
  DELETE FROM br_room_players p
  USING br_rooms r
  WHERE p.room_id = r.id
    AND r.status = 'waiting'
    AND p.is_bot = FALSE
    AND p.last_seen < v_stale_threshold;

  -- Step 2 — delete empty waiting rooms left after the sweep.
  DELETE FROM br_rooms r
  WHERE r.status = 'waiting'
    AND NOT EXISTS (
      SELECT 1 FROM br_room_players p WHERE p.room_id = r.id
    );

  -- Step 3 — pick a waiting room: fullest first, then oldest. Skip empty
  -- ones (count >= 1) so we don't fall back into an abandoned lobby.
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

  -- Step 4 — no candidate → create a fresh room.
  IF v_room_id IS NULL THEN
    INSERT INTO br_rooms DEFAULT VALUES RETURNING id INTO v_room_id;
  END IF;

  -- Step 5 — claim the lowest free slot atomically.
  SELECT MIN(s) INTO v_slot
  FROM generate_series(0, 4) s
  WHERE s NOT IN (
    SELECT p.slot_index FROM br_room_players p WHERE p.room_id = v_room_id
  );

  -- Defensive: if the room filled between the lock and the slot claim
  -- (extremely rare race), surface a clear error so the client can retry.
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

-- ---------- Heartbeat ----------
CREATE OR REPLACE FUNCTION br_heartbeat(
  p_room_id UUID,
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

-- ---------- Optional: stale-room cleanup helper ----------
-- Run on a cron (e.g. once a minute) or call manually to keep the table
-- tidy. Drops waiting rooms older than 5 minutes and finished rooms
-- older than 1 hour.
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
