import 'package:shared_preferences/shared_preferences.dart';

/// User preferences. Both the high score and the tutorial toggle are
/// persisted across launches via [SharedPreferences] so a player who has
/// already cleared the onboarding doesn't see it again on a page reload.
class Preferences {
  static const _kBestScore = 'best_score';
  static const _kShowTutorial = 'show_tutorial';

  static SharedPreferences? _prefs;
  static int _bestScore = 0;
  static bool _showTutorial = true;

  /// Loads persisted values into memory. Must be awaited before any reads.
  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _bestScore = _prefs?.getInt(_kBestScore) ?? 0;
    _showTutorial = _prefs?.getBool(_kShowTutorial) ?? true;
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

  // ---- Tutorial ----

  /// Whether to show the onboarding tutorial when a new game starts.
  /// Reading hits the in-memory cache. Writing updates the cache and
  /// fire-and-forgets a write to disk so the choice survives reloads.
  static bool get showTutorial => _showTutorial;
  static set showTutorial(bool value) {
    _showTutorial = value;
    _prefs?.setBool(_kShowTutorial, value);
  }
}
