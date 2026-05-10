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

const _profileConfigs = <BotProfile, _BotConfig>{
  BotProfile.bondisseur: _BotConfig(
    restMin: 0.50,
    restMax: 0.95,
    successBase: 0.85,
    minReach: 110,
    maxReach: 260,
    targetMode: _TargetMode.highest,
    jumpDurationBase: 0.62,
    arcMultiplier: 1.30,
  ),
  BotProfile.prudent: _BotConfig(
    restMin: 0.80,
    restMax: 1.45,
    successBase: 0.96,
    minReach: 30,
    maxReach: 120,
    targetMode: _TargetMode.closest,
    jumpDurationBase: 0.48,
    arcMultiplier: 0.85,
  ),
  BotProfile.impatient: _BotConfig(
    restMin: 0.18,
    restMax: 0.42,
    successBase: 0.72,
    minReach: 50,
    maxReach: 200,
    targetMode: _TargetMode.random,
    jumpDurationBase: 0.42,
    arcMultiplier: 1.00,
  ),
  BotProfile.acrobate: _BotConfig(
    restMin: 0.45,
    restMax: 0.78,
    successBase: 0.80,
    minReach: 130,
    maxReach: 320,
    targetMode: _TargetMode.farthest,
    jumpDurationBase: 0.70,
    arcMultiplier: 1.50,
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

  // Jump animation state.
  bool _jumping = false;
  Vector2 _jumpStart = Vector2.zero();
  Vector2 _jumpTarget = Vector2.zero();
  double _jumpProgress = 0;
  double _jumpDuration = 0.55;
  double _arcHeight = 70;
  double _peakScore = 0;
  bool _failedJump = false;

  // Score = max world Y climb so far.
  double _initialY = 0;
  double _broadcastTimer = 0;

  @override
  Future<void> onLoad() async {
    super.onLoad();
    _initialY = position.y;
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
    if (control == BotControl.remote) {
      _updateRemote(dt);
      return;
    }
    _updateAi(dt);
  }

  /// AI-driven update (leader only).
  void _updateAi(double dt) {
    if (!_alive) return;

    if (_falling) {
      // Botched jump → keep falling under gravity. The game checks the
      // bot's Y against the camera and finishes them off when they're
      // off-screen.
      _fallVy += GameConfig.gravity * 0.55 * dt;
      position.y += _fallVy * dt;
      _maybeBroadcastPosition(dt);
      return;
    }

    if (_jumping) {
      _jumpProgress += dt / _jumpDuration;
      if (_jumpProgress >= 1.0) {
        _jumpProgress = 1.0;
        _jumping = false;
        position = _jumpTarget.clone();
        if (_failedJump) {
          // Start free-falling instead of insta-dying — the player can
          // see the bot whiff and tumble out of the screen.
          _failedJump = false;
          _falling = true;
          _fallVy = 80;
        } else {
          _peakScore = max(_peakScore, _initialY - position.y);
          BattleRoyaleService.instance
              .reportBotScore(playerId, _peakScore.round());
          final cfg = _cfg;
          _restTimer =
              cfg.restMin + _rng.nextDouble() * (cfg.restMax - cfg.restMin);
        }
      } else {
        final t = Curves.easeInOut.transform(_jumpProgress);
        final px = _jumpStart.x + (_jumpTarget.x - _jumpStart.x) * t;
        final py = _jumpStart.y + (_jumpTarget.y - _jumpStart.y) * t;
        final arc = sin(_jumpProgress * pi) * _arcHeight;
        position = Vector2(px, py - arc);
      }
    } else {
      _restTimer -= dt;
      if (_restTimer <= 0) _planNextJump();
    }

    _maybeBroadcastPosition(dt);
  }

  void _maybeBroadcastPosition(double dt) {
    _broadcastTimer -= dt;
    if (_broadcastTimer <= 0) {
      _broadcastTimer = 0.1;
      BattleRoyaleService.instance
          .broadcastBotPosition(playerId, position.x, position.y);
    }
  }

  /// Public method called by the game when the camera has caught the bot.
  void killByCamera() => _die();

  /// Remote update (non-leader clients) — lerp toward the latest broadcast
  /// position so the cube animates smoothly even at 10 Hz.
  void _updateRemote(double dt) {
    final svc = BattleRoyaleService.instance;
    final state = svc.playerStates[playerId];
    if (state != null) _alive = state.alive;
    if (!_alive) return;
    final pos = svc.botPositionFor(playerId);
    if (pos == null) return;
    final target = Vector2(pos.x, pos.y);
    // Lerp ~12× per second of dt → smooth follow without overshoot.
    final t = (dt * 14.0).clamp(0.0, 1.0);
    position = Vector2(
      position.x + (target.x - position.x) * t,
      position.y + (target.y - position.y) * t,
    );
  }

  Color _gradLight() => Color.lerp(color, Colors.white, 0.40)!;
  Color _gradDark() => Color.lerp(color, Colors.black, 0.55)!;

  void _planNextJump() {
    final cfg = _cfg;

    // The bot can only "see" what's currently on screen — anything above
    // the visible top is off-limits even if it has been pre-generated.
    final visibleTopY = -game.cameraY;

    // Collect every reachable platform above the bot, within the profile's
    // [minReach, maxReach] vertical band, and below the visible top edge.
    final platforms = game.gameWorld.platforms;
    final candidates = <(Platform p, double dy)>[];
    for (final p in platforms) {
      if (p.topY < visibleTopY) continue; // off-screen above
      final dy = position.y - p.topY;
      if (dy < cfg.minReach) continue;
      if (dy > cfg.maxReach) continue;
      candidates.add((p, dy));
    }
    if (candidates.isEmpty) {
      // Fallback: closest visible platform above, no band restriction.
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

    // Pick a target according to the bot's playstyle.
    (Platform p, double dy) pick;
    switch (cfg.targetMode) {
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

    // Skill-tweaked success rate, clamped to a sane range. Bots barely
    // miss — most deaths come from the camera catching the slow ones.
    final baseSuccess = (cfg.successBase + (skill - 1.0) * 0.05)
        .clamp(0.85, 0.99);
    final missChance = (1.0 - baseSuccess) * 0.4; // cut misses further
    final missed = _rng.nextDouble() < missChance;

    _jumpStart = position.clone();
    if (missed) {
      // Aim short of the platform → falls past it, off-screen, dies.
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
        target.position.x + target.size.x / 2,
        target.topY,
      );
      _jumpDuration = cfg.jumpDurationBase +
          _rng.nextDouble() * 0.18 +
          (delta / 320) * 0.20;
      _arcHeight = max(30.0, delta * 0.50 * cfg.arcMultiplier);
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

    // Push the cube + face onto a translucent layer so other players read
    // as "remote" and your own (local) player visibly pops in front.
    // Both bots and remote humans render translucent so the local player
    // visually pops in front. The whole cube + glow + face is composited
    // through a single layer at this alpha.
    final layered = _alive;
    if (layered) {
      canvas.saveLayer(
        Rect.fromLTWH(-14, -14, w + 28, h + 28),
        Paint()..color = const Color.fromRGBO(255, 255, 255, 0.62),
      );
    }

    if (_alive) {
      // Glow halo
      canvas.drawRRect(
        body,
        Paint()
          ..color = color.withValues(alpha: 0.30)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      // Gradient fill
      canvas.drawRRect(
        body,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_gradLight(), color, _gradDark()],
            stops: const [0.0, 0.55, 1.0],
          ).createShader(size.toRect()),
      );
      // Top rim highlight
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
      // Outline
      canvas.drawRRect(
        body,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = _gradDark(),
      );
      // Simple face — two eye dots so it reads as "a player".
      final eyeR = w * 0.085;
      final eyeY = h * 0.42;
      final eyeOffset = w * 0.18;
      final eyePaint = Paint()..color = const Color(0xFF1A1410);
      canvas.drawCircle(Offset(w / 2 - eyeOffset, eyeY), eyeR, eyePaint);
      canvas.drawCircle(Offset(w / 2 + eyeOffset, eyeY), eyeR, eyePaint);
    } else {
      // Dead marker: faded cube with X.
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

    // Close the translucent layer (alive only) so the name above renders
    // at full opacity / readability.
    if (layered) {
      canvas.restore();
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
