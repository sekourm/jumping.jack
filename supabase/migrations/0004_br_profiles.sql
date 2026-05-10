-- ============================================================
-- 0004_br_profiles
-- Per-device persistent profile: best_score, br_wins, current
-- nickname. Keyed by `player_id`, which is the stable device-
-- derived id generated in `Preferences._generatePlayerId` on
-- first launch (no auth in this game).
--
-- The lobby reads `br_wins` to show "🏆 N" next to each human
-- player. Writes go through `upsert_br_profile` which always
-- keeps the max of best_score / br_wins so a flaky network
-- never regresses the stored value.
-- ============================================================

CREATE TABLE IF NOT EXISTS br_profiles (
  player_id    TEXT PRIMARY KEY,
  name         TEXT NOT NULL,
  best_score   INT NOT NULL DEFAULT 0,
  br_wins      INT NOT NULL DEFAULT 0,
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Realtime is not needed: the lobby loads profiles once per
-- player set. We just need read/write under anon.
ALTER TABLE br_profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_all_profiles" ON br_profiles;
CREATE POLICY "anon_all_profiles" ON br_profiles
  FOR ALL TO anon, authenticated
  USING (true) WITH CHECK (true);

-- Upsert that monotonically grows best_score and br_wins, and
-- always picks up the latest nickname / timestamp. Clients call
-- this whenever they finish a run, win a BR, or change their
-- nickname — and on every BR join so a profile row always
-- exists by the time the lobby queries it.
CREATE OR REPLACE FUNCTION upsert_br_profile(
  p_player_id  TEXT,
  p_name       TEXT,
  p_best_score INT,
  p_br_wins    INT
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO br_profiles (player_id, name, best_score, br_wins, updated_at)
  VALUES (p_player_id, p_name, GREATEST(p_best_score, 0), GREATEST(p_br_wins, 0), NOW())
  ON CONFLICT (player_id) DO UPDATE
  SET name       = EXCLUDED.name,
      best_score = GREATEST(br_profiles.best_score, EXCLUDED.best_score),
      br_wins    = GREATEST(br_profiles.br_wins, EXCLUDED.br_wins),
      updated_at = NOW();
END;
$$;

GRANT EXECUTE ON FUNCTION upsert_br_profile(TEXT, TEXT, INT, INT) TO anon, authenticated;
