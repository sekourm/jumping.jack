import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../i18n/i18n.dart';

/// User preferences. Persisted across launches via [SharedPreferences]:
/// high score, tutorial toggle, and the auto-generated Battle Royale
/// nickname (so other players see the same JACK_xxxx name session after
/// session).
class Preferences {
  static const _kBestScore = 'best_score';
  static const _kBrWins = 'br_wins';
  static const _kShowTutorial = 'show_tutorial';
  static const _kPlayerId = 'player_id';
  static const _kPlayerName = 'player_name';
  static const _kLocale = 'locale';

  static SharedPreferences? _prefs;
  static int _bestScore = 0;
  static int _brWins = 0;
  static bool _showTutorial = true;
  static String _playerId = '';
  static String _playerName = '';
  static AppLocale _locale = AppLocale.fr;

  /// Loads persisted values into memory. Must be awaited before any reads.
  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _bestScore = _prefs?.getInt(_kBestScore) ?? 0;
    _brWins = _prefs?.getInt(_kBrWins) ?? 0;
    _showTutorial = _prefs?.getBool(_kShowTutorial) ?? true;

    // Auto-generate a stable player id + display name on first run.
    _playerId = _prefs?.getString(_kPlayerId) ?? _generatePlayerId();
    _playerName = _prefs?.getString(_kPlayerName) ?? _generatePlayerName();
    _prefs?.setString(_kPlayerId, _playerId);
    _prefs?.setString(_kPlayerName, _playerName);

    final localeName = _prefs?.getString(_kLocale);
    _locale = AppLocale.values.firstWhere(
      (l) => l.name == localeName,
      orElse: () => AppLocale.fr,
    );
  }

  static String _generatePlayerId() {
    final rng = Random.secure();
    final hex = StringBuffer();
    for (var i = 0; i < 16; i++) {
      hex.write(rng.nextInt(16).toRadixString(16));
    }
    return hex.toString();
  }

  static String _generatePlayerName() {
    final rng = Random.secure();
    return 'JACK_${1000 + rng.nextInt(9000)}';
  }

  // ---- High score ----

  static int get bestScore => _bestScore;

  /// Updates the best score in memory and persists it asynchronously.
  /// Returns true if [score] beats the previous best.
  static bool updateBestScore(int score) {
    if (score <= _bestScore) return false;
    _bestScore = score;
    _prefs?.setInt(_kBestScore, score);
    return true;
  }

  // ---- Battle Royale wins ----

  static int get brWins => _brWins;

  /// Bumps the lifetime BR victory counter by 1 and persists.
  static void incrementBrWins() {
    _brWins += 1;
    _prefs?.setInt(_kBrWins, _brWins);
  }

  // ---- Tutorial ----

  /// Whether to show the onboarding tutorial when a new game starts.
  /// Reading hits the in-memory cache. Writing updates the cache and
  /// fire-and-forgets a write to disk so the choice survives reloads.
  static bool get showTutorial => _showTutorial;
  static set showTutorial(bool value) {
    _showTutorial = value;
    _prefs?.setBool(_kShowTutorial, value);
  }

  // ---- Battle Royale identity ----

  /// Stable random ID for this device — used as the player's primary key
  /// in the BR matchmaking and presence flow. Never displayed.
  static String get playerId => _playerId;

  /// Display name shown to other players (e.g. JACK_4271). Generated once
  /// at first launch; can be changed later from settings.
  static String get playerName => _playerName;
  static set playerName(String value) {
    final cleaned = value.trim();
    if (cleaned.isEmpty) return;
    _playerName = cleaned;
    _prefs?.setString(_kPlayerName, cleaned);
  }

  // ---- Language ----

  static AppLocale get locale => _locale;
  static set locale(AppLocale value) {
    _locale = value;
    _prefs?.setString(_kLocale, value.name);
  }
}
