import 'dart:math';

import 'package:flame/components.dart';

import '../config.dart';
import 'pickups.dart';
import 'platform.dart';
import 'platform_explosion.dart';

/// Procedural infinite world. Holds platforms, the player, and effects.
/// Platforms are spawned upward as the camera rises and culled below.
///
/// Coordinate system: y grows downward (Flame default). "Higher" means smaller y.
class GameWorld extends PositionComponent {
  GameWorld({
    required this.viewportWidth,
    this.canSpawnVision,
    int? seed,
    this.randomPickups = true,
  }) : _rng = Random(seed);

  double viewportWidth;
  final Random _rng;
  final List<Platform> platforms = [];
  final List<Pickup> pickups = [];
  /// Returning false suppresses Vision pickups (e.g. while the player
  /// already has a Vision boost active — no point handing out another).
  /// Defaults to "always allow" when not set.
  final bool Function()? canSpawnVision;
  /// Set to false in Battle Royale: the match has a single shared pickup
  /// spawned manually by [JumpingJackGame] instead of the per-platform
  /// random spawner.
  final bool randomPickups;
  double _highestY = 0; // y of last spawned (highest) platform
  int _spawnIndex = 0;
  int _platformsSinceLastPickup = 0;

  /// Wipes existing platforms and spawns enough to cover the initial viewport.
  Future<void> initializePlatforms({
    required double viewportWidth,
    required double viewportHeight,
  }) async {
    this.viewportWidth = viewportWidth;
    for (final p in platforms) {
      p.removeFromParent();
    }
    platforms.clear();
    for (final p in pickups) {
      p.removeFromParent();
    }
    pickups.clear();
    _spawnIndex = 0;
    _platformsSinceLastPickup = 0;

    _highestY = viewportHeight - 40;
    final start = Platform(
      position: Vector2(0, _highestY),
      width: viewportWidth,
    );
    platforms.add(start);
    add(start);

    while (_highestY > 0) {
      _spawnNext();
    }
  }

  /// Make sure platforms exist up to [targetTopWorldY] (inclusive).
  void ensureCovered(double targetTopWorldY) {
    while (_highestY > targetTopWorldY) {
      _spawnNext();
    }
  }

  /// Remove platforms + pickups below [cullWorldY] (off-screen below).
  void cleanupBelow(double cullWorldY) {
    final platToRemove = <Platform>[];
    for (final p in platforms) {
      if (p.topY > cullWorldY) platToRemove.add(p);
    }
    for (final p in platToRemove) {
      platforms.remove(p);
      p.removeFromParent();
    }
    final pickToRemove = <Pickup>[];
    for (final p in pickups) {
      if (p.position.y > cullWorldY) pickToRemove.add(p);
    }
    for (final p in pickToRemove) {
      pickups.remove(p);
      p.removeFromParent();
    }
  }

  void removePickup(Pickup p) {
    if (pickups.remove(p)) {
      p.removeFromParent();
    }
  }

  /// Removes a platform with a particle explosion effect.
  /// Also bumps impact damage to 1.0 first so cracks render fully on the
  /// final frame before particles take over. Any pickup anchored to this
  /// platform is destroyed with it.
  void explodeAndRemove(Platform p) {
    if (!platforms.remove(p)) return;
    final orphans = pickups.where((pk) => pk.anchorPlatform == p).toList();
    for (final pk in orphans) {
      pickups.remove(pk);
      pk.removeFromParent();
    }
    p.applyImpact(1.0);
    add(PlatformExplosion(
      origin: p.position.clone(),
      size: p.size.clone(),
    ));
    p.removeFromParent();
  }

  /// 0 = no variation, 1 = full variation (spacing in [base, base + maxExtra]).
  double _difficulty(int index) {
    final beyondEasy = index - GameConfig.platformEasyCount;
    if (beyondEasy <= 0) return 0;
    return (beyondEasy / GameConfig.platformVariationRamp).clamp(0.0, 1.0);
  }

  void _spawnNext() {
    _spawnIndex++;
    final difficulty = _difficulty(_spawnIndex);
    final dy = GameConfig.platformBaseSpacingY +
        difficulty * _rng.nextDouble() * GameConfig.platformMaxExtraSpacingY;
    final newY = _highestY - dy;

    final type = _pickType();
    final w = GameConfig.platformWidth;

    // Reachability envelope of a max-power jump.
    final v = GameConfig.maxJumpPower;
    final peak = v * v / (2 * GameConfig.gravity);
    final shrink = GameConfig.gravity / (2 * v * v);
    final dxMax = dy < peak
        ? sqrt((peak - dy) / shrink) * GameConfig.platformReachabilitySafety
        : 0.0;

    final prev = platforms.last;
    final prevCenterX = prev.position.x + prev.size.x / 2;

    // Moving platforms occupy a wider effective span — keep their base
    // position centered enough that the moving range stays on-screen.
    final movingPad = type == PlatformType.moving
        ? GameConfig.movingPlatformRange
        : 0.0;

    final lowCenter = max(w / 2 + movingPad, prevCenterX - dxMax);
    final highCenter =
        min(viewportWidth - w / 2 - movingPad, prevCenterX + dxMax);

    final centerX = highCenter > lowCenter
        ? lowCenter + _rng.nextDouble() * (highCenter - lowCenter)
        : prevCenterX.clamp(w / 2 + movingPad, viewportWidth - w / 2 - movingPad);

    final p = Platform(
      position: Vector2(centerX - w / 2, newY),
      width: w,
      type: type,
    );
    platforms.add(p);
    add(p);
    _highestY = newY;

    _maybeSpawnPickupBetween(prev, p);
  }

  /// Maybe spawns a pickup ON the destination platform [to] (hovering just
  /// above its top surface) if the cooldown has elapsed and the dice rolls
  /// right. The pickup is pinned to the platform so it follows movement.
  void _maybeSpawnPickupBetween(Platform from, Platform to) {
    if (!randomPickups) return; // BR mode: single shared pickup, no random.
    _platformsSinceLastPickup++;
    if (_platformsSinceLastPickup < GameConfig.pickupMinPlatformsBetween) {
      return;
    }
    if (_rng.nextDouble() >= GameConfig.pickupSpawnChance) return;

    _platformsSinceLastPickup = 0;

    // Pickup hovers right above the platform's top surface, centered.
    final offsetX = to.size.x / 2;
    final px = to.position.x + offsetX;
    final py = to.topY - 16;
    final pos = Vector2(px, py);

    final roll = _rng.nextDouble();
    final tHeart = GameConfig.pickupRatioHeart;
    final tCrystal = tHeart + GameConfig.pickupRatioCrystal;
    final tTp = tCrystal + GameConfig.pickupRatioTeleport;
    final tVision = tTp + GameConfig.pickupRatioVision;
    Pickup pickup;
    if (roll < tHeart) {
      pickup = HeartPickup(
        position: pos,
        anchorPlatform: to,
        anchorOffsetX: offsetX,
      );
    } else if (roll < tCrystal) {
      pickup = CrystalPickup(
        position: pos,
        anchorPlatform: to,
        anchorOffsetX: offsetX,
      );
    } else if (roll < tTp) {
      pickup = TeleportPickup(
        position: pos,
        anchorPlatform: to,
        anchorOffsetX: offsetX,
      );
    } else if (roll < tVision) {
      // Skip the Vision pickup if the player already has the boost active —
      // fall back to a Star so the slot still rewards the player.
      if (canSpawnVision == null || canSpawnVision!()) {
        pickup = VisionPickup(
          position: pos,
          anchorPlatform: to,
          anchorOffsetX: offsetX,
        );
      } else {
        pickup = StarPickup(
          position: pos,
          anchorPlatform: to,
          anchorOffsetX: offsetX,
        );
      }
    } else {
      pickup = StarPickup(
        position: pos,
        anchorPlatform: to,
        anchorOffsetX: offsetX,
      );
    }
    pickups.add(pickup);
    add(pickup);
  }

  PlatformType _pickType() {
    if (_spawnIndex <= GameConfig.firstSafePlatforms) {
      return PlatformType.standard;
    }
    // Prevent two moving platforms in a row.
    final lastType = platforms.isNotEmpty ? platforms.last.type : null;
    final weights = <(PlatformType, double)>[
      (PlatformType.standard, GameConfig.weightStandard),
      if (lastType != PlatformType.moving)
        (PlatformType.moving, GameConfig.weightMoving),
      (PlatformType.bouncy, GameConfig.weightBouncy),
    ];
    final total = weights.fold<double>(0, (a, w) => a + w.$2);
    var roll = _rng.nextDouble() * total;
    for (final (t, w) in weights) {
      roll -= w;
      if (roll <= 0) return t;
    }
    return PlatformType.standard;
  }
}
