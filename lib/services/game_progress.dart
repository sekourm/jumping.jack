import 'package:flutter/foundation.dart';

/// Global, lightweight notifier describing how far the player has climbed
/// in the current run. Used by the cosmic side-band background to show a
/// planet progression (Earth → Moon → Mars → ...) even though that widget
/// lives outside the game's widget subtree.
class GameProgress {
  static final ValueNotifier<int> platforms = ValueNotifier<int>(0);

  /// Bumps the highest-reached count if the new value is higher.
  static void update(int p) {
    if (p > platforms.value) {
      platforms.value = p;
    }
  }

  static void reset() {
    platforms.value = 0;
  }
}
