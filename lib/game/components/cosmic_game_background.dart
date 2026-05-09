import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../../services/game_progress.dart';

/// Procedural cosmic backdrop. Static (no per-frame motion to avoid the
/// "reading in a car" effect) — only the stage colour smoothly interpolates
/// when the player crosses a stage threshold. Visual language matches the
/// Fortnite-toon platforms: cell-shaded cloud silhouettes in the distance,
/// dot stars + cross sparkles, and a 3-stop vertical sky gradient.
class CosmicGameBackground extends PositionComponent with HasGameReference {
  CosmicGameBackground() : super(priority: -1000);

  static const int _starCount = 130;
  static const int _nebulaCount = 5;

  late final List<_Star> _stars;
  late final List<_Nebula> _nebulas;

  double _stageFloat = 0;

  @override
  Future<void> onLoad() async {
    super.onLoad();
    size = game.size;
    final rng = Random(0xC05);

    _stars = List<_Star>.generate(_starCount, (_) {
      return _Star(
        x: rng.nextDouble(),
        y: rng.nextDouble(),
        size: 0.5 + rng.nextDouble() * 1.6,
        phase: rng.nextDouble() * 2 * pi,
      );
    });

    _nebulas = List<_Nebula>.generate(_nebulaCount, (_) {
      return _Nebula(
        x: rng.nextDouble(),
        y: rng.nextDouble(),
        radius: 0.18 + rng.nextDouble() * 0.30,
      );
    });

    _stageFloat = _stageIndexFor(GameProgress.platforms.value).toDouble();
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    this.size = size;
  }

  @override
  void update(double dt) {
    super.update(dt);
    final target = _stageIndexFor(GameProgress.platforms.value).toDouble();
    final diff = target - _stageFloat;
    _stageFloat += diff * 1.4 * dt;
  }

  @override
  void render(Canvas canvas) {
    final w = size.x;
    final h = size.y;

    final stageA = _stageFloat.floor().clamp(0, _stages.length - 1);
    final stageB = (stageA + 1).clamp(0, _stages.length - 1);
    final t = (_stageFloat - stageA).clamp(0.0, 1.0);
    final a = _stages[stageA];
    final b = _stages[stageB];
    final top = Color.lerp(a.top, b.top, t)!;
    final mid = Color.lerp(a.mid, b.mid, t)!;
    final bottom = Color.lerp(a.bottom, b.bottom, t)!;
    final accent = Color.lerp(a.accent, b.accent, t)!;

    _paintGradient(canvas, w, h, top, mid, bottom);
    _paintNebulas(canvas, w, h, accent);
    _paintStars(canvas, w, h);
  }

  void _paintGradient(
    Canvas canvas,
    double w,
    double h,
    Color top,
    Color mid,
    Color bottom,
  ) {
    final rect = Rect.fromLTWH(0, 0, w, h);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [top, mid, bottom],
          stops: const [0.0, 0.30, 1.0],
        ).createShader(rect),
    );
  }

  void _paintNebulas(Canvas canvas, double w, double h, Color accent) {
    // Use a RadialGradient instead of MaskFilter.blur — same soft look but
    // dramatically cheaper on Safari/iOS where maskFilter blurs are slow.
    for (final n in _nebulas) {
      final cx = n.x * w;
      final cy = n.y * h;
      final r = n.radius * min(w, h) * 1.6; // expanded to absorb the fade
      final rect = Rect.fromCircle(center: Offset(cx, cy), radius: r);
      canvas.drawCircle(
        Offset(cx, cy),
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [
              accent.withValues(alpha: 0.10),
              accent.withValues(alpha: 0.0),
            ],
            stops: const [0.0, 1.0],
          ).createShader(rect),
      );
    }
  }

  void _paintStars(Canvas canvas, double w, double h) {
    final paint = Paint();
    for (final s in _stars) {
      final cx = s.x * w;
      final cy = s.y * h;
      final brightness = 0.30 + 0.40 * (sin(s.phase) * 0.5 + 0.5);
      paint.color = Colors.white.withValues(alpha: brightness * 0.65);
      canvas.drawCircle(Offset(cx, cy), s.size, paint);
    }
  }

  int _stageIndexFor(int platforms) {
    for (var i = 0; i < _stages.length; i++) {
      final s = _stages[i];
      if (platforms >= s.start && platforms < s.end) return i;
    }
    return _stages.length - 1;
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
  final int start;
  final int end; // exclusive
  final Color top;
  final Color mid;
  final Color bottom;
  final Color accent; // drives the cloud tint
}

const _stages = <_StageColors>[
  // Earth — atmospheric blue fading to deep ocean.
  _StageColors(
    0,
    5,
    Color(0xFF173A5C),
    Color(0xFF071A33),
    Color(0xFF030914),
    Color(0xFF7CC0FF),
  ),
  // Moon — cool gray space.
  _StageColors(
    5,
    15,
    Color(0xFF22222A),
    Color(0xFF101015),
    Color(0xFF050508),
    Color(0xFFEFEFEF),
  ),
  // Mars — rust red dust.
  _StageColors(
    15,
    30,
    Color(0xFF3D140A),
    Color(0xFF1B0805),
    Color(0xFF080302),
    Color(0xFFFF8A5C),
  ),
  // Jupiter — cream brown gas-giant glow.
  _StageColors(
    30,
    50,
    Color(0xFF35200F),
    Color(0xFF170D06),
    Color(0xFF080402),
    Color(0xFFFFC788),
  ),
  // Saturn — pale amber.
  _StageColors(
    50,
    100,
    Color(0xFF2E2510),
    Color(0xFF141008),
    Color(0xFF060503),
    Color(0xFFFFE7A8),
  ),
  // Nebula — vibrant purple cosmic.
  _StageColors(
    100,
    1 << 30,
    Color(0xFF260C44),
    Color(0xFF110325),
    Color(0xFF04010B),
    Color(0xFFD06BFF),
  ),
];
