import 'dart:math';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../services/audio_manager.dart';
import '../services/battle_royale_service.dart';
import '../services/game_progress.dart';
import '../services/preferences.dart';
import '../state/death_reason.dart';
import '../state/game_state.dart';
import 'components/bot_player.dart';
import 'components/bouncy_chain_trail.dart';
import 'components/charge_aim_arrow.dart';
import 'components/charge_sparks.dart';
import 'components/cosmic_game_background.dart';
import 'components/floating_score_text.dart';
import 'components/game_world.dart';
import 'components/landing_burst.dart';
import 'components/pickups.dart';
import 'components/platform.dart';
import 'components/platform_explosion.dart';
import 'components/player.dart';
import 'config.dart';
import 'input/trajectory_preview.dart';
import 'physics/jump_solver.dart';

/// Orchestrates the game.
///
/// World coords: y grows downward. The world is scrolled by translating
/// [GameWorld.position] in screen space (no [CameraComponent]) so input events
/// stay easy to convert: worldPos = screenPos - world.position.
class JumpingJackGame extends FlameGame with DragCallbacks {
  JumpingJackGame({
    required this.gameState,
    this.isBattleRoyale = false,
  });

  final GameState gameState;
  final bool isBattleRoyale;
  int _lastBroadcastScore = -1;
  double _myPosBroadcastTimer = 0;
  final Map<String, BotPlayer> _bots = {};
  CrystalPickup? _brPickup;

  // Slot → ghost colour for remote players (matches the BR HUD palette).
  static const _slotColors = <Color>[
    GameConfig.playerColor,
    Color(0xFF6CD8FF),
    Color(0xFFFF6E94),
    Color(0xFF7AE091),
    Color(0xFFFFA64C),
  ];

  late final GameWorld gameWorld;
  late final Player player;
  late final TrajectoryPreview preview;

  // Charging state
  bool _charging = false;
  double _chargeMs = 0;
  Vector2? _fingerScreenPos;

  // Captured at reset time, used as the reference for "height above start".
  double _initialPlayerFeetY = 0;

  // Camera & shake (kept separate so shake doesn't drift the camera)
  double _cameraY = 0;

  /// Public accessor used by [RemotePlayer] ghosts to clamp their Y so
  /// they don't drift above the player's visible (already-generated) world.
  double get cameraY => _cameraY;
  double _shakeRemaining = 0;
  double _shakeAmplitude = 0;
  final Random _shakeRng = Random();

  // ---- Dynamic letterbox (BR only) ----
  // The whole match runs in a fixed virtual world (480×800). At render
  // time we scale + letterbox that world into whatever the local device
  // actually has, so every client sees the same content with bars on
  // sides/top depending on aspect ratio.
  double _worldScale = 1.0;
  double _letterboxX = 0;
  double _letterboxY = 0;

  double get _worldWidth => isBattleRoyale
      ? GameConfig.brVirtualViewportWidth
      : size.x;
  double get _worldHeight => isBattleRoyale
      ? GameConfig.brVirtualViewportHeight
      : size.y;

  void _recomputeViewport() {
    if (isBattleRoyale) {
      final scaleX = size.x / GameConfig.brVirtualViewportWidth;
      final scaleY = size.y / GameConfig.brVirtualViewportHeight;
      _worldScale = scaleX < scaleY ? scaleX : scaleY;
      _letterboxX =
          (size.x - GameConfig.brVirtualViewportWidth * _worldScale) / 2;
      _letterboxY =
          (size.y - GameConfig.brVirtualViewportHeight * _worldScale) / 2;
    } else {
      _worldScale = 1.0;
      _letterboxX = 0;
      _letterboxY = 0;
    }
  }

  // Score captured at the start of the current jump, to compute the gain
  // when the player lands.
  int _scoreAtJumpStart = 0;

  // Counts wall bounces during the current jump — credited as a bonus on
  // landing, reset on release.
  int _wallBouncesThisJump = 0;

  // Tracks consecutive bouncy-platform landings — increments on each green,
  // resets on a normal landing or death. Drives both the score popup and
  // the BouncyChainTrail particle effect.
  int _bouncyChainCount = 0;

  // Captured on release to detect "comeback" jumps where the player ends
  // up lower than where they launched from.
  double _jumpStartY = 0;

  @override
  Color backgroundColor() => GameConfig.bgColor;

  @override
  Future<void> onLoad() async {
    add(CosmicGameBackground());
    // In Battle Royale, seed the procedural world with a hash of the room
    // id so every client in the same match generates identical platforms.
    int? worldSeed;
    if (isBattleRoyale) {
      final rid = BattleRoyaleService.instance.roomId;
      if (rid != null) worldSeed = rid.hashCode;
    }
    // In BR mode every client uses the same virtual viewport for world
    // generation so platforms end up at identical coordinates regardless
    // of the actual device screen size.
    gameWorld = GameWorld(
      viewportWidth: isBattleRoyale
          ? GameConfig.brVirtualViewportWidth
          : size.x,
      canSpawnVision: () => gameState.trajectoryBoostJumps == 0,
      seed: worldSeed,
      randomPickups: !isBattleRoyale,
    );
    add(gameWorld);
    _recomputeViewport();

    player = Player();
    gameWorld.add(player);

    preview = TrajectoryPreview();
    gameWorld.add(preview);

    gameWorld.add(ChargeSparks(player: player, gameState: gameState));
    gameWorld.add(ChargeAimArrow(player: player, gameState: gameState));
    gameWorld.add(BouncyChainTrail(player: player, gameState: gameState));

    // Audio: preload SFX and start the in-game music loop.
    await AudioManager.preload();
    AudioManager.startGameMusic();

    await _reset();

    if (isBattleRoyale) {
      BattleRoyaleService.instance.addListener(_syncRemotePlayers);
      _syncRemotePlayers();
      _spawnBrPickup();
    }
  }

  /// Spawns the single shared Battle Royale pickup at a deterministic
  /// platform so every client agrees on its position. Always a Crystal
  /// (slow time) — when collected, the slow effect is applied on every
  /// client via [_syncRemotePlayers] reacting to the BR service flag.
  void _spawnBrPickup() {
    if (gameWorld.platforms.length < 5) return;
    final seed = BattleRoyaleService.instance.roomId?.hashCode ?? 0;
    final idxRange = (gameWorld.platforms.length - 4).clamp(1, 99);
    final platformIdx = 4 + (seed.abs() % idxRange);
    if (platformIdx >= gameWorld.platforms.length) return;
    final anchor = gameWorld.platforms[platformIdx];
    final offsetX = anchor.size.x / 2;
    final pos = Vector2(anchor.position.x + offsetX, anchor.topY - 16);
    final pickup = CrystalPickup(
      position: pos,
      anchorPlatform: anchor,
      anchorOffsetX: offsetX,
    );
    gameWorld.pickups.add(pickup);
    gameWorld.add(pickup);
    _brPickup = pickup;
  }

  /// Adds / updates the visual representation of every other player and
  /// pauses the engine when the match has been decided. Both bots and
  /// remote humans are rendered as cubes that lerp to broadcast world
  /// coordinates so they look like real opponents jumping on the shared
  /// platforms.
  void _syncRemotePlayers() {
    final svc = BattleRoyaleService.instance;
    if (svc.phase == BrPhase.finished && !paused) {
      pauseEngine();
    }
    // Apply the global slow-time effect on every client the moment any
    // player (or bot) grabs the shared BR pickup.
    if (svc.brPickupCollected && _brPickup != null) {
      final p = _brPickup!;
      _brPickup = null;
      gameWorld.removePickup(p);
      gameWorld.add(FloatingScoreText(
        origin: Vector2(p.position.x, p.position.y - 24),
        label: 'RALENTI',
        color: const Color(0xFF4FC3F7),
        fontSize: 20,
        life: 1.4,
        floatHeight: 70,
      ));
      gameState.activateSlowTime(GameConfig.slowTimeDuration);
      AudioManager.pickupCrystal();
    }
    final me = Preferences.playerId;
    final iAmLeader = svc.isLeader;
    for (final p in svc.players) {
      if (p.playerId == me) continue;
      final color =
          _slotColors[p.slotIndex.clamp(0, _slotColors.length - 1)];

      var cube = _bots[p.playerId];
      if (cube == null) {
        final startX = _spawnXForSlot(p.slotIndex);
        if (p.isBot) {
          // Bots: AI mode for the leader, remote (lerp) for everyone else.
          final seed = (svc.roomId?.hashCode ?? 0) ^ p.slotIndex;
          final rng = Random(seed);
          final skill = 0.65 + rng.nextDouble() * 0.85;
          final lifespan = 22 + rng.nextDouble() * 70;
          cube = BotPlayer(
            playerId: p.playerId,
            name: p.name,
            slotIndex: p.slotIndex,
            color: color,
            skill: skill,
            lifespanSec: lifespan,
            control: iAmLeader ? BotControl.ai : BotControl.remote,
            profile: _profileForSlot(p.slotIndex),
            startPos: Vector2(startX, _initialPlayerFeetY),
          );
        } else {
          // Remote human: always lerp to their broadcast world position so
          // they appear jumping on the shared platforms.
          cube = BotPlayer(
            playerId: p.playerId,
            name: p.name,
            slotIndex: p.slotIndex,
            color: color,
            skill: 1.0,
            lifespanSec: 9999,
            control: BotControl.remote,
            profile: BotProfile.bondisseur,
            startPos: Vector2(startX, _initialPlayerFeetY),
          );
        }
        _bots[p.playerId] = cube;
        gameWorld.add(cube);
      }
    }
  }

  /// Only the leader checks bot deaths against the camera — single source
  /// of truth. Other clients receive the broadcast and align their state.
  void _checkBotDeaths() {
    if (!isBattleRoyale) return;
    if (_bots.isEmpty) return;
    if (!BattleRoyaleService.instance.isLeader) return;
    final caughtY = _worldHeight - _cameraY + GameConfig.playerSize;
    for (final bot in _bots.values) {
      if (!bot.alive) continue;
      if (bot.position.y >= caughtY) {
        bot.killByCamera();
      }
    }
  }

  /// Leader-only: did any of our bots run through the BR pickup this frame?
  /// If so we notify the service which broadcasts so every client removes
  /// it locally and applies the slow-time effect uniformly.
  void _checkBotPickupCollision() {
    if (!isBattleRoyale) return;
    final pickup = _brPickup;
    if (pickup == null) return;
    if (!BattleRoyaleService.instance.isLeader) return;
    for (final bot in _bots.values) {
      if (!bot.alive) continue;
      final dx = bot.position.x - pickup.position.x;
      final dy = (bot.position.y - bot.size.y / 2) - pickup.position.y;
      final reach = bot.size.x * 0.5 + GameConfig.pickupRadius;
      if (dx * dx + dy * dy <= reach * reach) {
        BattleRoyaleService.instance.notifyBrPickupCollected();
        return;
      }
    }
  }

  /// Spread the bots' starting X across the viewport so they don't all sit
  /// on top of the player.
  double _spawnXForSlot(int slot) {
    const fracs = [0.50, 0.20, 0.35, 0.65, 0.80];
    final f = fracs[slot.clamp(0, fracs.length - 1)];
    return gameWorld.viewportWidth * f;
  }

  /// Bot personality assigned per slot — gives the room four distinct
  /// playstyles to compete with.
  BotProfile _profileForSlot(int slot) {
    const profiles = [
      BotProfile.bondisseur, // never assigned (slot 0 is always the local player)
      BotProfile.bondisseur,
      BotProfile.prudent,
      BotProfile.impatient,
      BotProfile.acrobate,
    ];
    return profiles[slot.clamp(0, profiles.length - 1)];
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (isMounted) {
      gameWorld.viewportWidth = isBattleRoyale
          ? GameConfig.brVirtualViewportWidth
          : size.x;
      _recomputeViewport();
    }
  }

  Future<void> restart() async {
    await _reset();
    AudioManager.startGameMusic();
  }

  Future<void> _reset() async {
    await gameWorld.initializePlatforms(
      viewportWidth: isBattleRoyale
          ? GameConfig.brVirtualViewportWidth
          : size.x,
      viewportHeight: isBattleRoyale
          ? GameConfig.brVirtualViewportHeight
          : size.y,
    );
    final start = gameWorld.platforms.first;
    player.position = Vector2(
      start.position.x + start.size.x / 2,
      start.topY,
    );
    player.velocity = Vector2.zero();
    player.grounded = true;
    player.resetVisuals();
    // Pin the player to the start platform so that releasing from it triggers
    // the explosion just like any other platform.
    player.lastLandedPlatform = start;
    // Place the camera so the player appears at the configured screen ratio
    // from the very first frame (no jump needed to "kick" the camera).
    _cameraY = -(player.position.y - _desiredPlayerScreenY);
    _shakeRemaining = 0;
    _shakeAmplitude = 0;
    _applyCameraToWorld();

    _initialPlayerFeetY = player.position.y;
    _scoreAtJumpStart = 0;
    _wallBouncesThisJump = 0;
    _bouncyChainCount = 0;
    _jumpStartY = player.position.y;
    _resetCharging();

    gameState.start();
    GameProgress.reset();
  }

  // ---------------- update loop ----------------

  @override
  void update(double dt) {
    super.update(dt);

    final isSpectating =
        isBattleRoyale && BattleRoyaleService.instance.spectator;
    final isPlaying = gameState.status == GameStatus.playing;

    // Frozen state: not playing AND not spectating → nothing to do.
    if (!isPlaying && !isSpectating) return;

    if (!isPlaying && isSpectating) {
      // Spectator mode after the local player has died: skip every
      // player-physics path but keep the world alive so the camera follows
      // the surviving climbers.
      _riseCamera(dt);
      _updateShake(dt);
      _applyCameraToWorld();
      _spawnAndCull();
      _updateDangerLevel();
      _updatePlatformProximity();
      _checkBotDeaths();
      _checkBotPickupCollision();
      gameState.tick(dt);
      return;
    }

    if (_charging) {
      _chargeMs = (_chargeMs + dt * 1000).clamp(0.0, GameConfig.maxChargeMs);
      gameState.updateCharge(charging: true, progress: _chargeProgress);
      player.applyChargingState(_chargeProgress);
      _updatePreview();
    }

    // Carry the player along moving platforms before physics this frame.
    if (player.grounded && player.lastLandedPlatform != null) {
      final p = player.lastLandedPlatform!;
      if (p.type == PlatformType.moving) {
        player.position.x += p.deltaX;
      }
    }

    final landingSpeed = player.velocity.y;
    final landedOn = player.stepAndCollide(dt, gameWorld.platforms);
    if (landedOn != null) {
      // Stamp impact damage proportional to incoming speed.
      final damage = (landingSpeed.abs() / GameConfig.maxJumpPower)
          .clamp(0.0, 1.0);
      landedOn.applyImpact(damage);

      if (landedOn.type == PlatformType.bouncy) {
        // Auto-collect pickups before the bouncy is destroyed by the launcher.
        _autoCollectPickupsOnPlatform(landedOn);

        // Bouncy chain — increment + reward popup at chain ≥ 2.
        _bouncyChainCount++;
        gameState.updateBouncyChain(_bouncyChainCount);
        if (_bouncyChainCount >= 2) {
          final mult = gameState.comboMultiplier;
          final bonus = (100 * _bouncyChainCount * mult).round();
          gameState.addBonus(bonus);
          gameWorld.add(FloatingScoreText(
            origin: Vector2(
              player.position.x,
              player.position.y - player.size.y - 36,
            ),
            label: 'CHAIN ×$_bouncyChainCount  +$bonus',
            color: const Color(0xFF66E081), // bouncy green
            fontSize: 19,
            life: 1.5,
            floatHeight: 85,
          ));
        }

        // Auto-launch toward the next platform above, predicting its position
        // if it's a moving target.
        final velocity = _computeBouncyLaunchVelocity(landedOn);
        gameWorld.explodeAndRemove(landedOn);
        player.lastLandedPlatform = null;
        player.launch(velocity);
        gameState.onJumpStart();
        _onBounced(landingSpeed);
        AudioManager.bouncy();
      } else {
        gameState.onJumpLanded();
        GameProgress.update(gameState.platformsReached);
        _onLanded(landingSpeed);
        _autoCollectPickupsOnPlatform(landedOn);
        AudioManager.land();
        // Chain ends on a non-bouncy landing.
        if (_bouncyChainCount != 0) {
          _bouncyChainCount = 0;
          gameState.updateBouncyChain(0);
        }
      }
    }

    _checkWallBounce();
    player.tickVisuals(dt);

    _checkPickupCollisions();
    _riseCamera(dt);
    _updateShake(dt);
    _applyCameraToWorld();
    _spawnAndCull();
    _updateDangerLevel();
    _updatePlatformProximity();
    _checkBotDeaths();
    _checkBotPickupCollision();
    if (_checkDeath()) return;

    gameState.tick(dt);

    // Broadcast my score to Battle Royale teammates whenever it changes.
    if (isBattleRoyale && gameState.score != _lastBroadcastScore) {
      _lastBroadcastScore = gameState.score;
      BattleRoyaleService.instance.updateMyScore(gameState.score);
    }

    // Stream my world position 10×/s so the other clients render me as a
    // real cube jumping on the shared platforms instead of a floating
    // ghost.
    if (isBattleRoyale) {
      _myPosBroadcastTimer -= dt;
      if (_myPosBroadcastTimer <= 0) {
        _myPosBroadcastTimer = 0.1;
        BattleRoyaleService.instance.broadcastBotPosition(
          Preferences.playerId,
          player.position.x,
          player.position.y,
        );
      }
    }
  }

  /// Each frame, paint proximity-based damage on every platform based on its
  /// screen Y, and explode any platform the camera has fully caught.
  void _updatePlatformProximity() {
    final dangerStart = _desiredPlayerScreenY; // = comfort line
    final dangerSpan = _worldHeight - dangerStart;
    if (dangerSpan <= 0) return;

    Platform? caught;
    for (final p in gameWorld.platforms) {
      final screenY = p.topY + _cameraY;
      final raw = (screenY - dangerStart) / dangerSpan;
      p.setProximityDamage(raw.clamp(0.0, 1.0));
      // The camera has reached the platform — explode it.
      if (raw >= 1.0 && caught == null) caught = p;
    }
    if (caught != null) {
      if (player.lastLandedPlatform == caught) {
        player.grounded = false;
        player.lastLandedPlatform = null;
      }
      gameWorld.explodeAndRemove(caught);
    }
  }

  void _onLanded(double landingSpeed) {
    final amplitude =
        (landingSpeed.abs() * GameConfig.shakePowerScale).clamp(2.0, 12.0);
    _triggerShake(amplitude);
    player.applyLandingSquash();
    gameWorld.add(LandingBurst(
      origin: Vector2(player.position.x, player.position.y),
    ));

    // Score is only gained on landing, on a platform higher than any previous.
    final landingHeight = _initialPlayerFeetY - player.position.y;
    final prevBest = gameState.bestHeight;
    gameState.updateBestHeight(landingHeight);
    final realHeightGained = gameState.bestHeight - prevBest;
    // Combo: extra bonus on top of the real height gained.
    gameState.addComboBonus(realHeightGained);

    final scoreGained = gameState.score - _scoreAtJumpStart;
    if (scoreGained > 0) {
      gameWorld.add(FloatingScoreText(
        origin: Vector2(
          player.position.x + player.size.x * 0.7,
          player.position.y - player.size.y,
        ),
        value: scoreGained,
      ));
    }

    // Comeback reward — landing on a platform LOWER than the one we
    // launched from (= we deliberately went back down). Risky move, big
    // payout.
    if (player.position.y > _jumpStartY + 4) {
      const comebackBonus = 1000;
      gameState.addBonus(comebackBonus);
      gameWorld.add(FloatingScoreText(
        origin: Vector2(
          player.position.x,
          player.position.y - player.size.y - 56,
        ),
        label: 'RETOUR  +$comebackBonus',
        color: const Color(0xFFB14BFF), // warp purple
        fontSize: 20,
        life: 1.6,
        floatHeight: 95,
      ));
    }

    // Wall-bounce reward — landing successfully after kissing a wall pays
    // out a bonus that scales with the number of bounces and the combo.
    if (_wallBouncesThisJump > 0) {
      final mult = gameState.comboMultiplier;
      final bonus = (50 * _wallBouncesThisJump * mult).round();
      gameState.addBonus(bonus);
      final label = _wallBouncesThisJump > 1
          ? 'REBOND ×$_wallBouncesThisJump  +$bonus'
          : 'REBOND  +$bonus';
      gameWorld.add(FloatingScoreText(
        origin: Vector2(
          player.position.x,
          player.position.y - player.size.y - 32,
        ),
        label: label,
        color: const Color(0xFF4FC3F7),
        fontSize: 18,
        life: 1.5,
        floatHeight: 80,
      ));
      _wallBouncesThisJump = 0;
    }
  }

  /// Computes a launch velocity that lands the player on the next platform
  /// above [from]. If the next platform is moving, predicts where it will be
  /// at arrival time. Falls back to a straight-up bounce if no platform is
  /// found above.
  Vector2 _computeBouncyLaunchVelocity(Platform from) {
    Platform? next;
    double bestDeltaY = double.infinity;
    for (final p in gameWorld.platforms) {
      if (identical(p, from)) continue;
      if (p.topY >= from.topY) continue; // not strictly above
      final dy = from.topY - p.topY; // positive
      if (dy < bestDeltaY) {
        bestDeltaY = dy;
        next = p;
      }
    }
    if (next == null) {
      return Vector2(0, -GameConfig.bouncyJumpPower);
    }

    const t = 0.55; // time of flight (seconds)
    final targetCenterX = next.predictedCenterX(t);
    final dx = targetCenterX - player.position.x;
    final dy = next.topY - player.position.y; // negative (target is higher)

    var vx = dx / t;
    var vy = (dy - 0.5 * GameConfig.gravity * t * t) / t;

    // Cap the magnitude at maxJumpPower so we don't exceed normal physics.
    final speed = sqrt(vx * vx + vy * vy);
    final maxSpeed = GameConfig.maxJumpPower;
    if (speed > maxSpeed) {
      final scale = maxSpeed / speed;
      vx *= scale;
      vy *= scale;
    }
    return Vector2(vx, vy);
  }

  /// Cosmetic feedback when a bouncy platform sends the player back up.
  /// No score, no combo — just shake + burst.
  void _onBounced(double landingSpeed) {
    final amplitude =
        (landingSpeed.abs() * GameConfig.shakePowerScale).clamp(2.0, 9.0);
    _triggerShake(amplitude);
    player.applyLandingSquash();
    gameWorld.add(LandingBurst(
      origin: Vector2(player.position.x, player.position.y),
    ));
  }

  void _triggerShake(double amplitude) {
    _shakeRemaining = GameConfig.shakeOnLandDuration;
    _shakeAmplitude = amplitude;
  }

  void _updateShake(double dt) {
    if (_shakeRemaining > 0) {
      _shakeRemaining -= dt;
      if (_shakeRemaining < 0) _shakeRemaining = 0;
    }
  }

  void _applyCameraToWorld() {
    double offsetX = 0;
    double offsetY = 0;
    if (_shakeRemaining > 0) {
      final t = (_shakeRemaining / GameConfig.shakeOnLandDuration)
          .clamp(0.0, 1.0);
      final amp = _shakeAmplitude * t;
      offsetX = (_shakeRng.nextDouble() - 0.5) * 2 * amp;
      offsetY = (_shakeRng.nextDouble() - 0.5) * 2 * amp;
    }
    // World coords are in virtual units. Scale + letterbox to the local
    // device so every client renders the same content with consistent
    // proportions, just with different black bars depending on aspect.
    gameWorld.position = Vector2(
      _letterboxX + offsetX * _worldScale,
      _letterboxY + (_cameraY + offsetY) * _worldScale,
    );
    gameWorld.scale = Vector2.all(_worldScale);
  }

  void _updateDangerLevel() {
    final playerScreenY = player.position.y + _cameraY;
    final comfortY = _desiredPlayerScreenY;
    final span = _worldHeight - comfortY;
    final danger = span > 0
        ? ((playerScreenY - comfortY) / span).clamp(0.0, 1.0)
        : 0.0;
    gameState.updateDanger(danger);
    player.setDangerTint(danger);
  }

  double get _desiredPlayerScreenY =>
      _worldHeight * GameConfig.cameraPlayerScreenRatio;

  /// Picks up any in-air bonus the player passes through this frame, applies
  /// its effect, and removes it.
  void _checkPickupCollisions() {
    if (gameWorld.pickups.isEmpty) return;
    final cx = player.position.x;
    final cy = player.position.y - player.size.y / 2;
    final playerR = player.size.x * 0.5;
    final toCollect = <Pickup>[];
    for (final p in gameWorld.pickups) {
      if (p.collected) continue;
      final dx = cx - p.position.x;
      final dy = cy - p.position.y;
      final reach = playerR + GameConfig.pickupRadius;
      if (dx * dx + dy * dy <= reach * reach) {
        p.collected = true;
        toCollect.add(p);
      }
    }
    for (final p in toCollect) {
      _onPickupCollected(p);
      gameWorld.removePickup(p);
    }
  }

  void _onPickupCollected(Pickup p) {
    // Battle Royale: the pickup is shared across the room. Skip the local
    // effect path and let the BR service broadcast — every client (incl.
    // the collector) will get the slow-time effect via the listener.
    if (isBattleRoyale && identical(p, _brPickup)) {
      BattleRoyaleService.instance.notifyBrPickupCollected();
      return;
    }
    if (p is StarPickup) {
      final mult = gameState.comboMultiplier;
      final amount = (GameConfig.starBaseValue * mult).round();
      gameState.addBonus(amount);
      gameWorld.add(FloatingScoreText(
        origin: p.position.clone(),
        value: amount,
      ));
      AudioManager.pickupStar();
    } else if (p is CrystalPickup) {
      gameState.activateSlowTime(GameConfig.slowTimeDuration);
      gameWorld.add(FloatingScoreText(
        origin: Vector2(p.position.x, p.position.y - 24),
        label: 'RALENTI',
        color: const Color(0xFF4FC3F7),
        fontSize: 20,
        life: 1.4,
        floatHeight: 70,
      ));
      AudioManager.pickupCrystal();
    } else if (p is HeartPickup) {
      gameState.freezeCombo(GameConfig.comboFreezeDuration);
      gameWorld.add(FloatingScoreText(
        origin: Vector2(p.position.x, p.position.y - 24),
        label: 'COMBO PROTÉGÉ',
        color: const Color(0xFFFF6E94),
        fontSize: 20,
        life: 1.4,
        floatHeight: 70,
      ));
      AudioManager.pickupHeart();
    } else if (p is VisionPickup) {
      gameState.grantTrajectoryBoost(GameConfig.visionBoostJumps);
      gameWorld.add(FloatingScoreText(
        origin: Vector2(p.position.x, p.position.y - 24),
        label: 'VISION ×${GameConfig.visionBoostJumps}',
        color: const Color(0xFFFFA64C),
        fontSize: 20,
        life: 1.4,
        floatHeight: 70,
      ));
      AudioManager.pickupStar();
    } else if (p is TeleportPickup) {
      final popupOrigin = Vector2(p.position.x, p.position.y - 24);
      gameWorld.add(FloatingScoreText(
        origin: popupOrigin,
        label: 'TÉLÉPORT',
        color: const Color(0xFFB14BFF),
        fontSize: 22,
        life: 1.4,
        floatHeight: 70,
      ));
      AudioManager.pickupWarp();
      _teleportToHighestPlatform();
    }
  }

  /// Collect every pickup currently anchored to [platform].
  /// Used when the player lands on a platform — they shouldn't have to
  /// pixel-perfect align with the pickup, the platform is the trigger.
  void _autoCollectPickupsOnPlatform(Platform platform) {
    final toCollect = <Pickup>[];
    for (final p in gameWorld.pickups) {
      if (p.collected) continue;
      if (p.anchorPlatform == platform) toCollect.add(p);
    }
    for (final p in toCollect) {
      p.collected = true;
      _onPickupCollected(p);
      gameWorld.removePickup(p);
    }
  }

  /// Teleport the player onto the highest platform that is currently visible
  /// on screen. Off-screen platforms (above the camera) are ignored so the
  /// player always lands somewhere they can see. Updates score + combo and
  /// plays particle bursts at both departure and arrival.
  void _teleportToHighestPlatform() {
    final visibleTopWorldY = -_cameraY;
    final visibleBottomWorldY = visibleTopWorldY + size.y;

    Platform? best;
    double bestY = double.infinity;
    for (final p in gameWorld.platforms) {
      if (p.topY < visibleTopWorldY) continue; // off-screen above
      if (p.topY > visibleBottomWorldY) continue; // off-screen below
      if (p.topY < bestY) {
        bestY = p.topY;
        best = p;
      }
    }
    if (best == null) return;

    // If the destination is a bouncy, convert it to a regular platform so the
    // teleport doesn't immediately re-launch the player.
    if (best.type == PlatformType.bouncy) {
      best.convertToStandard();
    }

    // Departure burst at current position.
    gameWorld.add(PlatformExplosion(
      origin: Vector2(
        player.position.x - player.size.x / 2,
        player.position.y - player.size.y,
      ),
      size: player.size.clone(),
      color: GameConfig.playerColor,
    ));

    // Move the player to the target platform.
    player.position = Vector2(
      best.position.x + best.size.x / 2,
      best.topY,
    );
    player.velocity = Vector2.zero();
    player.grounded = true;
    player.lastLandedPlatform = best;

    // Arrival burst at new position.
    gameWorld.add(LandingBurst(
      origin: Vector2(player.position.x, player.position.y),
    ));

    // Treat the teleport as a successful landing for score + combo purposes.
    _scoreAtJumpStart = gameState.score;
    gameState.onJumpLanded();
    _onLanded(0);
  }

  /// Camera rises at base speed when the player is at or below the comfort
  /// line, and accelerates only when the player drifts above it.
  /// Difficulty ramp: speed is reduced before the first platform is reached
  /// and linearly ramps back to 1.0 over the first
  /// [cameraRiseRampPlatforms] platforms.
  void _riseCamera(double dt) {
    final playerScreenY = player.position.y + _cameraY;
    final comfortY = _desiredPlayerScreenY;
    final factor = playerScreenY < comfortY && comfortY > 0
        ? ((comfortY - playerScreenY) / comfortY).clamp(0.0, 1.0)
        : 0.0;

    final rampProgress =
        (gameState.platformsReached / GameConfig.cameraRiseRampPlatforms)
            .clamp(0.0, 1.0);
    final rampMult = GameConfig.cameraRiseStartMultiplier +
        (1.0 - GameConfig.cameraRiseStartMultiplier) * rampProgress;

    final speed = (GameConfig.cameraRiseSpeed +
            factor * GameConfig.cameraRiseSpeedBonus) *
        rampMult *
        gameState.slowFactor;
    _cameraY += speed * dt;
  }

  void _spawnAndCull() {
    final visibleTopWorldY = -_cameraY;
    final visibleBottomWorldY = visibleTopWorldY + size.y;
    gameWorld.ensureCovered(visibleTopWorldY - 100);
    gameWorld.cleanupBelow(visibleBottomWorldY + 200);
  }

  bool _checkDeath() {
    // Side walls bounce the player back instead of killing them — only the
    // bottom (camera catching up) and being engulfed off the bottom kills.
    final playerScreenY = player.position.y + _cameraY;
    if (playerScreenY >= _worldHeight + GameConfig.playerSize) {
      _handleDeath(DeathReason.offscreenBottom);
      return true;
    }
    return false;
  }

  /// Bounce the player off the left/right viewport edges with a small energy
  /// loss instead of letting them die. Keeps the player on screen at all
  /// times and turns mistakes into recoveries.
  void _checkWallBounce() {
    final halfW = player.size.x / 2;
    final left = player.position.x - halfW;
    final right = player.position.x + halfW;
    const restitution = 0.85;
    var bounced = false;

    if (left < 0) {
      player.position.x = halfW;
      if (player.velocity.x < 0) {
        player.velocity.x = -player.velocity.x * restitution;
        bounced = true;
      }
    } else if (right > _worldWidth) {
      player.position.x = _worldWidth - halfW;
      if (player.velocity.x > 0) {
        player.velocity.x = -player.velocity.x * restitution;
        bounced = true;
      }
    }

    if (bounced) {
      _wallBouncesThisJump++;
      final amplitude =
          (player.velocity.x.abs() * GameConfig.shakePowerScale)
              .clamp(2.0, 6.0);
      _triggerShake(amplitude);
      AudioManager.bounce();
    }
  }

  void _handleDeath(DeathReason reason) {
    if (gameState.status == GameStatus.dead) return;
    gameWorld.add(PlatformExplosion(
      origin: Vector2(
        player.position.x - player.size.x / 2,
        player.position.y - player.size.y,
      ),
      size: player.size.clone(),
      color: GameConfig.playerColor,
    ));
    player.markDead();
    if (_bouncyChainCount != 0) {
      _bouncyChainCount = 0;
      gameState.updateBouncyChain(0);
    }
    gameState.die(reason);
    if (Preferences.updateBestScore(gameState.score)) {
      gameState.markNewBest();
    }
    if (isBattleRoyale) {
      BattleRoyaleService.instance.updateMyScore(gameState.score);
      BattleRoyaleService.instance.reportMyDeath();
      // BR: keep the music going so the spectator view stays alive.
    } else {
      AudioManager.playGameOverJingle();
    }
  }

  // ---------------- charging / firing ----------------

  // Map a touch/drag screen position back to world coords. Reverses the
  // letterbox offset and scaling that [_applyCameraToWorld] applied.
  Vector2 _screenToWorld(Vector2 screenPos) {
    final scale = _worldScale == 0 ? 1.0 : _worldScale;
    return Vector2(
      (screenPos.x - _letterboxX) / scale,
      (screenPos.y - _letterboxY) / scale - _cameraY,
    );
  }

  double get _chargeProgress =>
      (_chargeMs / GameConfig.maxChargeMs).clamp(0.0, 1.0);

  void _updatePreview() {
    if (_fingerScreenPos == null) {
      preview.active = false;
      player.aimDirection = null;
      return;
    }
    final fingerWorld = _screenToWorld(_fingerScreenPos!);
    final velocity = JumpSolver.solve(
      playerPos: player.centerWorld,
      fingerPos: fingerWorld,
      chargeProgress: _chargeProgress,
    );
    preview.startPos = player.centerWorld;
    preview.initialVelocity = velocity;
    // Vision pickup overrides the natural fade for N jumps. Otherwise linear
    // fade from 1.0 (no jumps yet) to 0.0 (3+ platforms reached).
    preview.visibility = gameState.trajectoryBoostJumps > 0
        ? 1.0
        : (1.0 - gameState.platformsReached / 3.0).clamp(0.0, 1.0);
    preview.active = true;
    // Feed the aim direction (normalized) to the player so the cube tilts
    // and the aim arrow renders.
    if (velocity.length > 0.01) {
      player.aimDirection = velocity.normalized();
    } else {
      player.aimDirection = Vector2(0, -1);
    }
  }

  void _releaseJump() {
    if (!_charging || _fingerScreenPos == null) {
      _resetCharging();
      return;
    }
    final fingerWorld = _screenToWorld(_fingerScreenPos!);
    final velocity = JumpSolver.solve(
      playerPos: player.centerWorld,
      fingerPos: fingerWorld,
      chargeProgress: _chargeProgress,
    );
    // Punitive: the platform we're launching from explodes on release.
    // Skipped in Battle Royale — bots share these platforms and the
    // explosion would empty the world too fast.
    final from = player.lastLandedPlatform;
    if (from != null) {
      if (!isBattleRoyale) {
        gameWorld.explodeAndRemove(from);
      }
      player.lastLandedPlatform = null;
    }

    _scoreAtJumpStart = gameState.score;
    _wallBouncesThisJump = 0;
    _jumpStartY = player.position.y;
    // Vision boost consumes one release per jump.
    gameState.consumeTrajectoryBoostJump();
    player.launch(velocity);
    gameState.onJumpStart();
    _resetCharging();
    AudioManager.jump();
    if (!isBattleRoyale) {
      AudioManager.platformExplode();
    }
  }

  void _resetCharging() {
    _charging = false;
    _chargeMs = 0;
    _fingerScreenPos = null;
    preview.active = false;
    player.aimDirection = null;
    gameState.updateCharge(charging: false, progress: 0);
  }

  // ---------------- input ----------------

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    if (gameState.status != GameStatus.playing) return;
    if (!player.grounded) return;
    _charging = true;
    _chargeMs = 0;
    _fingerScreenPos = event.localPosition;
    _updatePreview();
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    super.onDragUpdate(event);
    if (!_charging) return;
    _fingerScreenPos = event.localEndPosition;
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    if (!_charging) return;
    _releaseJump();
  }

  @override
  void onDragCancel(DragCancelEvent event) {
    super.onDragCancel(event);
    _resetCharging();
  }
}
