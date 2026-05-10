-- ============================================================
-- 0005_recovery_code
-- Adds a short, human-readable recovery code to each profile so
-- web users (who lack a stable device id by browser design) can
-- migrate their progress between browsers / cleared caches.
--
-- Format on the client: `JJ-XXXX-XXXX` where X is from a 32-char
-- alphabet that excludes ambiguous glyphs (0/O, 1/I/L). ~31 bits
-- of entropy — plenty for collision avoidance at this player
-- count scale.
-- ============================================================

ALTER TABLE br_profiles
  ADD COLUMN IF NOT EXISTS recovery_code TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS idx_br_profiles_recovery_code
  ON br_profiles (recovery_code)
  WHERE recovery_code IS NOT NULL;

-- Re-create the upsert so a new client passing a recovery_code
-- writes it once and never overwrites it (the code is permanent
-- per profile — losing it is what the lookup-by-name backup is
-- supposed to fix). Existing callers that don't pass the code
-- continue to work unchanged.
CREATE OR REPLACE FUNCTION upsert_br_profile(
  p_player_id     TEXT,
  p_name          TEXT,
  p_best_score    INT,
  p_br_wins       INT,
  p_recovery_code TEXT DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO br_profiles
    (player_id, name, best_score, br_wins, recovery_code, updated_at)
  VALUES
    (p_player_id, p_name, GREATEST(p_best_score, 0),
     GREATEST(p_br_wins, 0), p_recovery_code, NOW())
  ON CONFLICT (player_id) DO UPDATE
  SET name          = EXCLUDED.name,
      best_score    = GREATEST(br_profiles.best_score, EXCLUDED.best_score),
      br_wins       = GREATEST(br_profiles.br_wins, EXCLUDED.br_wins),
      -- Recovery code is sticky: once set, never overwritten.
      recovery_code = COALESCE(br_profiles.recovery_code, EXCLUDED.recovery_code),
      updated_at    = NOW();
END;
$$;

GRANT EXECUTE ON FUNCTION upsert_br_profile(TEXT, TEXT, INT, INT, TEXT)
  TO anon, authenticated;

-- Lookup used by the "restore profile" UI. Returns the cloud-of-
-- record values for a code so the client can replace its local
-- player_id + stats with the recovered profile.
CREATE OR REPLACE FUNCTION redeem_recovery_code(p_code TEXT)
RETURNS TABLE(
  player_id  TEXT,
  name       TEXT,
  best_score INT,
  br_wins    INT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT p.player_id, p.name, p.best_score, p.br_wins
  FROM br_profiles p
  WHERE p.recovery_code = p_code
  LIMIT 1;
END;
$$;

GRANT EXECUTE ON FUNCTION redeem_recovery_code(TEXT) TO anon, authenticated;
