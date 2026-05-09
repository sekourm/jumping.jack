import 'dart:math';

import 'package:flutter/material.dart';

/// Static cosmic backdrop used by the home and death screens. Mirrors the
/// in-game [CosmicGameBackground]: 3-stop sky gradient, soft nebula glow
/// blobs (subtle, not competing with the foreground), and dot stars. No
/// time-based animation.
///
/// [platforms] picks the stage: 0 → Earth, 5 → Moon, 15 → Mars, 30 → Jupiter,
/// 50 → Saturn, 100+ → Nebula.
class CosmicBackground extends StatelessWidget {
  CosmicBackground({super.key, this.platforms = 0, int starCount = 130})
      : _stars = _generateStars(starCount),
        _nebulas = _generateNebulas();

  final int platforms;
  final List<_Star> _stars;
  final List<_Nebula> _nebulas;

  static List<_Star> _generateStars(int count) {
    final rng = Random(0xC05);
    return List<_Star>.generate(count, (_) {
      return _Star(
        x: rng.nextDouble(),
        y: rng.nextDouble(),
        size: 0.5 + rng.nextDouble() * 1.6,
        phase: rng.nextDouble() * 2 * pi,
      );
    });
  }

  static List<_Nebula> _generateNebulas() {
    final rng = Random(0xC05 + 1);
    return List<_Nebula>.generate(5, (_) {
      return _Nebula(
        x: rng.nextDouble(),
        y: rng.nextDouble(),
        radius: 0.18 + rng.nextDouble() * 0.30,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _CosmicPainter(
        platforms: platforms,
        stars: _stars,
        nebulas: _nebulas,
      ),
      size: Size.infinite,
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

class _Nebula {
  const _Nebula({
    required this.x,
    required this.y,
    required this.radius,
  });
  final double x, y, radius;
}

class _StageColors {
  const _StageColors(
    this.start,
    this.end,
    this.top,
    this.mid,
    this.bottom,
    this.accent,
  );
  final int start, end;
  final Color top, mid, bottom, accent;
}

const _stages = <_StageColors>[
  _StageColors(
    0, 5,
    Color(0xFF173A5C),
    Color(0xFF071A33),
    Color(0xFF030914),
    Color(0xFF7CC0FF),
  ),
  _StageColors(
    5, 15,
    Color(0xFF22222A),
    Color(0xFF101015),
    Color(0xFF050508),
    Color(0xFFEFEFEF),
  ),
  _StageColors(
    15, 30,
    Color(0xFF3D140A),
    Color(0xFF1B0805),
    Color(0xFF080302),
    Color(0xFFFF8A5C),
  ),
  _StageColors(
    30, 50,
    Color(0xFF35200F),
    Color(0xFF170D06),
    Color(0xFF080402),
    Color(0xFFFFC788),
  ),
  _StageColors(
    50, 100,
    Color(0xFF2E2510),
    Color(0xFF141008),
    Color(0xFF060503),
    Color(0xFFFFE7A8),
  ),
  _StageColors(
    100, 1 << 30,
    Color(0xFF260C44),
    Color(0xFF110325),
    Color(0xFF04010B),
    Color(0xFFD06BFF),
  ),
];

class _CosmicPainter extends CustomPainter {
  _CosmicPainter({
    required this.platforms,
    required this.stars,
    required this.nebulas,
  });

  final int platforms;
  final List<_Star> stars;
  final List<_Nebula> nebulas;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stage = _stages.firstWhere(
      (s) => platforms >= s.start && platforms < s.end,
      orElse: () => _stages.last,
    );

    final rect = Rect.fromLTWH(0, 0, w, h);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [stage.top, stage.mid, stage.bottom],
          stops: const [0.0, 0.30, 1.0],
        ).createShader(rect),
    );

    // Soft nebula glow via RadialGradient (faster than MaskFilter.blur on
    // iOS Safari).
    for (final n in nebulas) {
      final cx = n.x * w;
      final cy = n.y * h;
      final r = n.radius * min(w, h) * 1.6;
      final rect = Rect.fromCircle(center: Offset(cx, cy), radius: r);
      canvas.drawCircle(
        Offset(cx, cy),
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [
              stage.accent.withValues(alpha: 0.10),
              stage.accent.withValues(alpha: 0.0),
            ],
            stops: const [0.0, 1.0],
          ).createShader(rect),
      );
    }

    final paint = Paint();
    for (final s in stars) {
      final cx = s.x * w;
      final cy = s.y * h;
      final brightness = 0.30 + 0.40 * (sin(s.phase) * 0.5 + 0.5);
      paint.color = Colors.white.withValues(alpha: brightness * 0.65);
      canvas.drawCircle(Offset(cx, cy), s.size, paint);
    }
  }

  @override
  bool shouldRepaint(_CosmicPainter old) => old.platforms != platforms;
}
