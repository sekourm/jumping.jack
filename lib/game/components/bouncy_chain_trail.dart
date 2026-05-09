import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../../state/game_state.dart';
import 'player.dart';

/// Yellow-star particle trail that streams from the player while a bouncy
/// chain is active (≥ 2 consecutive green platforms). Spawn rate scales
/// with chain depth.
class BouncyChainTrail extends Component {
  BouncyChainTrail({required this.player, required this.gameState})
      : super(priority: 9);

  final Player player;
  final GameState gameState;
  final List<_TrailParticle> _particles = [];
  final Random _rng = Random();
  double _spawnAcc = 0;

  static const Color _color = Color(0xFFFFEB3B);

  @override
  void update(double dt) {
    super.update(dt);
    if (gameState.status == GameStatus.playing) {
      final chain = gameState.bouncyChainCount;
      if (chain >= 2) {
        // 18 particles/sec at chain=2, +8 per extra step
        final rate = 18.0 + (chain - 2) * 8;
        _spawnAcc += rate * dt;
        while (_spawnAcc >= 1) {
          _spawnAcc -= 1;
          _particles.add(_TrailParticle.spawn(_rng, player));
        }
      }
    }
    for (final p in _particles) {
      p.update(dt);
    }
    _particles.removeWhere((p) => p.dead);
  }

  @override
  void render(Canvas canvas) {
    for (final p in _particles) {
      p.render(canvas, _color);
    }
  }
}

class _TrailParticle {
  _TrailParticle({
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

  static _TrailParticle spawn(Random rng, Player player) {
    final dx = (rng.nextDouble() - 0.5) * player.size.x;
    final dy = -rng.nextDouble() * player.size.y;
    return _TrailParticle(
      position: Vector2(player.position.x + dx, player.position.y + dy),
      velocity: Vector2(
        (rng.nextDouble() - 0.5) * 30,
        20 + rng.nextDouble() * 30, // slight downward drift
      ),
      size: 2 + rng.nextDouble() * 2.5,
      life: 0.45 + rng.nextDouble() * 0.25,
    );
  }

  void update(double dt) {
    if (dead) return;
    _elapsed += dt;
    velocity.y += 120 * dt; // gentle gravity
    velocity.x *= 0.96;
    position.x += velocity.x * dt;
    position.y += velocity.y * dt;
  }

  void render(Canvas canvas, Color base) {
    if (dead) return;
    final t = (_elapsed / life).clamp(0.0, 1.0);
    final alpha = (1 - t * t) * 0.85;
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(position.x, position.y),
        width: size,
        height: size,
      ),
      Paint()..color = base.withValues(alpha: alpha),
    );
  }
}
