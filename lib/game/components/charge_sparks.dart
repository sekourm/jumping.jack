import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../../state/game_state.dart';
import 'player.dart';

/// Small "energy" sparks that rise from the player while charging. The spawn
/// rate and speed scale with [GameState.chargeProgress] — barely visible at
/// low charge, intense burst at full charge.
class ChargeSparks extends Component {
  ChargeSparks({required this.player, required this.gameState})
      : super(priority: 22);

  final Player player;
  final GameState gameState;
  final List<_Spark> _sparks = [];
  final Random _rng = Random();
  double _spawnTimer = 0;

  static const Color _color = Color(0xFFFFEB3B);

  @override
  void update(double dt) {
    super.update(dt);

    if (gameState.charging) {
      _spawnTimer += dt;
      // Spawn interval shrinks with charge: 50ms at 0% → 14ms at 100%.
      final interval = 0.05 - 0.036 * gameState.chargeProgress;
      while (_spawnTimer >= interval) {
        _spawnTimer -= interval;
        _sparks.add(_Spark.spawn(
          _rng,
          Vector2(player.position.x, player.position.y - player.size.y * 0.5),
          player.size.x,
          gameState.chargeProgress,
        ));
      }
    }

    for (final s in _sparks) {
      s.update(dt);
    }
    _sparks.removeWhere((s) => s.dead);
  }

  @override
  void render(Canvas canvas) {
    for (final s in _sparks) {
      s.render(canvas, _color);
    }
  }
}

class _Spark {
  _Spark({
    required this.position,
    required this.velocity,
    required this.size,
    required this.life,
  });

  final Vector2 position;
  final Vector2 velocity;
  final double size;
  final double life;
  double _elapsed = 0;

  bool get dead => _elapsed >= life;

  static _Spark spawn(
    Random rng,
    Vector2 origin,
    double playerSize,
    double progress,
  ) {
    final dx = (rng.nextDouble() - 0.5) * playerSize * 0.85;
    final dy = (rng.nextDouble() - 0.5) * playerSize * 0.4;
    final speed = 80 + rng.nextDouble() * 50 + progress * 90;
    return _Spark(
      position: origin + Vector2(dx, dy),
      velocity: Vector2((rng.nextDouble() - 0.5) * 40, -speed),
      size: 1.5 + rng.nextDouble() * (1.5 + progress),
      life: 0.30 + rng.nextDouble() * 0.20,
    );
  }

  void update(double dt) {
    if (dead) return;
    _elapsed += dt;
    velocity.y += 220 * dt; // gentle drag-down (less than full gravity)
    velocity.x *= 0.94;
    position.x += velocity.x * dt;
    position.y += velocity.y * dt;
  }

  void render(Canvas canvas, Color baseColor) {
    if (dead) return;
    final t = (_elapsed / life).clamp(0.0, 1.0);
    final alpha = (1 - t) * 0.95;
    final paint = Paint()..color = baseColor.withValues(alpha: alpha);
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(position.x, position.y),
        width: size,
        height: size,
      ),
      paint,
    );
  }
}
