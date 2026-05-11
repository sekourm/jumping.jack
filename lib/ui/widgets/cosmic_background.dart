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
    // 60 s loop. Long enough that the vertical star drift reads as a slow
    // calm float (rather than a distracting scroll), short enough that the
    // floating-point precision of the modulo wrap stays clean over the
    // wallclock lifetime of the home screen.
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 60),
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
          drift: _ctrl.value,
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
    required this.drift,
  });
  final JackStage stage;
  final List<_Star> stars;
  /// 0..1 wrap-around progress over the controller period. Drives both
  /// the upward parallax scroll of the star field and (rescaled by
  /// [_twinkleCyclesPerLoop]) the per-star alpha flicker.
  final double drift;

  /// Sin-wave cycles per controller loop used for star twinkle. The
  /// controller runs at 60 s; 15 cycles ≈ one twinkle per 4 s, which
  /// matches the previous standalone twinkle controller.
  static const double _twinkleCyclesPerLoop = 15.0;

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
      // Parallax drift: bigger stars travel faster (read as closer) for a
      // gentle depth illusion. Speed range 0.3..1.0 of one full screen
      // height per controller loop. `%` in Dart is always non-negative
      // for a positive divisor, so the subtraction wraps cleanly into
      // [0, 1) regardless of the drift / size combination.
      final speed = 0.3 + ((s.size - 0.6) / 1.6).clamp(0.0, 1.0) * 0.7;
      final yProgress = (s.y - drift * speed) % 1.0;
      final cx = s.x * w;
      final cy = yProgress * h;
      // Twinkle: sin wave with per-star phase offset. Rescaled because
      // the controller now loops every 60 s instead of 4 s.
      final flicker = 0.5 +
          0.5 *
              sin(drift * 2 * pi * _twinkleCyclesPerLoop + s.phase * 4);
      final brightness = 0.30 + 0.55 * flicker;
      paint.color = Colors.white.withValues(alpha: brightness);
      canvas.drawCircle(Offset(cx, cy), s.size, paint);
    }

    // (Removed) Saturn ring hint — the two flat concentric ellipses read
    // as an ugly disc layered on top of the sky gradient rather than as
    // planetary rings. The saturn stage still reads through its tinted
    // gradient + nebula blobs alone.
  }

  @override
  bool shouldRepaint(_CosmicPainter old) =>
      old.stage != stage || old.drift != drift;
}
