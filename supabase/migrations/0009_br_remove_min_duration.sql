-- Remove the 15-second minimum match duration check from br_end_match.
-- Legitimate short matches (fast resolution with bots, or a quick wipe)
-- were getting permanently blocked by the anti-cheat guard. The other
-- safeguards (winner-not-in-room, winner-already-dead, winner-disconnected,
-- match-not-resolved) remain in place.

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
