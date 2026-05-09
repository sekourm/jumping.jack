import 'package:flame/components.dart';

import '../config.dart';

class JumpSolver {
  /// Given player center, finger position (both in world coords) and a charge
  /// progress in [0..1], returns the initial velocity for the jump.
  ///
  /// Direction = from player toward finger (direct mapping). If the finger is
  /// too close, default to vertical-up.
  static Vector2 solve({
    required Vector2 playerPos,
    required Vector2 fingerPos,
    required double chargeProgress,
  }) {
    final delta = fingerPos - playerPos;
    final Vector2 direction;
    if (delta.length < 8) {
      direction = Vector2(0, -1);
    } else {
      direction = delta.normalized();
    }

    final clamped = chargeProgress.clamp(0.0, 1.0);
    final power = GameConfig.minJumpPower +
        (GameConfig.maxJumpPower - GameConfig.minJumpPower) * clamped;
    return direction * power;
  }
}
