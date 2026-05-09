import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../game/config.dart';

/// Animated background of slow-rising yellow particles. Used on the menu and
/// death screens so the static UI shares the same energy/particle language
/// as the game itself.
class ParticleBackground extends StatefulWidget {
  const ParticleBackground({
    super.key,
    this.particleCount = 60,
    this.color = GameConfig.playerColor,
  });

  final int particleCount;
  final Color color;

  @override
  State<ParticleBackground> createState() => _ParticleBackgroundState();
}

class _ParticleBackgroundState extends State<ParticleBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final List<_BgParticle> _particles = [];
  final Random _rng = Random();
  Duration _lastTick = Duration.zero;
  Size _size = Size.zero;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )
      ..addListener(_onTick)
      ..repeat();
  }

  void _onTick() {
    final now = _controller.lastElapsedDuration ?? Duration.zero;
    final dt = (now - _lastTick).inMicroseconds / 1e6;
    _lastTick = now;
    if (dt <= 0 || dt > 0.5) return;
    if (_size.width <= 0 || _size.height <= 0) return;

    // Top up to target count.
    while (_particles.length < widget.particleCount) {
      _particles.add(_BgParticle.spawn(_rng, _size, fresh: false));
    }

    for (final p in _particles) {
      p.update(dt);
    }
    _particles.removeWhere((p) {
      if (p.dead) return true;
      if (p.position.dy < -20) return true;
      return false;
    });

    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _size = Size(constraints.maxWidth, constraints.maxHeight);
        return IgnorePointer(
          child: CustomPaint(
            painter: _BgPainter(
              particles: List.unmodifiable(_particles),
              color: widget.color,
            ),
            size: _size,
          ),
        );
      },
    );
  }
}

class _BgParticle {
  _BgParticle({
    required this.position,
    required this.velocity,
    required this.size,
    required this.life,
  });

  Offset position;
  Offset velocity;
  double size;
  double life;
  double elapsed = 0;

  bool get dead => elapsed >= life;

  static _BgParticle spawn(Random rng, Size canvas, {bool fresh = true}) {
    final startY = fresh
        ? canvas.height + rng.nextDouble() * 30 // off-screen below
        : rng.nextDouble() * canvas.height;     // first frame: spread evenly
    return _BgParticle(
      position: Offset(rng.nextDouble() * canvas.width, startY),
      velocity: Offset(
        (rng.nextDouble() - 0.5) * 6,
        -8 - rng.nextDouble() * 10,
      ),
      size: 1.4 + rng.nextDouble() * 2.4,
      life: 6 + rng.nextDouble() * 6,
    );
  }

  void update(double dt) {
    elapsed += dt;
    position += velocity * dt;
  }
}

class _BgPainter extends CustomPainter {
  _BgPainter({required this.particles, required this.color});

  final List<_BgParticle> particles;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final t = (p.elapsed / p.life).clamp(0.0, 1.0);
      // Fade in for first 15%, hold, fade out last 30%.
      double a;
      if (t < 0.15) {
        a = t / 0.15;
      } else if (t > 0.7) {
        a = 1 - (t - 0.7) / 0.3;
      } else {
        a = 1.0;
      }
      a *= 0.55; // overall dim so it's a backdrop, not a wall
      if (a <= 0) continue;

      final paint = Paint()..color = color.withValues(alpha: a);
      final glowPaint = Paint()
        ..color = color.withValues(alpha: a * 0.4)
        ..maskFilter = const ui.MaskFilter.blur(BlurStyle.normal, 3);

      final rect = Rect.fromCenter(
        center: p.position,
        width: p.size,
        height: p.size,
      );
      canvas.drawRect(rect.inflate(2), glowPaint);
      canvas.drawRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(_BgPainter old) => true;
}
