import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../config.dart';

/// Bursts a platform into a shower of small chunks. Chunks fly outward,
/// fall under gravity, and fade out. The component removes itself when
/// every chunk has decayed.
class PlatformExplosion extends Component {
  PlatformExplosion({
    required Vector2 origin, // top-left of the platform in world coords
    required Vector2 size, // platform size
    Color color = GameConfig.platformColor,
  })  : _origin = origin.clone(),
        _size = size.clone(),
        _color = color,
        super(priority: 6);

  final Vector2 _origin;
  final Vector2 _size;
  final Color _color;
  late final List<_Chunk> _chunks;
  static final _rng = Random();

  @override
  Future<void> onLoad() async {
    // More chunks for wider platforms.
    final count = (10 + _size.x / 14).round().clamp(10, 28);
    _chunks = List.generate(count, (_) {
      final px = _origin.x + _rng.nextDouble() * _size.x;
      final py = _origin.y + _rng.nextDouble() * _size.y;

      // Outward random burst, slight upward bias.
      final speed = 90 + _rng.nextDouble() * 130;
      final angle = _rng.nextDouble() * 2 * pi;
      final vx = cos(angle) * speed;
      final vy = sin(angle) * speed - 60;

      return _Chunk(
        position: Vector2(px, py),
        velocity: Vector2(vx, vy),
        size: 2.5 + _rng.nextDouble() * 3,
        life: 0.45 + _rng.nextDouble() * 0.25,
      );
    });
  }

  @override
  void update(double dt) {
    super.update(dt);
    for (final c in _chunks) {
      c.update(dt);
    }
    if (_chunks.every((c) => c.dead)) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    for (final c in _chunks) {
      c.render(canvas, _color);
    }
  }
}

class _Chunk {
  _Chunk({
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

  void update(double dt) {
    if (dead) return;
    _elapsed += dt;
    velocity.y += GameConfig.gravity * 0.85 * dt;
    velocity.x *= 0.97;
    position.x += velocity.x * dt;
    position.y += velocity.y * dt;
  }

  void render(Canvas canvas, Color base) {
    if (dead) return;
    final t = (_elapsed / life).clamp(0.0, 1.0);
    final alpha = (1 - t * t) * 0.95;
    final paint = Paint()..color = base.withValues(alpha: alpha);
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
