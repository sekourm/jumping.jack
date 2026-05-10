/// Supabase project credentials. Replace the placeholders below with the
/// values from your Supabase project (Settings → API).
///
/// The anon key is a public token — safe to ship in the client. RLS
/// policies on the database control what it can actually do.
class SupabaseConfig {
  /// Project URL, e.g. `https://xxxxxxx.supabase.co`.
  static const String url = 'https://uumsewtdeylldacxdemc.supabase.co';

  /// `anon public` key from the dashboard. Safe to ship in the client —
  /// RLS policies on the database enforce what it can actually do.
  static const String anonKey =
      'sb_publishable_SPvF4W1OZTmZeBLBDSNdYg_gm1a3yjF';

  /// Returns true when both values are non-empty placeholders are filled.
  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;
}
