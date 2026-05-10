import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../config.dart';
import '../jumping_jack_game.dart';
import 'platform.dart';

/// Player physics:
/// - anchor = bottomCenter so [position.x] is the horizontal center of the
///   feet line and squash/stretch (scale) is symmetric around it.
/// - One-way collision: only lands on platforms when falling and feet cross
///   the platform's top within the same frame.
class Player extends PositionComponent
    with HasGameReference<JumpingJackGame> {
  Player()
      : super(
          size: Vector2.all(GameConfig.playerSize),
          anchor: Anchor.bottomCenter,
          priority: 10,
        );

  Vector2 velocity = Vector2.zero();
  bool grounded = true;
  Platform? lastLandedPlatform;
  // Set by the game during charging — direction the player is aiming the
  // jump. Drives the cube tilt for instinctive aim feedback.
  Vector2? aimDirection;

  // Squash & stretch — _targetScale is what we lerp toward each frame.
  Vector2 _targetScale = Vector2.all(1);

  // Active charge level (0..1) — drives both color and squash intensity.
  double chargeLevel = 0;

  // Visual visibility — set to false on death so the explosion takes over.
  bool visible = true;

  // Kept for any other component that wants to read proximity to the bottom
  // (e.g. dust). Not used by the cube renderer itself anymore.
  double dangerLevel = 0;

  static const Color _chargeMaxColor = Color(0xFFFFFFFF);

  void setDangerTint(double level) {
    dangerLevel = level.clamp(0.0, 1.0);
  }

  void markDead() {
    visible = false;
  }

  @override
  void render(Canvas canvas) {
    if (!visible) return;

    final w = size.x;
    final h = size.y;
    final cornerR = w * 0.20;

    // Charge glow halo (only while charging).
    if (chargeLevel > 0) {
      final glowPaint = Paint()
        ..color = GameConfig.playerColor.withValues(alpha: 0.55 * chargeLevel)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          6 + chargeLevel * 12,
        );
      canvas.drawRRect(
        RRect.fromRectAndRadius(size.toRect(), Radius.circular(cornerR)),
        glowPaint,
      );
    }

    Color base = GameConfig.playerColor;
    if (chargeLevel > 0) {
      base = Color.lerp(base, _chargeMaxColor, chargeLevel * 0.55)!;
      // Past ~85% charge the cube boils over — shift toward an angry
      // red-orange so the maxed-out state reads as dangerously loaded.
      if (chargeLevel > 0.85) {
        final t = ((chargeLevel - 0.85) / 0.15).clamp(0.0, 1.0);
        base = Color.lerp(base, const Color(0xFFFF6B3F), t * 0.50)!;
      }
    }
    final light = Color.lerp(base, Colors.white, 0.32)!;
    final dark = Color.lerp(base, const Color(0xFFB36F00), 0.55)!;

    final body = RRect.fromRectAndRadius(
      size.toRect(),
      Radius.circular(cornerR),
    );

    // Body gradient (light top → base mid → dark bottom).
    canvas.drawRRect(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [light, base, dark],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(size.toRect()),
    );

    // Top rim highlight (Fortnite-style toon shading).
    final rim = RRect.fromLTRBAndCorners(
      1.5,
      1.5,
      w - 1.5,
      h * 0.30,
      topLeft: Radius.circular(cornerR * 0.85),
      topRight: Radius.circular(cornerR * 0.85),
      bottomLeft: const Radius.circular(2),
      bottomRight: const Radius.circular(2),
    );
    canvas.drawRRect(
      rim,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xCCFFFFFF),
            Color(0x00FFFFFF),
          ],
        ).createShader(rim.outerRect),
    );

    // Outline.
    canvas.drawRRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = const Color(0xFF7A4A00),
    );

    // Battle Royale: dangerous spikes under the cube to communicate
    // "this end stomps your opponents".
    if (game.isBattleRoyale) {
      _renderSpikes(canvas, w, h);
    }

    _renderFace(canvas, w, h);
  }

  /// Renders downward-pointing teeth/spikes along the bottom edge of the
  /// cube, brown stroke + lighter fill, to signify the crush hitbox.
  void _renderSpikes(Canvas canvas, double w, double h) {
    const spikeCount = 4;
    final spikeBaseY = h - 0.5;
    final spikeTipY = h + 4.5;
    final cellW = w / spikeCount;
    final fill = Paint()..color = const Color(0xFFFFEFC2);
    final stroke = Paint()
      ..color = const Color(0xFF7A4A00)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeJoin = StrokeJoin.round;
    for (var i = 0; i < spikeCount; i++) {
      final left = i * cellW + cellW * 0.10;
      final right = (i + 1) * cellW - cellW * 0.10;
      final cx = (left + right) / 2;
      final path = Path()
        ..moveTo(left, spikeBaseY)
        ..lineTo(right, spikeBaseY)
        ..lineTo(cx, spikeTipY)
        ..close();
      canvas.drawPath(path, fill);
      canvas.drawPath(path, stroke);
    }
  }

  void _renderFace(Canvas canvas, double w, double h) {
    final eyeY = h * 0.42;
    final eyeOffset = w * 0.20;
    final eyeR = w * 0.13;
    final pupilR = eyeR * 0.55;

    // Pupil offset — looks where the cube is aiming (or up while airborne).
    Offset pupilDelta = Offset.zero;
    if (chargeLevel > 0 && aimDirection != null) {
      final d = aimDirection!;
      pupilDelta = Offset(
        d.x.clamp(-1.0, 1.0) * eyeR * 0.35,
        d.y.clamp(-1.0, 1.0) * eyeR * 0.35,
      );
    } else if (!grounded) {
      pupilDelta = Offset(0, -eyeR * 0.25);
    }

    final eyeWhite = Paint()..color = const Color(0xFFFFFAF0);
    final pupil = Paint()..color = const Color(0xFF1A1410);
    final shine = Paint()..color = Colors.white;

    for (final side in const [-1, 1]) {
      final ex = w / 2 + side * eyeOffset;
      canvas.drawCircle(Offset(ex, eyeY), eyeR, eyeWhite);
      // Slight squint while charging hard — makes effort readable.
      if (chargeLevel > 0.6) {
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset(ex, eyeY - eyeR * 0.7),
            width: eyeR * 2.4,
            height: eyeR * 0.9,
          ),
          Paint()..color = GameConfig.playerColor,
        );
      }
      final pcx = ex + pupilDelta.dx;
      final pcy = eyeY + pupilDelta.dy;
      canvas.drawCircle(Offset(pcx, pcy), pupilR, pupil);
      canvas.drawCircle(
        Offset(pcx - pupilR * 0.30, pcy - pupilR * 0.30),
        pupilR * 0.40,
        shine,
      );
    }

    // Angry V-shape eyebrows at max charge — outer-low, inner-high.
    if (chargeLevel > 0.85) {
      final browPaint = Paint()
        ..color = const Color(0xFF1A1410)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round;
      final browY = eyeY - eyeR * 1.05;
      for (final side in const [-1, 1]) {
        final ex = w / 2 + side * eyeOffset;
        canvas.drawLine(
          Offset(ex - side * eyeR * 0.95, browY + eyeR * 0.40),
          Offset(ex + side * eyeR * 0.65, browY - eyeR * 0.05),
          browPaint,
        );
      }
    }

    _renderMouth(canvas, w, h);
  }

  void _renderMouth(Canvas canvas, double w, double h) {
    final cx = w / 2;
    final mouthY = h * 0.72;
    final mouthW = w * 0.34;
    final dark = const Color(0xFF3B1F00);

    if (chargeLevel > 0.85) {
      // Boiling over: clenched zigzag teeth.
      const segs = 4;
      final segW = mouthW / segs;
      final left = cx - mouthW / 2;
      final path = Path()..moveTo(left, mouthY);
      for (var i = 1; i <= segs; i++) {
        final dx = i * segW;
        final dy = i.isEven ? -2.0 : 2.0;
        path.lineTo(left + dx, mouthY + dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = dark
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    } else if (chargeLevel > 0.3) {
      // Determined: thick horizontal line.
      canvas.drawLine(
        Offset(cx - mouthW / 2, mouthY),
        Offset(cx + mouthW / 2, mouthY),
        Paint()
          ..color = dark
          ..strokeWidth = 2.0
          ..strokeCap = StrokeCap.round,
      );
    } else if (!grounded) {
      // Excited: open "O" (filled circle).
      canvas.drawCircle(
        Offset(cx, mouthY),
        mouthW * 0.30,
        Paint()..color = dark,
      );
    } else {
      // Idle: simple smile (open arc).
      final path = Path()
        ..moveTo(cx - mouthW / 2, mouthY)
        ..quadraticBezierTo(
          cx,
          mouthY + mouthW * 0.42,
          cx + mouthW / 2,
          mouthY,
        );
      canvas.drawPath(
        path,
        Paint()
          ..color = dark
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  void launch(Vector2 initialVelocity) {
    velocity = initialVelocity.clone();
    grounded = false;
    chargeLevel = 0;
    aimDirection = null;
    // Brief vertical stretch on launch — relaxes back during airtime.
    _targetScale = Vector2(0.85, 1.25);
  }

  void applyChargingState(double progress) {
    chargeLevel = progress;
    // Stronger squash than before — the cube visibly compresses to launch.
    final squash = 0.45 * progress;
    _targetScale = Vector2(1 + squash, 1 - squash * 1.3);
  }

  void applyLandingSquash() {
    // Flat squash on landing — relaxes back to neutral.
    _targetScale = Vector2(1.35, 0.55);
  }

  void resetVisuals() {
    _targetScale = Vector2.all(1);
    scale = Vector2.all(1);
    angle = 0;
    aimDirection = null;
    dangerLevel = 0;
    chargeLevel = 0;
    visible = true;
    lastLandedPlatform = null;
  }

  void tickVisuals(double dt) {
    final t = (GameConfig.squashLerpRate * dt).clamp(0.0, 1.0);
    scale = scale + (_targetScale - scale) * t;

    // Tilt toward aim direction while charging — pivots around bottom-center
    // (the anchor) so the cube's "feet" stay planted.
    final targetAngle = _computeTiltAngle();
    angle = angle + (targetAngle - angle) * t;
    // While airborne and not actively launching, drift back to neutral.
    if (!grounded) {
      _targetScale = Vector2(
        _targetScale.x + (1 - _targetScale.x) * 0.05,
        _targetScale.y + (1 - _targetScale.y) * 0.05,
      );
    } else {
      _targetScale = Vector2(
        _targetScale.x + (1 - _targetScale.x) * 0.10,
        _targetScale.y + (1 - _targetScale.y) * 0.10,
      );
    }
  }

  /// Returns the platform we collided with this frame, or null. The game
  /// inspects the platform's [PlatformType] to decide what to do (regular
  /// landing, bouncy auto-launch, trap death...).
  Platform? stepAndCollide(double dt, List<Platform> platforms) {
    if (grounded) return null;

    velocity.y += GameConfig.gravity * dt;
    final prevFeetY = position.y;
    position += velocity * dt;
    final feetY = position.y;

    if (velocity.y <= 0) return null;

    final halfW = size.x / 2;
    final left = position.x - halfW;
    final right = position.x + halfW;
    for (final p in platforms) {
      final overlapsX = right > p.leftX && left < p.rightX;
      final crossedTop = prevFeetY <= p.topY && feetY >= p.topY;
      if (overlapsX && crossedTop) {
        position.y = p.topY;
        velocity = Vector2.zero();
        grounded = true;
        lastLandedPlatform = p;
        return p;
      }
    }
    return null;
  }

  /// Center point used as origin for trajectory + jump direction.
  Vector2 get centerWorld =>
      Vector2(position.x, position.y - size.y / 2);

  // Up to ~22° in either direction while aiming. Scales sub-linearly with the
  // angle from vertical so straight-up = no tilt, side jumps lean visibly.
  static const double _maxTilt = pi / 8;
  double _computeTiltAngle() {
    if (chargeLevel <= 0 || aimDirection == null) return 0;
    final dir = aimDirection!;
    if (!dir.x.isFinite || !dir.y.isFinite) return 0;
    // angle from straight-up (positive = clockwise / right).
    final ang = atan2(dir.x, -dir.y);
    if (!ang.isFinite) return 0;
    return (ang * 0.45).clamp(-_maxTilt, _maxTilt);
  }
}
