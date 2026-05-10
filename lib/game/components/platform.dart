import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../config.dart';

enum PlatformType { standard, moving, bouncy }

/// Static or dynamic platform.
///
/// Cracks are PURELY VISUAL feedback driven by [impactDamage] (set on landing)
/// and [proximityDamage] (set each frame by the game). Platforms never auto-
/// destroy from cracks alone.
class Platform extends PositionComponent {
  Platform({
    required Vector2 position,
    required double width,
    PlatformType type = PlatformType.standard,
  })  : _type = type,
        _baseX = position.x,
        super(
          position: position,
          size: Vector2(width, GameConfig.platformHeight),
          priority: 0,
        );

  // Stored as nullable + mutable so that hot-reloaded instances (which may
  // temporarily present a null field) fall back to [PlatformType.standard]
  // gracefully, and so the type can be converted at runtime (e.g. after a
  // teleport drops the player on a bouncy that should now behave standard).
  PlatformType? _type;
  PlatformType get type => _type ?? PlatformType.standard;
  void convertToStandard() {
    _type = PlatformType.standard;
  }

  final double _baseX;
  double _movingPhase = 0;

  // Track horizontal position last frame so the game can carry a player
  // standing on a moving platform.
  double previousFrameX = 0;
  double get deltaX => position.x - previousFrameX;

  // Crack visuals
  double impactDamage = 0;
  double proximityDamage = 0;
  static const int _maxCrackLines = 8;
  final List<List<Offset>> _crackLines = [];

  // Paints
  static final _crackPaint = Paint()..style = PaintingStyle.stroke;
  static const Color _crackColor = Color(0xFF0A0A0A);

  @override
  Future<void> onLoad() async {
    _generateCrackLines();
    previousFrameX = position.x;
  }

  void _generateCrackLines() {
    _crackLines.clear();
    final rng = Random();
    for (var i = 0; i < _maxCrackLines; i++) {
      final startX = rng.nextDouble() * size.x;
      final segments = 3 + rng.nextInt(2);
      var x = startX;
      final line = <Offset>[Offset(x, 0)];
      for (var j = 1; j <= segments; j++) {
        final y = (j / segments) * size.y;
        x += (rng.nextDouble() - 0.5) * 9;
        x = x.clamp(0.0, size.x);
        line.add(Offset(x, y));
      }
      _crackLines.add(line);
    }
  }

  void applyImpact(double damage) {
    final clamped = damage.clamp(0.0, 1.0);
    if (clamped > impactDamage) impactDamage = clamped;
  }

  void setProximityDamage(double damage) {
    proximityDamage = damage.clamp(0.0, 1.0);
  }

  double get totalDamage =>
      (impactDamage + proximityDamage).clamp(0.0, 1.0).toDouble();

  @override
  void update(double dt) {
    super.update(dt);
    previousFrameX = position.x;
    if (type == PlatformType.moving) {
      _movingPhase += dt * GameConfig.movingPlatformSpeed;
      position.x = _baseX + sin(_movingPhase) * GameConfig.movingPlatformRange;
    }
  }

  @override
  void render(Canvas canvas) {
    switch (type) {
      case PlatformType.standard:
        _renderAsteroid(canvas);
      case PlatformType.moving:
        _renderHovercraft(canvas);
      case PlatformType.bouncy:
        _renderLaunchPad(canvas);
    }
    _renderCracks(canvas);
  }

  // ---- Standard: white sky cloud (matches design handoff palette) ----
  void _renderAsteroid(Canvas canvas) {
    _renderCloud(
      canvas,
      body: const Color(0xFFFFFFFF),
      mid: const Color(0xFFFFFFFF),
      highlight: const Color(0xFFFFFFFF),
      shadow: const Color(0xFFC8CDD6),
      outline: const Color(0xFF13202D),
    );
  }

  // ---- Moving: warm peach (#FFB890) ----
  void _renderHovercraft(Canvas canvas) {
    _renderCloud(
      canvas,
      body: const Color(0xFFFFB890),
      mid: const Color(0xFFFFCFAB),
      highlight: const Color(0xFFFFE7CE),
      shadow: const Color(0xFFA35C3A),
      outline: const Color(0xFF2A1004),
    );
  }

  // ---- Bouncy: glowing green energy cloud with up-arrows ----
  void _renderLaunchPad(Canvas canvas) {
    // Outer green halo so this platform reads as energetic from a distance.
    // Drawn as a radial gradient ellipse — much cheaper than MaskFilter.blur
    // on Safari/iOS while staying visually similar.
    final w = size.x;
    final h = size.y;
    final glowRect = Rect.fromLTWH(-10, -12, w + 20, h + 22);
    canvas.drawOval(
      glowRect,
      Paint()
        ..shader = const RadialGradient(
          colors: [
            Color(0x9980E89A),
            Color(0x0080E89A),
          ],
          stops: [0.0, 1.0],
        ).createShader(glowRect),
    );
    _renderCloud(
      canvas,
      body: const Color(0xFFA8EDB6),
      mid: const Color(0xFFC4F4CC),
      highlight: const Color(0xFFE3FBC8),
      shadow: const Color(0xFF3D8F4F),
      outline: const Color(0xFF062612),
    );
    // Up-arrows on top so it reads as a booster.
    final arrowFill = Paint()..color = const Color(0xFFF5FFE3);
    final arrowEdge = Paint()
      ..color = const Color(0xFF062612)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeJoin = StrokeJoin.round;
    const arrowCount = 3;
    final cellW = w / arrowCount;
    for (var i = 0; i < arrowCount; i++) {
      final cx = i * cellW + cellW / 2;
      const cy = 8.5;
      final path = Path()
        ..moveTo(cx - 4, cy)
        ..lineTo(cx, cy - 5)
        ..lineTo(cx + 4, cy)
        ..close();
      canvas.drawPath(path, arrowFill);
      canvas.drawPath(path, arrowEdge);
    }
  }

  /// Fortnite-style toon cloud: dark outline silhouette, body fill, then
  /// shadow underside, mid-tone, and a kiss-of-light crown on top of each
  /// puff. The outline is drawn as slightly larger circles BEHIND the body
  /// so only the outer silhouette gets a stroke — interior overlaps stay
  /// clean.
  void _renderCloud(
    Canvas canvas, {
    required Color body,
    required Color mid,
    required Color highlight,
    required Color shadow,
    required Color outline,
  }) {
    final w = size.x;
    final h = size.y;
    // Puff density scales with width so a normal platform reads as a small
    // cloud and the full-width starting platform reads as a continuous
    // cloud bank.
    final puffCount = (w / 18).round().clamp(3, 32);
    final cellW = w / puffCount;
    final puffR = h * 0.90;
    final cy = h * 0.50;

    // 1. Outline silhouette (slightly larger circles in dark stroke colour).
    final outlinePaint = Paint()..color = outline;
    for (var i = 0; i < puffCount; i++) {
      final cx = (i + 0.5) * cellW;
      canvas.drawCircle(Offset(cx, cy), puffR + 1.5, outlinePaint);
    }

    // 2. Body fill (overlapping puffs on top of the outline).
    final bodyPaint = Paint()..color = body;
    for (var i = 0; i < puffCount; i++) {
      final cx = (i + 0.5) * cellW;
      canvas.drawCircle(Offset(cx, cy), puffR, bodyPaint);
    }

    // 3. Underside shadow (lower-half darker tone, no blur — much
    // cheaper on iOS Safari and visually almost identical at this size).
    final shadowPaint = Paint()..color = shadow.withValues(alpha: 0.55);
    for (var i = 0; i < puffCount; i++) {
      final cx = (i + 0.5) * cellW;
      canvas.drawCircle(Offset(cx, h * 0.78), puffR * 0.78, shadowPaint);
    }

    // 4. Mid-tone highlight (upper half).
    final midPaint = Paint()..color = mid;
    for (var i = 0; i < puffCount; i++) {
      final cx = (i + 0.5) * cellW;
      canvas.drawCircle(
        Offset(cx - 0.8, h * 0.32),
        puffR * 0.62,
        midPaint,
      );
    }

    // 5. Bright crown ("kiss of light") on the very top of each puff.
    final crownPaint = Paint()..color = highlight;
    for (var i = 0; i < puffCount; i++) {
      final cx = (i + 0.5) * cellW;
      canvas.drawCircle(
        Offset(cx - 1.4, h * 0.14),
        puffR * 0.34,
        crownPaint,
      );
    }
  }

  void _renderCracks(Canvas canvas) {
    final dmg = totalDamage;
    if (dmg <= 0 || _crackLines.isEmpty) return;
    final visibleCount = (dmg * _crackLines.length).round();
    if (visibleCount <= 0) return;
    final alpha = (0.40 + 0.50 * dmg).clamp(0.0, 0.95);
    _crackPaint.color = _crackColor.withValues(alpha: alpha);
    _crackPaint.strokeWidth = 1.4;
    for (var i = 0; i < visibleCount; i++) {
      final line = _crackLines[i];
      for (var j = 0; j < line.length - 1; j++) {
        canvas.drawLine(line[j], line[j + 1], _crackPaint);
      }
    }
  }

  double get topY => position.y;
  double get leftX => position.x;
  double get rightX => position.x + size.x;

  /// Predicted x of the LEFT edge [futureSeconds] from now. For non-moving
  /// platforms this is just [leftX]. For moving platforms it extrapolates the
  /// sinusoidal motion. Used by the bouncy launcher to aim where the moving
  /// target *will* be, not where it is.
  double predictedLeftX(double futureSeconds) {
    if (type != PlatformType.moving) return position.x;
    final futurePhase =
        _movingPhase + futureSeconds * GameConfig.movingPlatformSpeed;
    return _baseX + sin(futurePhase) * GameConfig.movingPlatformRange;
  }

  double predictedCenterX(double futureSeconds) =>
      predictedLeftX(futureSeconds) + size.x / 2;
}
