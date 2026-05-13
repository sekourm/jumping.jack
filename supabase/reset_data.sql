-- ============================================================
-- reset_data.sql
-- Wipes all live data while preserving the schema, so we can
-- start a fresh testing session without redeploying.
--
-- What's wiped:
--   • br_player_deaths   — death records per match
--   • br_room_players    — slots (humans + bots) in lobbies/matches
--   • br_rooms           — match lifecycle rows
--   • br_profiles        — per-device profiles (best_score, br_wins,
--                          chosen pseudos)
--
-- What's preserved:
--   • All tables / indices / RLS policies / functions / cron job
--   • br_name_blacklist  — the vocabulary stays put (run
--     seed_blacklist.sql separately if you ever wipe it too)
--
-- TRUNCATE is faster than DELETE on a large table, RESTART IDENTITY
-- resets any sequence (not currently used by these tables, but
-- defensive for future ones), and CASCADE walks the foreign keys
-- so we don't have to order the statements by FK direction.
-- ============================================================

TRUNCATE TABLE
  br_player_deaths,
  br_room_players,
  br_rooms,
  br_profiles
RESTART IDENTITY CASCADE;
