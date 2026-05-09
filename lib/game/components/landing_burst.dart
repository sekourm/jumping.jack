import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../config.dart';

/// A short-lived burst of small particles spawned at the player's feet on
/// landing. Particles fly outward, fall under gravity, and fade out. The whole
/// component removes itself once all particles are gone.
class LandingBurst extends Component {
  LandingBurst({required this.origin, this.count = 7})
      : super(priority: 5);

  final Vector2 origin;
  final int count;
  static final _rng = Random();

  late final List<_Particle> _particles;

  @override
  Future<void> onLoad() async {
    _particles = List.generate(count, (_) => _Particle.spawn(origin, _rng));
  }

  @override
  void update(double dt) {
    super.update(dt);
    for (final p in _particles) {
      p.update(dt);
    }
    if (_particles.every((p) => p.dead)) {
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    for (final p in _particles) {
      p.render(canvas);
    }
  }
}

class _Particle {
  _Particle({
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

  static _Particle spawn(Vector2 origin, Random rng) {
    final angle = -pi + rng.nextDouble() * pi; // upper hemisphere
    final speed = 80 + rng.nextDouble() * 100;
    return _Particle(
      position: origin.clone(),
      velocity: Vector2(cos(angle) * speed, sin(angle) * speed),
      size: 2 + rng.nextDouble() * 2.5,
      life: 0.4 + rng.nextDouble() * 0.2,
    );
  }

  void update(double dt) {
    if (dead) return;
    _elapsed += dt;
    velocity.y += GameConfig.gravity * 0.7 * dt;
    position.x += velocity.x * dt;
    position.y += velocity.y * dt;
  }

  void render(Canvas canvas) {
    if (dead) return;
    final t = (_elapsed / life).clamp(0.0, 1.0);
    final alpha = (1 - t) * 0.85;
    final paint = Paint()
      ..color = GameConfig.platformEdgeColor.withValues(alpha: alpha);
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
