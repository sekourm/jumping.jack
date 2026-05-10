import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../config.dart';

/// A non-local player (other human or bot) rendered as a ghost cube
/// in the local game world. Each remote player gets a fixed X column
/// (slot-based) so they don't overlap, and their Y position is driven
/// by their broadcast score: higher score → higher up in the world.
///
/// Their actual game world is independent — these cubes are a visual
/// abstraction so the local player feels racing alongside everyone else.
class RemotePlayer extends PositionComponent {
  RemotePlayer({
    required this.playerId,
    required this.name,
    required this.slotIndex,
    required this.color,
    required this.initialGroundY,
    required this.viewportWidth,
  }) : super(
          size: Vector2.all(GameConfig.playerSize * 0.85),
          anchor: Anchor.bottomCenter,
          priority: 9,
        );

  final String playerId;
  final String name;
  final int slotIndex;
  final Color color;
  /// World Y at which this player's "score = 0" sits (i.e. the local
  /// ground level when the run started).
  final double initialGroundY;
  final double viewportWidth;

  // Slot → fraction-of-viewport X. The local player sits ~50%, so we
  // distribute remote ghosts on either side and avoid the centre.
  static const _slotXFracs = <double>[0.50, 0.14, 0.28, 0.72, 0.86];

  bool _alive = true;
  double _targetScore = 0;
  double _displayedScore = 0;
  double _hopPhase = 0;
  late TextPainter _namePainter;

  @override
  Future<void> onLoad() async {
    super.onLoad();
    final fx = _slotXFracs[slotIndex.clamp(0, _slotXFracs.length - 1)];
    position.x = viewportWidth * fx;
    position.y = initialGroundY;
    _namePainter = _buildNamePainter(name, color);
  }

  TextPainter _buildNamePainter(String text, Color tint) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.2,
          shadows: [
            Shadow(color: tint.withValues(alpha: 0.7), blurRadius: 6),
            const Shadow(color: Colors.black, blurRadius: 3, offset: Offset(0, 1)),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  void setScore(int score) {
    _targetScore = score.toDouble();
  }

  void setAlive(bool alive) {
    _alive = alive;
  }

  @override
  void update(double dt) {
    super.update(dt);
    // Smooth score ramp toward the broadcast value so big jumps don't
    // teleport the cube around — gives a believable hop animation.
    final diff = _targetScore - _displayedScore;
    _displayedScore += diff * 3.0 * dt;
    if (diff.abs() > 0.5) {
      _hopPhase += dt * 9;
    } else {
      _hopPhase = 0;
    }

    // Position: world Y derived from the broadcast score (1 score pt = 1 px
    // climbed). Up = negative in Flame's coord system.
    final hopOffset = _hopPhase > 0 ? (sin(_hopPhase) * 6).abs() : 0.0;
    position.y = initialGroundY - _displayedScore - hopOffset;
  }

  @override
  void render(Canvas canvas) {
    final w = size.x;
    final h = size.y;
    final cornerR = w * 0.20;

    final alpha = _alive ? 0.65 : 0.18;
    final fillColor = color.withValues(alpha: alpha);
    final outlineColor = Color.lerp(color, Colors.black, 0.55)!
        .withValues(alpha: _alive ? 0.85 : 0.30);

    final body = RRect.fromRectAndRadius(
      size.toRect(),
      Radius.circular(cornerR),
    );

    if (_alive) {
      // Subtle glow so each ghost is readable on the cosmic background.
      canvas.drawRRect(
        body,
        Paint()
          ..color = color.withValues(alpha: 0.20)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }
    canvas.drawRRect(body, Paint()..color = fillColor);
    canvas.drawRRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = outlineColor,
    );

    // Top rim shine.
    if (_alive) {
      canvas.drawRRect(
        RRect.fromLTRBAndCorners(
          1.5,
          1.5,
          w - 1.5,
          h * 0.32,
          topLeft: Radius.circular(cornerR * 0.85),
          topRight: Radius.circular(cornerR * 0.85),
        ),
        Paint()..color = Colors.white.withValues(alpha: 0.35),
      );
    }

    if (!_alive) {
      // Dead marker: an X across the cube.
      final p = Paint()
        ..color = Colors.white.withValues(alpha: 0.55)
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(2, 2), Offset(w - 2, h - 2), p);
      canvas.drawLine(Offset(w - 2, 2), Offset(2, h - 2), p);
    }

    // Name above the cube.
    _namePainter.paint(
      canvas,
      Offset(
        (w - _namePainter.width) / 2,
        -_namePainter.height - 4,
      ),
    );
  }
}
