import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../config.dart';
import 'platform.dart';

/// Common base for in-air pickups that the player grabs by passing through.
/// Subclasses define their visual + on-collect effect (handled by the game).
abstract class Pickup extends PositionComponent {
  Pickup({
    required super.position,
    this.anchorPlatform,
    this.anchorOffsetX = 0,
    double size = GameConfig.pickupRadius * 2,
  }) : super(
          size: Vector2.all(size),
          anchor: Anchor.center,
          priority: 12,
        );

  /// If set, the pickup tracks this platform's horizontal motion. Used so
  /// pickups stay glued above moving platforms.
  final Platform? anchorPlatform;
  final double anchorOffsetX; // x-offset from the platform's left edge

  bool collected = false;
  double _pulse = 0;

  /// Loot-tier glow color painted as an aura behind the gem.
  Color get rarityHalo;

  @override
  void update(double dt) {
    super.update(dt);
    _pulse += dt;
    if (anchorPlatform != null) {
      position.x = anchorPlatform!.position.x + anchorOffsetX;
    }
  }

  double pulseScale({double speed = 4, double amplitude = 0.12}) =>
      1 + sin(_pulse * speed) * amplitude;

  /// Paints a Fortnite-style loot aura behind the gem. Subclasses should
  /// call this from [render] before drawing their gem shape.
  void paintRarityAura(Canvas canvas, {double scale = 1.0}) {
    final cx = size.x / 2;
    final cy = size.y / 2;
    final r = size.x * 0.7 * scale;
    canvas.drawCircle(
      Offset(cx, cy),
      r * 1.05,
      Paint()
        ..color = rarityHalo.withValues(alpha: 0.35)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.45),
    );
    canvas.drawCircle(
      Offset(cx, cy),
      r * 0.65,
      Paint()
        ..color = rarityHalo.withValues(alpha: 0.45)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.20),
    );
  }
}

/// Yellow diamond — base score boost. (Common loot tier.)
class StarPickup extends Pickup {
  StarPickup({
    required super.position,
    super.anchorPlatform,
    super.anchorOffsetX,
  });

  static const Color _fill = Color(0xFFFFEB3B);
  static const Color _core = Color(0xFFFFFDE0);
  static const Color _outline = Color(0xFF8A6700);

  @override
  Color get rarityHalo => const Color(0xFFFFFFFF);

  @override
  void render(Canvas canvas) {
    paintRarityAura(canvas);
    final scale = pulseScale();
    canvas.save();
    canvas.translate(size.x / 2, size.y / 2);
    canvas.scale(scale);
    canvas.rotate(pi / 4);
    final r = size.x / 2;
    final rect = Rect.fromLTWH(-r, -r, size.x, size.y);
    canvas.drawRect(rect, Paint()..color = _fill);
    canvas.drawRect(
      Rect.fromLTWH(-r * 0.45, -r * 0.45, size.x * 0.45, size.y * 0.45),
      Paint()..color = _core,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = _outline,
    );
    canvas.restore();
  }
}

/// Cyan diamond — slows the camera for a few seconds. (Uncommon tier.)
class CrystalPickup extends Pickup {
  CrystalPickup({
    required super.position,
    super.anchorPlatform,
    super.anchorOffsetX,
  }) : super(size: GameConfig.pickupRadius * 2.4);

  static const Color _fill = Color(0xFF4FC3F7);
  static const Color _edge = Color(0xFF00ACC1);
  static const Color _core = Color(0xFFE0F7FA);
  static const Color _outline = Color(0xFF003B4D);

  @override
  Color get rarityHalo => const Color(0xFF42E07A);

  @override
  void render(Canvas canvas) {
    paintRarityAura(canvas);
    final scale = pulseScale(speed: 3, amplitude: 0.14);
    canvas.save();
    canvas.translate(size.x / 2, size.y / 2);
    canvas.scale(scale);
    canvas.rotate(pi / 4);
    final r = size.x / 2;
    final outer = Rect.fromLTWH(-r, -r, size.x, size.y);
    canvas.drawRect(outer, Paint()..color = _fill);
    canvas.drawRect(
      Rect.fromLTWH(-r * 0.4, -r * 0.4, size.x * 0.4, size.y * 0.4),
      Paint()..color = _core,
    );
    canvas.drawRect(
      outer,
      Paint()
        ..color = _edge
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    canvas.drawRect(
      outer,
      Paint()
        ..color = _outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
    canvas.restore();
  }
}

/// Orange three-dot row — re-enables the trajectory preview for the next
/// few jumps after it has naturally faded out. (Rare tier.)
class VisionPickup extends Pickup {
  VisionPickup({
    required super.position,
    super.anchorPlatform,
    super.anchorOffsetX,
  }) : super(size: GameConfig.pickupRadius * 2.4);

  static const Color _fill = Color(0xFFFFA64C);
  static const Color _core = Color(0xFFFFEFC2);
  static const Color _outline = Color(0xFF6B3000);

  @override
  Color get rarityHalo => const Color(0xFF4FA3FF);

  @override
  void render(Canvas canvas) {
    paintRarityAura(canvas);
    final scale = pulseScale(speed: 4.0, amplitude: 0.12);
    canvas.save();
    canvas.translate(size.x / 2, size.y / 2);
    canvas.scale(scale);

    final r = size.x / 2;
    final dotR = r * 0.26;
    final fillPaint = Paint()..color = _fill;
    final corePaint = Paint()..color = _core;
    final outlinePaint = Paint()
      ..color = _outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    for (var i = -1; i <= 1; i++) {
      final cx = i * r * 0.60;
      canvas.drawCircle(Offset(cx, 0), dotR, fillPaint);
      canvas.drawCircle(Offset(cx, 0), dotR * 0.45, corePaint);
      canvas.drawCircle(Offset(cx, 0), dotR, outlinePaint);
    }
    canvas.restore();
  }
}

/// Purple up-arrow — teleports the player to the highest visible platform.
/// (Legendary tier — gold halo.)
class TeleportPickup extends Pickup {
  TeleportPickup({
    required super.position,
    super.anchorPlatform,
    super.anchorOffsetX,
  }) : super(size: GameConfig.pickupRadius * 2.4);

  static const Color _fill = Color(0xFFB14BFF);
  static const Color _edge = Color(0xFFE6BBFF);
  static const Color _outline = Color(0xFF3D0F66);

  @override
  Color get rarityHalo => const Color(0xFFFFB300);

  @override
  void render(Canvas canvas) {
    paintRarityAura(canvas, scale: 1.15);
    final scale = pulseScale(speed: 4.5, amplitude: 0.14);
    canvas.save();
    canvas.translate(size.x / 2, size.y / 2);
    canvas.scale(scale);
    final r = size.x / 2;
    final paint = Paint()..color = _fill;
    final edgePaint = Paint()
      ..color = _edge
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final outlinePaint = Paint()
      ..color = _outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final headPath = Path()
      ..moveTo(0, -r)
      ..lineTo(-r * 0.85, -r * 0.05)
      ..lineTo(-r * 0.35, -r * 0.05)
      ..lineTo(-r * 0.35, r * 0.85)
      ..lineTo(r * 0.35, r * 0.85)
      ..lineTo(r * 0.35, -r * 0.05)
      ..lineTo(r * 0.85, -r * 0.05)
      ..close();
    canvas.drawPath(headPath, paint);
    canvas.drawPath(headPath, edgePaint);
    canvas.drawPath(headPath, outlinePaint);
    canvas.restore();
  }
}

/// Pink heart — pauses the combo timer for a few seconds. (Epic tier.)
class HeartPickup extends Pickup {
  HeartPickup({
    required super.position,
    super.anchorPlatform,
    super.anchorOffsetX,
  }) : super(size: GameConfig.pickupRadius * 2.2);

  static const Color _fill = Color(0xFFFF6E94);
  static const Color _core = Color(0xFFFFD0DD);
  static const Color _outline = Color(0xFF7A1735);

  @override
  Color get rarityHalo => const Color(0xFFB14BFF);

  @override
  void render(Canvas canvas) {
    paintRarityAura(canvas);
    final scale = pulseScale(speed: 5, amplitude: 0.12);
    canvas.save();
    canvas.translate(size.x / 2, size.y / 2);
    canvas.scale(scale);
    final r = size.x / 2;
    final paint = Paint()..color = _fill;
    final corePaint = Paint()..color = _core;
    final outlinePaint = Paint()
      ..color = _outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeJoin = StrokeJoin.round;

    final path = Path()
      ..addOval(Rect.fromCircle(
        center: Offset(-r * 0.5, -r * 0.15),
        radius: r * 0.55,
      ))
      ..addOval(Rect.fromCircle(
        center: Offset(r * 0.5, -r * 0.15),
        radius: r * 0.55,
      ))
      ..moveTo(-r * 0.95, 0)
      ..lineTo(0, r * 0.95)
      ..lineTo(r * 0.95, 0)
      ..close();
    canvas.drawPath(path, paint);
    canvas.drawCircle(Offset(-r * 0.45, -r * 0.25), r * 0.18, corePaint);
    canvas.drawPath(path, outlinePaint);
    canvas.restore();
  }
}
