-- Battle Royale schema for Jumping JACK
-- Run this once in the Supabase SQL Editor of your project.
--
-- It creates:
--   • br_rooms          : matches in the lifecycle waiting → playing → ended
--   • br_room_players   : up to 5 slots per room (humans or bots)
--   • RLS policies open to the anon role (we have no user auth)
--   • Realtime publication entries for live updates from the client
--   • RPC `join_or_create_br_room` that atomically claims a slot

-- ---------- Tables ----------
CREATE TABLE IF NOT EXISTS br_rooms (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  status TEXT NOT NULL DEFAULT 'waiting'
    CHECK (status IN ('waiting', 'playing', 'ended')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  started_at TIMESTAMPTZ,
  ended_at TIMESTAMPTZ,
  winner_player_id TEXT
);

CREATE TABLE IF NOT EXISTS br_room_players (
  room_id UUID NOT NULL REFERENCES br_rooms(id) ON DELETE CASCADE,
  slot_index INT NOT NULL CHECK (slot_index BETWEEN 0 AND 4),
  player_id TEXT NOT NULL,
  name TEXT NOT NULL,
  is_bot BOOLEAN NOT NULL DEFAULT FALSE,
  joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (room_id, slot_index)
);

CREATE INDEX IF NOT EXISTS idx_br_rooms_status_created
  ON br_rooms (status, created_at DESC);

-- ---------- RLS (anon-friendly: no user auth in this game) ----------
ALTER TABLE br_rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE br_room_players ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_all_rooms" ON br_rooms;
DROP POLICY IF EXISTS "anon_all_players" ON br_room_players;

CREATE POLICY "anon_all_rooms" ON br_rooms
  FOR ALL USING (true) WITH CHECK (true);

CREATE POLICY "anon_all_players" ON br_room_players
  FOR ALL USING (true) WITH CHECK (true);

-- ---------- Realtime ----------
-- Wraps the ALTER PUBLICATION so a re-run doesn't fail.
DO $$
BEGIN
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE br_rooms;
  EXCEPTION
    WHEN duplicate_object THEN NULL;
  END;
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE br_room_players;
  EXCEPTION
    WHEN duplicate_object THEN NULL;
  END;
END$$;

-- ---------- RPC ----------
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
BEGIN
  SELECT r.id INTO v_room_id
  FROM br_rooms r
  WHERE r.status = 'waiting'
    AND r.created_at > NOW() - INTERVAL '30 seconds'
    AND (SELECT COUNT(*) FROM br_room_players p WHERE p.room_id = r.id) < 5
  ORDER BY r.created_at DESC
  LIMIT 1
  FOR UPDATE OF r;

  IF v_room_id IS NULL THEN
    INSERT INTO br_rooms DEFAULT VALUES RETURNING id INTO v_room_id;
  END IF;

  SELECT MIN(s) INTO v_slot
  FROM generate_series(0, 4) s
  WHERE s NOT IN (
    SELECT p.slot_index FROM br_room_players p WHERE p.room_id = v_room_id
  );

  INSERT INTO br_room_players (room_id, slot_index, player_id, name)
  VALUES (v_room_id, v_slot, p_player_id, p_name);

  RETURN QUERY SELECT v_room_id, v_slot;
END;
$$;
