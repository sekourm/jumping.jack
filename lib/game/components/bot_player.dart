import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../../services/battle_royale_service.dart';
import '../config.dart';
import '../jumping_jack_game.dart';
import 'platform.dart';

/// Bot that visually plays in the world.
///
/// Two control modes:
///   • [BotControl.ai]    — the leader of the room runs the AI locally and
///     broadcasts the resulting position so every other client renders the
///     same thing.
///   • [BotControl.remote] — non-leader clients receive the broadcast
///     positions and lerp the cube toward them; no AI runs here.
///
/// The platforms are deterministic (the BR room id seeds the world's
/// procedural RNG) so the leader's AI and the other clients' platforms
/// agree on geometry.
enum BotControl { ai, remote }

/// Bot personalities — each one plays the game with a distinct rhythm so
/// the player can recognise them by behaviour, not just colour.
enum BotProfile {
  /// "LE BONDISSEUR" — picks the highest reachable platform every jump.
  /// Big arcs, slower rests, ambitious. Drops behind on reaction misses.
  bondisseur,

  /// "LE PRUDENT" — always takes the closest safe platform above. High
  /// success rate but slow to climb.
  prudent,

  /// "L'IMPATIENT" — jumps almost non-stop, picks targets at random,
  /// makes mistakes from haste.
  impatient,

  /// "L'ACROBATE" — favours the farthest platform with showy long arcs.
  /// Skilled, but the riskier targets bite back.
  acrobate,
}

class _BotConfig {
  const _BotConfig({
    required this.restMin,
    required this.restMax,
    required this.successBase,
    required this.minReach,
    required this.maxReach,
    required this.targetMode,
    required this.jumpDurationBase,
    required this.arcMultiplier,
  });
  final double restMin;
  final double restMax;
  final double successBase;
  final double minReach;
  final double maxReach;
  final _TargetMode targetMode;
  final double jumpDurationBase;
  final double arcMultiplier;
}

enum _TargetMode { closest, highest, random, farthest }

// All profiles share the same reach + success + skill curve so the match
// stays fair (no one overpowered). Only the target-picking mode and rest
// rhythm vary, so bots desynchronise naturally. Success is intentionally
// kept around 80 % so bots feel human (occasional misses) instead of
// flawless pros — particularly noticeable in spectator mode.
const _profileConfigs = <BotProfile, _BotConfig>{
  BotProfile.bondisseur: _BotConfig(
    restMin: 0.40,
    restMax: 0.70,
    successBase: 0.82,
    minReach: 70,
    maxReach: 200,
    targetMode: _TargetMode.highest,
    jumpDurationBase: 0.60,
    arcMultiplier: 1.10,
  ),
  BotProfile.prudent: _BotConfig(
    restMin: 0.50,
    restMax: 0.85,
    successBase: 0.86,
    minReach: 70,
    maxReach: 200,
    targetMode: _TargetMode.closest,
    jumpDurationBase: 0.60,
    arcMultiplier: 1.10,
  ),
  BotProfile.impatient: _BotConfig(
    restMin: 0.25,
    restMax: 0.55,
    successBase: 0.74,
    minReach: 70,
    maxReach: 200,
    targetMode: _TargetMode.random,
    jumpDurationBase: 0.60,
    arcMultiplier: 1.10,
  ),
  BotProfile.acrobate: _BotConfig(
    restMin: 0.40,
    restMax: 0.70,
    successBase: 0.80,
    minReach: 70,
    maxReach: 200,
    targetMode: _TargetMode.farthest,
    jumpDurationBase: 0.60,
    arcMultiplier: 1.10,
  ),
};

class BotPlayer extends PositionComponent
    with HasGameReference<JumpingJackGame> {
  BotPlayer({
    required this.playerId,
    required this.name,
    required this.slotIndex,
    required this.color,
    required this.skill,
    required this.lifespanSec,
    required this.control,
    required this.profile,
    required Vector2 startPos,
  }) : super(
          size: Vector2.all(GameConfig.playerSize * 0.92),
          anchor: Anchor.bottomCenter,
          priority: 9,
          position: startPos.clone(),
        );

  final String playerId;
  final String name;
  final int slotIndex;
  final Color color;
  final double skill; // 0.6 (clumsy) → 1.4 (sharp)
  final double lifespanSec;
  final BotControl control;
  final BotProfile profile;
  _BotConfig get _cfg => _profileConfigs[profile]!;

  final Random _rng = Random();
  late TextPainter _namePainter;

  bool _alive = true;
  double _restTimer = 0;
  bool _falling = false;
  double _fallVy = 0;

  bool get alive => _alive;

  // Wind-up state — visible "I'm about to jump" animation.
  // Builds during the final [_windupDuration] seconds of rest (AI mode) or
  // is lerped from the broadcast `cl` field (remote mode). Drives both the
  // body squash (via [_targetScale]) and the glow halo painted in render().
  static const double _windupDuration = 0.45;
  double _chargeLevel = 0;
  Vector2 _targetScale = Vector2.all(1);

  // Airborne / aim parity with the local player. `_airborne` flips the
  // mouth state and triggers launch/landing pulses on transition. `_aimDir`
  // tilts the cube and offsets the pupils while charging.
  bool _airborne = false;
  bool _wasAirborne = false;
  Vector2 _aimDir = Vector2.zero();
  static const double _maxTilt = pi / 8;

  // Jump animation state.
  bool _jumping = false;
  Vector2 _jumpStart = Vector2.zero();
  Vector2 _jumpTarget = Vector2.zero();
  double _jumpProgress = 0;
  double _jumpDuration = 0.55;
  double _arcHeight = 70;
  double _peakHeight = 0; // height climbed in pixels
  bool _failedJump = false;
  // Platform we're aiming at this jump — used at landing time to detect
  // bouncy chains and trigger the auto-launch. Exposed (via [targetPlatform])
  // so other bots' AI can deconflict their target picks and avoid stacking
  // at the same pixel, which would otherwise trip the bot-vs-bot crush.
  Platform? _targetPlatform;
  Platform? get targetPlatform => _targetPlatform;

  /// Stable per-slot offset (in pixels) from a platform's center, so that
  /// when two bots share a platform their feet don't collide at the exact
  /// same X. Even slots offset left, odd slots offset right; magnitude is
  /// rotated by slot so adjacent slots don't clamp to the same two columns.
  double get _landingDx {
    final mag = 6.0 + (slotIndex % 3) * 2.0;
    return slotIndex.isEven ? -mag : mag;
  }

  // ---- Player-parity systems (Battle Royale fairness) ----
  // Combo: chained landings within [GameConfig.comboWindow] each bump the
  // multiplier, applied to height-based score gains. Mirrors the local
  // player's combo so bots don't lag behind on score.
  int _comboCount = 0;
  double _comboTimer = 0;
  // Bouncy chain: consecutive bouncy landings → flat bonus (×combo).
  int _bouncyChain = 0;
  // Bonus score accumulated from combo + bouncy chains. Reported on top of
  // [_peakHeight] so the bot's leaderboard score matches the player's
  // height + bonus model.
  double _bonusScore = 0;

  // Score = max world Y climb so far.
  double _initialY = 0;
  double _broadcastTimer = 0;

  /// Last "settled" Y of this cube — i.e. the world Y of the platform it's
  /// currently sitting on. Updated on successful jump completion (and on
  /// load). Used by the BR camera to track the room's highest *grounded*
  /// position without chasing every arc peak.
  double _lastSettledY = 0;
  double get lastSettledY => _lastSettledY;
  bool get settled => _alive && !_jumping && !_falling;

  /// Previous-frame Y, kept around so the crush detection can know if the
  /// cube is currently moving downward (i.e. at risk of squashing whoever
  /// is below). Updated each frame after movement.
  double _prevY = 0;
  double get prevY => _prevY;
  bool get descending => position.y > _prevY + 0.0001;

  @override
  Future<void> onLoad() async {
    super.onLoad();
    _initialY = position.y;
    _lastSettledY = position.y;
    final cfg = _cfg;
    _restTimer =
        cfg.restMin + _rng.nextDouble() * (cfg.restMax - cfg.restMin);
    _namePainter = TextPainter(
      text: TextSpan(
        text: name,
        style: TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.2,
          shadows: [
            Shadow(color: color.withValues(alpha: 0.7), blurRadius: 6),
            const Shadow(color: Colors.black, blurRadius: 3, offset: Offset(0, 1)),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (game.preGame || game.brWinSequenceActive) return;
    // Snapshot last-frame Y so crush detection can tell if we're descending.
    _prevY = position.y;
    if (control == BotControl.remote) {
      _updateRemote(dt);
      return;
    }
    _updateAi(dt);
  }

  /// AI-driven update (leader only).
  void _updateAi(double dt) {
    if (!_alive) return;

    // Combo timer ticks down while not actively jumping.
    if (!_jumping && !_falling && _comboTimer > 0) {
      _comboTimer -= dt;
      if (_comboTimer <= 0) {
        _comboTimer = 0;
        _comboCount = 0;
      }
    }

    if (_falling) {
      _fallVy += GameConfig.gravity * 0.55 * dt;
      position.y += _fallVy * dt;
      _setChargeLevel(0);
      _aimDir.setZero();
      _airborne = true;
      _applyAirborneTransitions();
      _tickVisuals(dt);
      _maybeBroadcastPosition(dt);
      return;
    }

    if (_jumping) {
      _setChargeLevel(0);
      _aimDir.setZero();
      _airborne = true;
      _applyAirborneTransitions();
      _jumpProgress += dt / _jumpDuration;
      if (_jumpProgress >= 1.0) {
        _jumpProgress = 1.0;
        _jumping = false;
        position = _jumpTarget.clone();
        if (_failedJump) {
          _failedJump = false;
          _falling = true;
          _fallVy = 80;
          _bouncyChain = 0;
        } else {
          _airborne = false;
          _applyAirborneTransitions();
          _onSuccessfulLanding();
        }
      } else {
        final t = Curves.easeInOut.transform(_jumpProgress);
        final px = _jumpStart.x + (_jumpTarget.x - _jumpStart.x) * t;
        final py = _jumpStart.y + (_jumpTarget.y - _jumpStart.y) * t;
        final arc = sin(_jumpProgress * pi) * _arcHeight;
        position = Vector2(px, py - arc);
      }
    } else {
      // While settled on a moving platform, ride it horizontally so the
      // cube actually moves with the platform (instead of staying at the
      // X where it landed). Mirrors the local player's "carry along
      // moving platform" pre-physics step.
      final tgt = _targetPlatform;
      if (tgt != null && tgt.type == PlatformType.moving) {
        position.x = tgt.position.x + tgt.size.x / 2 + _landingDx;
      }
      _airborne = false;
      _applyAirborneTransitions();
      _restTimer -= dt;
      // Final stretch of rest: ramp the wind-up so other clients see the
      // cube visibly preparing its jump. Peak under 1.0 so the squash
      // stays readable instead of flattening the cube entirely.
      if (_restTimer < _windupDuration && _restTimer > 0) {
        final progress =
            (1.0 - _restTimer / _windupDuration).clamp(0.0, 1.0);
        _setChargeLevel(progress * 0.85);
      } else {
        _setChargeLevel(0);
        _aimDir.setZero();
      }
      if (_restTimer <= 0) {
        _setChargeLevel(0);
        _aimDir.setZero();
        _planNextJump();
      }
    }

    _tickVisuals(dt);
    _maybeBroadcastPosition(dt);
  }

  /// Updates the wind-up level and the corresponding target scale. While
  /// charging the cube squashes wider + shorter; once charge drops to zero
  /// the target scale is left alone so launch/landing pulses (set by
  /// [_applyAirborneTransitions]) can take over and drift back naturally.
  void _setChargeLevel(double level) {
    _chargeLevel = level.clamp(0.0, 1.0);
    if (_chargeLevel > 0) {
      final s = 0.45 * _chargeLevel;
      _targetScale = Vector2(1 + s, 1 - s * 1.3);
    }
  }

  /// Detects airborne edges: false→true triggers the vertical stretch
  /// (mirrors `Player.launch`) and true→false triggers the flat landing
  /// squash (mirrors `Player.applyLandingSquash`). Both pulses then drift
  /// back to neutral via [_tickVisuals].
  void _applyAirborneTransitions() {
    if (_airborne == _wasAirborne) return;
    if (_airborne) {
      _targetScale = Vector2(0.85, 1.25);
    } else {
      _targetScale = Vector2(1.35, 0.55);
    }
    _wasAirborne = _airborne;
  }

  /// Lerps [scale] + [angle] toward their targets and drifts the target
  /// scale back to neutral when not being actively held by [_setChargeLevel].
  /// Same drift rates as the local player's `tickVisuals`.
  void _tickVisuals(double dt) {
    final t = (GameConfig.squashLerpRate * dt).clamp(0.0, 1.0);
    scale = scale + (_targetScale - scale) * t;

    final targetAngle = _computeTiltAngle();
    angle = angle + (targetAngle - angle) * t;

    // While charging, _setChargeLevel pins _targetScale each frame so this
    // drift is a no-op. Otherwise launch/landing pulses smoothly ease back
    // to (1, 1) — slower in the air, snappier on the ground.
    final pullRate = _airborne ? 0.05 : 0.10;
    _targetScale = Vector2(
      _targetScale.x + (1 - _targetScale.x) * pullRate,
      _targetScale.y + (1 - _targetScale.y) * pullRate,
    );
  }

  /// Bottom-anchored tilt toward the aim direction while charging. Same
  /// curve as the local player: capped at ±22°, sub-linear so straight-up
  /// reads as "no tilt" and side jumps lean visibly.
  double _computeTiltAngle() {
    if (_chargeLevel <= 0) return 0;
    if (_aimDir.x == 0 && _aimDir.y == 0) return 0;
    if (!_aimDir.x.isFinite || !_aimDir.y.isFinite) return 0;
    final ang = atan2(_aimDir.x, -_aimDir.y);
    if (!ang.isFinite) return 0;
    return (ang * 0.45).clamp(-_maxTilt, _maxTilt);
  }

  /// Called once each time the bot lands on its target platform without
  /// failing the jump. Mirrors the local player's onJumpLanded logic so
  /// bots accumulate the same combo / bouncy-chain bonuses.
  void _onSuccessfulLanding() {
    _lastSettledY = position.y;
    final tgt = _targetPlatform;
    final isBouncy = tgt != null && tgt.type == PlatformType.bouncy;

    if (isBouncy) {
      // Bouncy chain — same payout formula as the player.
      _bouncyChain++;
      if (_bouncyChain >= 2) {
        final mult = _comboMultiplier();
        _bonusScore += 100 * _bouncyChain * mult;
      }
      _reportScore();
      // Immediate re-launch — no rest, boosted reach to mimic the player's
      // auto-launch from the bouncy.
      _planNextJump(bouncyChain: true);
      return;
    }

    // Regular landing → combo + height-based score.
    _bouncyChain = 0;
    if (_comboTimer > 0) {
      _comboCount++;
    } else {
      _comboCount = 1;
    }
    _comboTimer = GameConfig.comboWindow;

    final climbed = _initialY - position.y;
    final delta = max(0.0, climbed - _peakHeight);
    if (delta > 0) {
      final mult = _comboMultiplier();
      if (mult > 1.0) {
        _bonusScore += delta * (mult - 1.0);
      }
      _peakHeight = climbed;
    }

    _reportScore();

    final cfg = _cfg;
    _restTimer =
        cfg.restMin + _rng.nextDouble() * (cfg.restMax - cfg.restMin);
  }

  double _comboMultiplier() {
    if (_comboCount <= 1) return 1.0;
    final extra = (_comboCount - 1) * GameConfig.comboMultiplierStep;
    return (1.0 + extra).clamp(1.0, GameConfig.comboMultiplierMax);
  }

  void _reportScore() {
    BattleRoyaleService.instance.reportBotScore(
      playerId,
      (_peakHeight + _bonusScore).round(),
    );
  }

  void _maybeBroadcastPosition(double dt) {
    _broadcastTimer -= dt;
    if (_broadcastTimer <= 0) {
      _broadcastTimer = 0.1;
      BattleRoyaleService.instance.broadcastBotPosition(
        playerId,
        position.x,
        position.y,
        _lastSettledY,
        chargeLevel: _chargeLevel,
        airborne: _airborne,
        aimX: _aimDir.x,
        aimY: _aimDir.y,
      );
    }
  }

  /// Public method called by the game when the camera has caught the bot
  /// (no specific killer — the world ate them). Reports the death to the
  /// service so the BR feed gets a "died" event.
  void killByCamera() => _die();

  /// Used by crush flows: just flips the local AI to "dead" without going
  /// through the service. The crush site is expected to call
  /// [BattleRoyaleService.broadcastCrushKill] afterwards, which records
  /// the kill credit + broadcasts. Avoids the double-event bug where both
  /// `reportBotDeath` and `broadcastCrushKill` would push entries.
  void markDeadLocal() {
    if (!_alive) return;
    _alive = false;
  }

  /// Credit a crush kill on this bot — +500 flat into the bonus pool, like
  /// the local player's crush bonus.
  void addCrushBonus() {
    _bonusScore += 500;
    _reportScore();
  }

  /// Remote update (non-leader clients) — lerp toward the latest broadcast
  /// position so the cube animates smoothly even at 10 Hz.
  void _updateRemote(double dt) {
    final svc = BattleRoyaleService.instance;
    final state = svc.playerStates[playerId];
    if (state != null) _alive = state.alive;
    if (!_alive) {
      _setChargeLevel(0);
      _airborne = false;
      _applyAirborneTransitions();
      _tickVisuals(dt);
      return;
    }
    final pos = svc.botPositionFor(playerId);
    if (pos == null) return;
    final target = Vector2(pos.x, pos.y);
    final t = (dt * 14.0).clamp(0.0, 1.0);
    position = Vector2(
      position.x + (target.x - position.x) * t,
      position.y + (target.y - position.y) * t,
    );
    // Mirror the authoritative settledY from the source client so the BR
    // camera (_riseCameraBr) can track this cube. Without this the field
    // stays at its spawn value and the camera never rises to follow remote
    // bots/humans climbing on the leader.
    _lastSettledY = pos.settledY;
    // Lerp the wind-up level from the broadcast so the squash settles in
    // smoothly between the 10 Hz packets.
    final ct = (dt * 12.0).clamp(0.0, 1.0);
    final lerped = _chargeLevel + (pos.chargeLevel - _chargeLevel) * ct;
    _setChargeLevel(lerped);
    // Mirror the source cube's aim direction (charging only) and airborne
    // state so face / mouth / launch-stretch + landing-squash all line up
    // with what the local player is seeing on their device.
    _aimDir = Vector2(pos.aimX, pos.aimY);
    _airborne = pos.airborne;
    _applyAirborneTransitions();
    _tickVisuals(dt);
  }

  /// Base body color after wind-up tinting. Below the threshold it returns
  /// the slot color; while charging it lerps toward white (then toward an
  /// angry red-orange past 85% charge), matching the local player's
  /// "boiling over" feedback.
  Color _bodyColor() {
    if (_chargeLevel <= 0) return color;
    var c = Color.lerp(color, Colors.white, _chargeLevel * 0.55)!;
    if (_chargeLevel > 0.85) {
      final t = ((_chargeLevel - 0.85) / 0.15).clamp(0.0, 1.0);
      c = Color.lerp(c, const Color(0xFFFF6B3F), t * 0.50)!;
    }
    return c;
  }

  Color _gradLight() => Color.lerp(_bodyColor(), Colors.white, 0.40)!;
  Color _gradDark() => Color.lerp(_bodyColor(), Colors.black, 0.55)!;

  /// Picks the next target platform and starts the jump animation.
  /// When [bouncyChain] is true we just landed on a bouncy and want to
  /// chain — extend the reach band so the next platform mimics the
  /// player's bouncy auto-launch (which goes much further than a normal
  /// jump).
  void _planNextJump({bool bouncyChain = false}) {
    final cfg = _cfg;

    // The bot can only "see" what's currently on screen — anything above
    // the visible top is off-limits even if it has been pre-generated.
    final visibleTopY = -game.cameraY;

    // Bouncy chain still uses the normal reach band — like the local
    // player's auto-launch, the bot just hops to the next platform above
    // instead of being catapulted twice as far.
    final minReach = cfg.minReach;
    final maxReach = cfg.maxReach;

    final platforms = game.gameWorld.platforms;
    final candidates = <(Platform p, double dy)>[];
    for (final p in platforms) {
      if (p.topY < visibleTopY) continue;
      final dy = position.y - p.topY;
      if (dy < minReach) continue;
      if (dy > maxReach) continue;
      candidates.add((p, dy));
    }
    if (candidates.isEmpty) {
      Platform? fallback;
      double best = double.infinity;
      for (final p in platforms) {
        if (p.topY < visibleTopY) continue;
        final dy = position.y - p.topY;
        if (dy < 30) continue;
        if (dy < best) {
          best = dy;
          fallback = p;
        }
      }
      if (fallback == null) {
        _restTimer = 0.4;
        return;
      }
      candidates.add((fallback, best));
    }

    // Deconflict: prefer platforms not already claimed by another live bot.
    // A platform is "claimed" by another bot if it is its current jump
    // target, or if the bot is settled on it (matched by topY proximity).
    // If every reachable platform is claimed we fall back to the full set,
    // so a crowded room never softlocks the AI.
    final claimed = <Platform>{};
    for (final other in game.aliveBots) {
      if (identical(other, this)) continue;
      final t = other.targetPlatform;
      if (t != null) claimed.add(t);
    }
    if (claimed.isNotEmpty) {
      final free = candidates.where((c) => !claimed.contains(c.$1)).toList();
      if (free.isNotEmpty) {
        candidates
          ..clear()
          ..addAll(free);
      }
    }

    (Platform p, double dy) pick;
    // Bouncy chain → always pick the *closest* platform above. Mirrors
    // the local player's bouncy auto-launch (which aims at the next
    // platform, not the farthest one).
    final mode = bouncyChain ? _TargetMode.closest : cfg.targetMode;
    switch (mode) {
      case _TargetMode.closest:
        candidates.sort((a, b) => a.$2.compareTo(b.$2));
        pick = candidates.first;
      case _TargetMode.highest:
        candidates.sort((a, b) => b.$2.compareTo(a.$2));
        pick = candidates.first;
      case _TargetMode.farthest:
        candidates.sort((a, b) => b.$2.compareTo(a.$2));
        pick = candidates.first;
      case _TargetMode.random:
        pick = candidates[_rng.nextInt(candidates.length)];
    }
    final target = pick.$1;
    final delta = pick.$2;

    // Bouncy chains rarely miss — the player's auto-launch is reliable.
    final baseSuccess = bouncyChain
        ? 0.985
        : (cfg.successBase + (skill - 1.0) * 0.05).clamp(0.85, 0.99);
    final missChance = (1.0 - baseSuccess) * 0.4;
    final missed = _rng.nextDouble() < missChance;

    _jumpStart = position.clone();
    _targetPlatform = target;
    if (missed) {
      _failedJump = true;
      final missY = target.topY + 60 + _rng.nextDouble() * 40;
      _jumpTarget = Vector2(
        target.position.x + target.size.x * (0.1 + _rng.nextDouble() * 0.5),
        missY,
      );
      _jumpDuration = cfg.jumpDurationBase + _rng.nextDouble() * 0.15;
      _arcHeight = 28;
    } else {
      _failedJump = false;
      _jumpTarget = Vector2(
        target.position.x + target.size.x / 2 + _landingDx,
        target.topY,
      );
      _jumpDuration = cfg.jumpDurationBase +
          _rng.nextDouble() * 0.18 +
          (delta / 320) * 0.20;
      // Bouncy chains get a flatter, faster arc — they're powered launches,
      // not measured jumps.
      _arcHeight = bouncyChain
          ? max(80.0, delta * 0.35)
          : max(30.0, delta * 0.50 * cfg.arcMultiplier);
      if (bouncyChain) {
        _jumpDuration = max(_jumpDuration, 0.55);
      }
    }
    _jumpProgress = 0;
    _jumping = true;
  }

  void _die() {
    if (!_alive) return;
    _alive = false;
    BattleRoyaleService.instance.reportBotDeath(playerId);
  }

  @override
  void render(Canvas canvas) {
    final w = size.x;
    final h = size.y;
    final cornerR = w * 0.20;
    final body = RRect.fromRectAndRadius(
      size.toRect(),
      Radius.circular(cornerR),
    );

    if (_alive) {
      // Wind-up glow — louder, blurrier halo while the cube is charging so
      // the player reads "this opponent is about to launch" from across
      // the screen, even at small remote-cube sizes.
      if (_chargeLevel > 0) {
        canvas.drawRRect(
          body,
          Paint()
            ..color = color.withValues(alpha: 0.55 * _chargeLevel)
            ..maskFilter = MaskFilter.blur(
              BlurStyle.normal,
              6 + _chargeLevel * 12,
            ),
        );
      }
      canvas.drawRRect(
        body,
        Paint()
          ..color = color.withValues(alpha: 0.30)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawRRect(
        body,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_gradLight(), _bodyColor(), _gradDark()],
            stops: const [0.0, 0.55, 1.0],
          ).createShader(size.toRect()),
      );
      canvas.drawRRect(
        RRect.fromLTRBAndCorners(
          1.5,
          1.5,
          w - 1.5,
          h * 0.30,
          topLeft: Radius.circular(cornerR * 0.85),
          topRight: Radius.circular(cornerR * 0.85),
        ),
        Paint()..color = Colors.white.withValues(alpha: 0.40),
      );
      canvas.drawRRect(
        body,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = _gradDark(),
      );
      // Battle Royale spikes — every cube in BR has them so the player
      // reads the room as "everyone can stomp everyone".
      _renderBotSpikes(canvas, w, h);
      _renderFace(canvas, w, h);
    } else {
      canvas.drawRRect(
        body,
        Paint()..color = color.withValues(alpha: 0.22),
      );
      canvas.drawRRect(
        body,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = color.withValues(alpha: 0.40),
      );
      final p = Paint()
        ..color = Colors.white.withValues(alpha: 0.55)
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(const Offset(2, 2), Offset(w - 2, h - 2), p);
      canvas.drawLine(Offset(w - 2, 2), Offset(2, h - 2), p);
    }

    _namePainter.paint(
      canvas,
      Offset(
        (w - _namePainter.width) / 2,
        -_namePainter.height - 4,
      ),
    );
  }

  /// Mirrors the local player's face: pupils that track [_aimDir] (or look
  /// up when airborne), a squint past 60% charge, angry V eyebrows past
  /// 85%, and a mouth that cycles smile → determined → clenched zigzag
  /// (charging) / open "O" (airborne).
  void _renderFace(Canvas canvas, double w, double h) {
    final eyeY = h * 0.42;
    final eyeOffset = w * 0.20;
    final eyeR = w * 0.13;
    final pupilR = eyeR * 0.55;

    Offset pupilDelta = Offset.zero;
    if (_chargeLevel > 0 && (_aimDir.x != 0 || _aimDir.y != 0)) {
      pupilDelta = Offset(
        _aimDir.x.clamp(-1.0, 1.0) * eyeR * 0.35,
        _aimDir.y.clamp(-1.0, 1.0) * eyeR * 0.35,
      );
    } else if (_airborne) {
      pupilDelta = Offset(0, -eyeR * 0.25);
    }

    final eyeWhite = Paint()..color = const Color(0xFFFFFAF0);
    final pupil = Paint()..color = const Color(0xFF1A1410);
    final shine = Paint()..color = Colors.white;
    final squintColor = _bodyColor();

    for (final side in const [-1, 1]) {
      final ex = w / 2 + side * eyeOffset;
      canvas.drawCircle(Offset(ex, eyeY), eyeR, eyeWhite);
      if (_chargeLevel > 0.6) {
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset(ex, eyeY - eyeR * 0.7),
            width: eyeR * 2.4,
            height: eyeR * 0.9,
          ),
          Paint()..color = squintColor,
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

    if (_chargeLevel > 0.85) {
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
    const dark = Color(0xFF3B1F00);

    if (_chargeLevel > 0.85) {
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
    } else if (_chargeLevel > 0.3) {
      canvas.drawLine(
        Offset(cx - mouthW / 2, mouthY),
        Offset(cx + mouthW / 2, mouthY),
        Paint()
          ..color = dark
          ..strokeWidth = 2.0
          ..strokeCap = StrokeCap.round,
      );
    } else if (_airborne) {
      canvas.drawCircle(
        Offset(cx, mouthY),
        mouthW * 0.30,
        Paint()..color = dark,
      );
    } else {
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

  void _renderBotSpikes(Canvas canvas, double w, double h) {
    const spikeCount = 4;
    final spikeBaseY = h - 0.5;
    final spikeTipY = h + 4.0;
    final cellW = w / spikeCount;
    final fill = Paint()..color = Colors.white.withValues(alpha: 0.85);
    final stroke = Paint()
      ..color = _gradDark()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
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
}
