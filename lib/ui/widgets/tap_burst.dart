import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/jack_design.dart';

/// Wraps a small interactive widget (icon button, chip, toggle…) and emits
/// a yellow + purple particle burst at the tap location. Used to give
/// every clickable surface in the UI the same juicy "click feedback" as
/// the [FortniteButton]. Drops the work to the next frame so it stacks
/// naturally on top of the wrapped widget.
class TapBurst extends StatefulWidget {
  const TapBurst({super.key, required this.child});
  final Widget child;

  @override
  State<TapBurst> createState() => _TapBurstState();
}

class _TapBurstState extends State<TapBurst>
    with SingleTickerProviderStateMixin {
  final List<_Particle> _particles = [];
  final Random _rng = Random();
  Ticker? _ticker;
  Duration _lastTick = Duration.zero;
  // Wall-clock anchor — used to detect that the Ticker was muted (route
  // pushed offstage) and flush stale particles instead of resuming a
  // stale animation when the user comes back.
  DateTime _lastWall = DateTime.now();

  void _ensureTicker() {
    _ticker ??= createTicker(_onTick);
    if (!_ticker!.isActive) _ticker!.start();
  }

  void _onTick(Duration elapsed) {
    final now = DateTime.now();
    final wallDt = now.difference(_lastWall).inMicroseconds / 1e6;
    _lastWall = now;
    if (wallDt > 0.5) {
      _particles.clear();
      _ticker?.stop();
      _lastTick = Duration.zero;
      if (mounted) setState(() {});
      return;
    }
    if (_lastTick == Duration.zero) {
      _lastTick = elapsed;
      return;
    }
    final dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (_particles.isEmpty) {
      _ticker?.stop();
      _lastTick = Duration.zero;
      return;
    }
    for (final p in _particles) {
      p.life -= dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.vy += 320 * dt;
      p.vx *= 0.96;
    }
    _particles.removeWhere((p) => p.life <= 0);
    if (mounted) setState(() {});
  }

  void _spawn(Offset position) {
    const count = 10;
    for (var i = 0; i < count; i++) {
      final angle = (i / count) * 2 * pi + _rng.nextDouble() * 0.4;
      final speed = 100 + _rng.nextDouble() * 160;
      final isPurple = i.isEven;
      _particles.add(_Particle(
        x: position.dx,
        y: position.dy,
        vx: cos(angle) * speed,
        vy: sin(angle) * speed - 60,
        radius: 2.2 + _rng.nextDouble() * 2.2,
        life: 0.40 + _rng.nextDouble() * 0.25,
        maxLife: 0.65,
        color: isPurple ? JackDesign.purpleHi : JackDesign.yellow,
      ));
    }
    _ensureTicker();
    _lastTick = Duration.zero;
    _lastWall = DateTime.now();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (e) => _spawn(e.localPosition),
          child: widget.child,
        ),
        if (_particles.isNotEmpty)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _BurstPainter(_particles)),
            ),
          ),
      ],
    );
  }
}

class _Particle {
  _Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.radius,
    required this.life,
    required this.maxLife,
    required this.color,
  });
  double x, y, vx, vy, radius, life;
  final double maxLife;
  final Color color;
}

class _BurstPainter extends CustomPainter {
  _BurstPainter(this.particles);
  final List<_Particle> particles;

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final t = (p.life / p.maxLife).clamp(0.0, 1.0);
      final r = p.radius * (0.6 + 0.4 * t);
      canvas.drawCircle(
        Offset(p.x, p.y),
        r * 2.0,
        Paint()
          ..color = p.color.withValues(alpha: 0.45 * t)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      canvas.drawCircle(
        Offset(p.x, p.y),
        r,
        Paint()..color = p.color.withValues(alpha: 0.95 * t),
      );
      canvas.drawCircle(
        Offset(p.x, p.y),
        r * 0.45,
        Paint()..color = Colors.white.withValues(alpha: t),
      );
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => true;
}
