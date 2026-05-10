import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../../ui/widgets/jack_gem.dart';
import '../config.dart';
import 'platform.dart';

/// Common base for in-air pickups that the player grabs by passing through.
/// Each subclass picks a [GemKind] from the design palette so the in-game
/// gem matches the static UI gems (death summary, etc.).
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

  final Platform? anchorPlatform;
  final double anchorOffsetX;

  bool collected = false;
  double _pulse = 0;

  /// The shape used to render this pickup. Mirrors `components.jsx`.
  GemKind get gemKind;

  /// Loot-tier glow color painted as a wider aura behind the gem. Defaults
  /// to the gem's own halo, but subclasses can override (e.g. legendary
  /// gold halo for the teleport pickup).
  Color get rarityHalo => kGemPalettes[gemKind]!.halo;

  /// Color used for the floating pop-up label spawned when this pickup is
  /// collected. Reads from the gem's lit "light" channel so the text is
  /// visually tied to the gem the player just grabbed.
  Color get labelColor => kGemPalettes[gemKind]!.light;

  @override
  void update(double dt) {
    super.update(dt);
    _pulse += dt;
    if (anchorPlatform != null) {
      position.x = anchorPlatform!.position.x + anchorOffsetX;
    }
  }

  double pulseScale({double speed = 4, double amplitude = 0.10}) =>
      1 + sin(_pulse * speed) * amplitude;

  /// Optional extra rarity aura behind the gem (kept thin so the gem reads
  /// as the design intends).
  void paintRarityAura(Canvas canvas, {double scale = 1.0}) {
    final cx = size.x / 2;
    final cy = size.y / 2;
    final r = size.x * 0.65 * scale;
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()
        ..color = rarityHalo.withValues(alpha: 0.32)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.45),
    );
  }

  @override
  void render(Canvas canvas) {
    paintRarityAura(canvas);
    paintJackGem(
      canvas,
      Size(size.x, size.y),
      gemKind,
      drawHalo: false,
      pulseScale: pulseScale(),
      outlineWidth: 1.6,
    );
  }
}

/// Gold star — flat score boost. Common loot tier.
class StarPickup extends Pickup {
  StarPickup({
    required super.position,
    super.anchorPlatform,
    super.anchorOffsetX,
  });

  @override
  GemKind get gemKind => GemKind.star;
}

/// Cyan crystal — slows the camera for a few seconds. Uncommon tier.
class CrystalPickup extends Pickup {
  CrystalPickup({
    required super.position,
    super.anchorPlatform,
    super.anchorOffsetX,
  }) : super(size: GameConfig.pickupRadius * 2.4);

  @override
  GemKind get gemKind => GemKind.crystal;
}

/// Green eye — re-enables the trajectory preview for the next few jumps.
/// Rare tier.
class VisionPickup extends Pickup {
  VisionPickup({
    required super.position,
    super.anchorPlatform,
    super.anchorOffsetX,
  }) : super(size: GameConfig.pickupRadius * 2.4);

  @override
  GemKind get gemKind => GemKind.vision;
}

/// Purple target — teleports the player to the highest visible platform.
/// Legendary tier — gold halo.
class TeleportPickup extends Pickup {
  TeleportPickup({
    required super.position,
    super.anchorPlatform,
    super.anchorOffsetX,
  }) : super(size: GameConfig.pickupRadius * 2.4);

  @override
  GemKind get gemKind => GemKind.teleport;

  @override
  Color get rarityHalo => const Color(0xFFFFB300);
}

/// Pink heart — pauses the combo timer for a few seconds. Epic tier.
class HeartPickup extends Pickup {
  HeartPickup({
    required super.position,
    super.anchorPlatform,
    super.anchorOffsetX,
  }) : super(size: GameConfig.pickupRadius * 2.2);

  @override
  GemKind get gemKind => GemKind.heart;
}
