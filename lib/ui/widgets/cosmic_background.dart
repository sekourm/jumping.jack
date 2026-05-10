import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/jack_design.dart';

/// Static cosmic backdrop. Renders a 3-stop sky gradient, soft nebula glow
/// blobs, deterministic dot stars (with optional twinkle), and a Saturn ring
/// hint for the saturn stage.
///
/// Two ways to drive the visuals:
/// 1. [stage] — pick a specific [JackStage] (used by the home screen / menu).
/// 2. [platforms] — legacy progression-based mode (in-game), maps the
///    platform count to a stage roughly equivalent to the original code.
class CosmicBackground extends StatefulWidget {
  CosmicBackground({
    super.key,
    this.platforms = 0,
    this.stage,
    int starCount = 80,
  })  : _stars = _generateStars(starCount, stage ?? _stageFromPlatforms(platforms));

  final int platforms;
  final JackStage? stage;
  final List<_Star> _stars;

  static JackStage _stageFromPlatforms(int p) {
    if (p < 5) return JackStage.earth;
    if (p < 15) return JackStage.moon;
    if (p < 30) return JackStage.mars;
    if (p < 50) return JackStage.jupiter;
    if (p < 100) return JackStage.saturn;
    return JackStage.nebula;
  }

  static List<_Star> _generateStars(int count, JackStage stage) {
    final seed = stage.toString().codeUnitAt(7); // deterministic per-stage
    final rng = Random(seed);
    return List<_Star>.generate(count, (_) {
      return _Star(
        x: rng.nextDouble(),
        y: rng.nextDouble(),
        size: 0.6 + rng.nextDouble() * 1.6,
        phase: rng.nextDouble() * 2 * pi,
      );
    });
  }

  @override
  State<CosmicBackground> createState() => _CosmicBackgroundState();
}

class _CosmicBackgroundState extends State<CosmicBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stage = widget.stage ??
        CosmicBackground._stageFromPlatforms(widget.platforms);
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) => CustomPaint(
        painter: _CosmicPainter(
          stage: stage,
          stars: widget._stars,
          twinkle: _ctrl.value,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _Star {
  const _Star({
    required this.x,
    required this.y,
    required this.size,
    required this.phase,
  });
  final double x, y, size, phase;
}

class _CosmicPainter extends CustomPainter {
  _CosmicPainter({
    required this.stage,
    required this.stars,
    required this.twinkle,
  });
  final JackStage stage;
  final List<_Star> stars;
  final double twinkle;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final g = stage.gradient;

    final rect = Rect.fromLTWH(0, 0, w, h);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [g.top, g.mid, g.bottom],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(rect),
    );

    for (final blob in g.blobs) {
      final cx = blob.x * w;
      final cy = blob.y * h;
      final r = blob.size * min(w, h) * 0.9;
      final br = Rect.fromCircle(center: Offset(cx, cy), radius: r);
      canvas.drawCircle(
        Offset(cx, cy),
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [
              blob.color.withValues(alpha: 0.40),
              blob.color.withValues(alpha: 0.0),
            ],
            stops: const [0.0, 1.0],
          ).createShader(br),
      );
    }

    final paint = Paint();
    for (final s in stars) {
      final cx = s.x * w;
      final cy = s.y * h;
      // Twinkle: sin wave with per-star phase offset.
      final flicker = 0.5 + 0.5 * sin(twinkle * 2 * pi + s.phase * 4);
      final brightness = 0.30 + 0.55 * flicker;
      paint.color = Colors.white.withValues(alpha: brightness);
      canvas.drawCircle(Offset(cx, cy), s.size, paint);
    }

    // Saturn ring hint — two concentric ellipses on the right side.
    if (stage == JackStage.saturn) {
      final ringRect = Rect.fromCenter(
        center: Offset(w * 0.85, h * 0.18),
        width: w * 0.55,
        height: h * 0.10,
      );
      final ringPaint = Paint()
        ..color = JackDesign.yellow.withValues(alpha: 0.40)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawOval(ringRect, ringPaint);
      final ringRect2 = ringRect.deflate(min(w, h) * 0.04);
      canvas.drawOval(
        ringRect2,
        Paint()
          ..color = JackDesign.yellowHi.withValues(alpha: 0.40)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(_CosmicPainter old) =>
      old.stage != stage || old.twinkle != twinkle;
}
