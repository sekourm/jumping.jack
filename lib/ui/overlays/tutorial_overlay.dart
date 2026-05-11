import 'dart:async';
import 'dart:math';

// `Timer` is also exported by flame/components — hide the Flame one so
// we get the dart:async Timer (with `.cancel()` and a Duration ctor)
// without needing a prefix everywhere.
import 'package:flame/components.dart' hide Timer;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../game/components/platform.dart';
import '../../game/jumping_jack_game.dart';
import '../../i18n/i18n.dart';
import '../../services/audio_manager.dart';
import '../../services/preferences.dart';
import '../theme/jack_design.dart';

/// Interactive onboarding overlay shown the very first time a new user
/// runs the solo mode. Two phases:
///
///   1. **Intro** — Jack greets the player through a sequence of speech
///      bubbles anchored above the cube. Everything except the cube is
///      dimmed by a circular spotlight so the player's attention is on
///      the character. Tap anywhere to advance to the next bubble.
///   2. **Coaching** — bubbles gone, dim retracted. A pulsing green
///      halo + dashed ring sits on the next target platform. A small
///      progress badge counts successful landings (`0/2`). After two
///      landings, [Preferences.tutorialCompleted] flips and the overlay
///      tears itself down.
///
/// While the overlay is up:
///   • [JumpingJackGame.tutorialCoachingActive] freezes the solo camera
///     (no time pressure for new users).
///   • [JumpingJackGame._checkDeath] respawns the player on the starting
///     platform on a fall instead of triggering the game-over flow.
///   • The pre-game `3-2-1` countdown is skipped in [JumpingJackGame._reset]
///     so Jack's bubbles take over the intro moment.
class TutorialOverlay extends StatefulWidget {
  const TutorialOverlay({super.key, required this.game});

  final JumpingJackGame game;

  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

enum _TutorialPhase { intro, coaching, outro, completed }

class _TutorialOverlayState extends State<TutorialOverlay>
    with TickerProviderStateMixin {
  /// Three successful landings — close, far, close — exercise both the
  /// short-charge / centred jump and the long-charge / off-axis aim
  /// without dragging the onboarding out.
  static const int _coachingTargetJumps = 3;

  /// Drives the halo pulse + the dashed-ring rotation during coaching,
  /// and the bubble's floating tail bob during intro.
  late final AnimationController _pulseCtrl;

  /// Slide+fade-in for each new bubble. Restarted on bubble advance.
  late final AnimationController _bubbleCtrl;

  /// Ticker re-build for the spotlight position so it tracks the cube
  /// even when the camera is technically frozen — needs to follow the
  /// initial mounting frames where the player's position hasn't been
  /// finalised yet.
  late final Ticker _ticker;

  _TutorialPhase _phase = _TutorialPhase.intro;
  int _bubbleIndex = 0;

  /// Number of consecutive landings on the highlighted target platform.
  /// Resets to 0 on a fall or on a landing on the wrong platform — the
  /// player must chain `_coachingTargetJumps` correct landings in a row
  /// to finish the tutorial.
  int _streak = 0;

  /// Last value of `gameState.platformsReached` observed by the
  /// coaching listener. Used to detect a brand-new landing (vs other
  /// state changes that also notify, e.g. combo timer ticks).
  int _lastPlatformsReached = 0;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
    _bubbleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    )..forward();
    _ticker = createTicker((_) {
      if (mounted) setState(() {});
    })..start();

    // First-time onboarding OR an explicit replay launched from the
    // home help dialog both need the full intro → coaching → outro
    // sequence. Anyone else lands in [completed] immediately so the
    // overlay is a no-op.
    if (Preferences.tutorialCompleted && !widget.game.tutorialReplay) {
      _phase = _TutorialPhase.completed;
      _ticker.stop();
      return;
    }
    widget.game.tutorialCoachingActive = true;
    widget.game.onCoachingRespawn = _onCoachingRespawn;
  }

  @override
  void dispose() {
    _detachCoachingListener();
    _pulseCtrl.dispose();
    _bubbleCtrl.dispose();
    _ticker.dispose();
    widget.game.tutorialCoachingActive = false;
    widget.game.onCoachingRespawn = null;
    super.dispose();
  }

  // ---- Intro ----

  void _advanceBubble() {
    final bubbles = I18n.t.tutorialIntroBubbles;
    AudioManager.click();
    if (_bubbleIndex < bubbles.length - 1) {
      setState(() => _bubbleIndex++);
      _bubbleCtrl.forward(from: 0);
    } else {
      _enterCoaching();
    }
  }

  void _enterCoaching() {
    _attachCoachingListener();
    setState(() => _phase = _TutorialPhase.coaching);
    _bubbleCtrl.forward(from: 0);
  }

  // ---- Coaching ----

  void _attachCoachingListener() {
    _lastPlatformsReached = widget.game.gameState.platformsReached;
    _streak = 0;
    widget.game.gameState.addListener(_onGameStateChanged);
  }

  void _detachCoachingListener() {
    widget.game.gameState.removeListener(_onGameStateChanged);
  }

  /// Fired every time the [GameState] notifies (combo ticks, jump
  /// landings, etc.). We only react when [GameState.platformsReached]
  /// has actually moved forward, which happens once per successful
  /// landing.
  ///
  /// Bienveillant flow — three outcomes:
  ///   • Landed on the highlighted target → streak++.
  ///   • Landed on the platform the player was already on (they tried
  ///     a jump but came back down on the same spot) → no-op so the
  ///     streak is preserved and no respawn shakes the camera.
  ///   • Anything else (a non-target platform, unexpected case) →
  ///     also no-op: we never demote progress mid-tutorial. The user
  ///     just stays where they landed and tries again.
  void _onGameStateChanged() {
    if (!mounted || _phase != _TutorialPhase.coaching) return;
    final current = widget.game.gameState.platformsReached;
    if (current == _lastPlatformsReached) return;
    _lastPlatformsReached = current;

    final expected = _expectedTargetPlatform();
    final landed = widget.game.player.lastLandedPlatform;
    if (expected != null && landed == expected) {
      _streak++;
      if (_streak >= _coachingTargetJumps) {
        _completeCoaching();
      } else {
        AudioManager.uiConfirm();
        setState(() {});
      }
    } else {
      // Landed somewhere that isn't the current target — most often
      // because the player came back down on the same platform they
      // launched from. Don't punish: just rebuild so the halo stays
      // anchored on the expected target.
      setState(() {});
    }
  }

  /// Called from [JumpingJackGame.respawnForCoaching] after a fall off
  /// the world. The game has already teleported the player back to
  /// their pre-jump platform; we just need to repaint the halo (the
  /// target hasn't changed, the streak is preserved).
  void _onCoachingRespawn() {
    if (!mounted || _phase != _TutorialPhase.coaching) return;
    setState(() {});
  }

  /// Currently-highlighted target. Index 0 is the starting platform,
  /// so the first target the player chases is `platforms[1]`, then 2,
  /// then 3 — advanced by [_streak] as they land correctly.
  Platform? _expectedTargetPlatform() {
    final platforms = widget.game.platforms;
    final idx = 1 + _streak;
    if (idx >= platforms.length) return null;
    return platforms[idx];
  }

  void _completeCoaching() {
    _detachCoachingListener();
    widget.game.onCoachingRespawn = null;
    Preferences.tutorialCompleted = true;
    AudioManager.uiConfirm();
    // Keep [tutorialCoachingActive] TRUE through the outro so the
    // camera stays frozen, no score / combo widgets pop in, and the
    // platform under the player can't get caught. The flag flips
    // false in [_finishOutro] right before the restart.
    setState(() => _phase = _TutorialPhase.outro);
    _bubbleCtrl.forward(from: 0);
  }

  /// Tears the overlay down. Two paths depending on how the player got
  /// here: a brand-new user gets handed off to a fresh run with the
  /// regular 3-2-1 PRÊT countdown; a returning user who came from the
  /// home's help dialog ("Rejouer le tutoriel") is popped straight back
  /// to the home — they only wanted to re-watch the lesson, not start
  /// a solo session. Idempotent so accidental double-taps don't fire
  /// the transition twice.
  void _finishOutro() {
    if (_phase != _TutorialPhase.outro) return;
    widget.game.tutorialCoachingActive = false;
    _ticker.stop();
    setState(() => _phase = _TutorialPhase.completed);
    if (widget.game.tutorialReplay) {
      // Replay flow — pop the GameScreen so the home re-emerges with
      // the latest stats and the (now-completed) tutorial flag.
      Navigator.of(context).maybePop();
      return;
    }
    // Fire-and-forget — the overlay is already in [completed] state and
    // won't touch the game again. `restart()` re-runs `_reset()` which
    // picks up `Preferences.tutorialCompleted = true` and arms the
    // standard 3-2-1 countdown.
    unawaited(widget.game.restart());
  }

  // ---- Geometry helpers ----

  Offset? _playerScreenCenter() {
    final p = widget.game.player;
    return widget.game.worldToScreen(
      Vector2(p.position.x, p.position.y - p.size.y / 2),
    );
  }

  Offset? _nextTargetCenter() {
    final p = _expectedTargetPlatform();
    if (p == null) return null;
    return widget.game.worldToScreen(
      Vector2(p.position.x + p.size.x / 2, p.topY),
    );
  }

  // ---- Build ----

  @override
  Widget build(BuildContext context) {
    switch (_phase) {
      case _TutorialPhase.completed:
        return const SizedBox.shrink();
      case _TutorialPhase.intro:
        return _buildIntro();
      case _TutorialPhase.coaching:
        return _buildCoaching();
      case _TutorialPhase.outro:
        return _buildOutro();
    }
  }

  Widget _buildOutro() {
    final playerCenter = _playerScreenCenter();
    final size = MediaQuery.of(context).size;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _finishOutro,
      child: Stack(
        children: [
          // Same spotlight treatment as the intro — anchors the eye on
          // Jack while the celebration line lands.
          Positioned.fill(
            child: CustomPaint(
              painter: _SpotlightPainter(
                center: playerCenter ??
                    Offset(size.width / 2, size.height / 2),
                radius: 80,
              ),
            ),
          ),
          if (playerCenter != null)
            _BubbleAnchor(
              anchorScreen: playerCenter,
              screenSize: size,
              child: AnimatedBuilder(
                animation: _bubbleCtrl,
                builder: (context, child) {
                  final t = Curves.easeOutBack.transform(_bubbleCtrl.value);
                  return Opacity(
                    opacity: _bubbleCtrl.value,
                    child: Transform.translate(
                      offset: Offset(0, 12 * (1 - t)),
                      child: Transform.scale(
                        scale: 0.92 + 0.08 * t,
                        child: child,
                      ),
                    ),
                  );
                },
                child: _SpeechBubble(
                  text: I18n.t.tutorialOutroBubble,
                  // Outro is a single line, no counter.
                  index: 0,
                  total: 1,
                  hideCounter: true,
                ),
              ),
            ),
          // "Tap to start" hint — same pulse + style as the intro
          // "Tap to continue" hint, but on the outro we wait for the
          // user before kicking off the real run (no auto-timer).
          Positioned(
            left: 0,
            right: 0,
            bottom: MediaQuery.of(context).padding.bottom + 28,
            child: AnimatedBuilder(
              animation: _pulseCtrl,
              builder: (context, child) {
                final t = (sin(_pulseCtrl.value * 2 * pi) * 0.5 + 0.5);
                return Opacity(opacity: 0.55 + 0.35 * t, child: child);
              },
              child: Center(
                child: Text(
                  I18n.t.tutorialTapToStart,
                  style: JackDesign.manrope(
                    fontSize: 11,
                    weight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 3,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIntro() {
    final bubbles = I18n.t.tutorialIntroBubbles;
    final playerCenter = _playerScreenCenter();
    final size = MediaQuery.of(context).size;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _advanceBubble,
      child: Stack(
        children: [
          // Spotlight dim — covers everything except a soft circle
          // around the player. Painted via saveLayer + BlendMode.clear
          // so the cube reads as the only well-lit element.
          Positioned.fill(
            child: CustomPaint(
              painter: _SpotlightPainter(
                center: playerCenter ?? Offset(size.width / 2, size.height / 2),
                radius: 72,
              ),
            ),
          ),
          // Speech bubble anchored above the cube.
          if (playerCenter != null)
            _BubbleAnchor(
              anchorScreen: playerCenter,
              screenSize: size,
              child: AnimatedBuilder(
                animation: _bubbleCtrl,
                builder: (context, child) {
                  final t =
                      Curves.easeOutBack.transform(_bubbleCtrl.value);
                  return Opacity(
                    opacity: _bubbleCtrl.value,
                    child: Transform.translate(
                      offset: Offset(0, 12 * (1 - t)),
                      child: Transform.scale(
                        scale: 0.92 + 0.08 * t,
                        child: child,
                      ),
                    ),
                  );
                },
                child: _SpeechBubble(
                  text: bubbles[_bubbleIndex],
                  index: _bubbleIndex,
                  total: bubbles.length,
                ),
              ),
            ),
          // "Tap to continue" hint at the bottom — uses the same pulse
          // controller as the bubble so the two cues feel coherent.
          Positioned(
            left: 0,
            right: 0,
            bottom: MediaQuery.of(context).padding.bottom + 28,
            child: AnimatedBuilder(
              animation: _pulseCtrl,
              builder: (context, child) {
                final t = (sin(_pulseCtrl.value * 2 * pi) * 0.5 + 0.5);
                return Opacity(
                  opacity: 0.55 + 0.35 * t,
                  child: child,
                );
              },
              child: Center(
                child: Text(
                  I18n.t.tutorialTapToContinue,
                  style: JackDesign.manrope(
                    fontSize: 11,
                    weight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 3,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoaching() {
    final done = _streak.clamp(0, _coachingTargetJumps);
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: [
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _pulseCtrl,
                builder: (context, _) => CustomPaint(
                  painter: _TargetHaloPainter(
                    target: _nextTargetCenter(),
                    pulse: _pulseCtrl.value,
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: _CoachingBadge(
                    done: done,
                    target: _coachingTargetJumps,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Positions [child] above the [anchorScreen] point on screen, falling
/// back below the anchor if there isn't enough room above. Centers the
/// child horizontally and clamps it inside [screenSize] with a 16 px
/// margin from each edge.
class _BubbleAnchor extends StatelessWidget {
  const _BubbleAnchor({
    required this.anchorScreen,
    required this.screenSize,
    required this.child,
  });
  final Offset anchorScreen;
  final Size screenSize;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Bubble sits ABOVE the cube by default. If the cube is too close
    // to the top edge (e.g. the player jumped while the bubble is
    // showing — shouldn't happen since the game's input is still live
    // but defensive), the bubble drops below the cube instead.
    const bubbleEstHeight = 130.0;
    const gap = 60.0; // space between anchor and bubble + tail allowance
    final above = anchorScreen.dy - bubbleEstHeight - gap > 0;
    final topAnchor = above
        ? anchorScreen.dy - bubbleEstHeight - gap
        : anchorScreen.dy + gap;
    return Positioned(
      top: topAnchor.clamp(40.0, screenSize.height - bubbleEstHeight - 40),
      left: 24,
      right: 24,
      child: Align(alignment: Alignment.center, child: child),
    );
  }
}

/// Cartoon-style speech bubble anchored above Jack. Dark rounded body
/// with a yellow border + bottom triangle tail. Displays a "n / total"
/// chip in the corner so the player can gauge how many bubbles remain.
class _SpeechBubble extends StatelessWidget {
  const _SpeechBubble({
    required this.text,
    required this.index,
    required this.total,
    this.hideCounter = false,
  });
  final String text;
  final int index;
  final int total;
  /// Suppresses the "n / total" chip in the corner. Used by the outro
  /// where the bubble is a single beat and the counter would feel like
  /// "you've still got steps left to do".
  final bool hideCounter;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: CustomPaint(
        painter: _SpeechTailPainter(),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
          decoration: BoxDecoration(
            color: JackDesign.bg.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: JackDesign.yellow, width: 2.2),
            boxShadow: [
              BoxShadow(
                color: JackDesign.yellow.withValues(alpha: 0.45),
                blurRadius: 18,
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  // Jack-flavoured marker — a small yellow rounded
                  // square stands in for the cube's identity inside
                  // the bubble (cheap + readable; full mascot would
                  // be visually busy at this size).
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: JackDesign.yellow,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: JackDesign.brown,
                        width: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'JACK',
                    style: JackDesign.bungee(
                      fontSize: 12,
                      color: JackDesign.yellow,
                      letterSpacing: 2,
                    ),
                  ),
                  const Spacer(),
                  if (!hideCounter)
                    Text(
                      '${index + 1} / $total',
                      style: JackDesign.manrope(
                        fontSize: 10,
                        weight: FontWeight.w800,
                        color: Colors.white.withValues(alpha: 0.55),
                        letterSpacing: 2,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                text,
                style: JackDesign.manrope(
                  fontSize: 14,
                  weight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 0.4,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Draws the downward-pointing triangle below the speech bubble. Lives
/// in a CustomPaint so it lines up perfectly with the bubble border
/// regardless of text length.
class _SpeechTailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const tailWidth = 18.0;
    const tailHeight = 12.0;
    final cx = size.width / 2;
    final baseY = size.height;
    final fill = Paint()..color = JackDesign.bg.withValues(alpha: 0.94);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeJoin = StrokeJoin.round
      ..color = JackDesign.yellow;
    final tail = Path()
      ..moveTo(cx - tailWidth / 2, baseY - 1)
      ..lineTo(cx, baseY + tailHeight)
      ..lineTo(cx + tailWidth / 2, baseY - 1);
    canvas.drawPath(tail, fill);
    canvas.drawPath(tail, stroke);
  }

  @override
  bool shouldRepaint(_SpeechTailPainter old) => false;
}

/// Dims the whole screen except a soft circle around [center]. Uses
/// saveLayer + BlendMode.clear so the spotlight cut-out has clean
/// alpha edges; the radial gradient feathers the boundary so the cube
/// doesn't get a hard-edged ring around it.
class _SpotlightPainter extends CustomPainter {
  _SpotlightPainter({required this.center, required this.radius});
  final Offset center;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.saveLayer(rect, Paint());
    canvas.drawRect(
      rect,
      Paint()..color = Colors.black.withValues(alpha: 0.68),
    );
    // Soft cut-out — radial gradient with full alpha at the centre that
    // falls off to zero past `radius`. Used with BlendMode.dstOut so
    // wherever the gradient is opaque it ERASES the dim above.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.black, Colors.black.withValues(alpha: 0.0)],
          stops: const [0.55, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: radius))
        ..blendMode = BlendMode.dstOut,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) =>
      old.center != center || old.radius != radius;
}

/// Small pill anchored at the top of the screen that tells the player
/// what to do and counts their progress.
class _CoachingBadge extends StatelessWidget {
  const _CoachingBadge({required this.done, required this.target});
  final int done;
  final int target;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: JackDesign.bg.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: JackDesign.green, width: 2),
        boxShadow: [
          BoxShadow(
            color: JackDesign.green.withValues(alpha: 0.55),
            blurRadius: 18,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.flag_rounded, size: 16, color: JackDesign.green),
          const SizedBox(width: 8),
          Text(
            I18n.t.tutorialCoaching(done, target),
            style: JackDesign.manrope(
              fontSize: 12,
              weight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// Pulsing green halo + rotating dashed ring on the next target.
class _TargetHaloPainter extends CustomPainter {
  _TargetHaloPainter({required this.target, required this.pulse});
  final Offset? target;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final t = target;
    if (t == null) return;
    final tWave = (sin(pulse * 2 * pi) * 0.5 + 0.5);
    final r = 22.0 + 14.0 * tWave;
    final alpha = (0.55 + 0.30 * tWave).clamp(0.0, 1.0);

    canvas.drawCircle(
      t,
      r + 6,
      Paint()
        ..color = JackDesign.green.withValues(alpha: 0.25 * alpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawCircle(
      t,
      r,
      Paint()..color = JackDesign.green.withValues(alpha: 0.18 * alpha),
    );
    canvas.drawCircle(
      t,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = JackDesign.green.withValues(alpha: alpha),
    );

    final dashRing = Rect.fromCircle(center: t, radius: r + 10);
    const dashCount = 8;
    final rotation = pulse * 2 * pi;
    for (var i = 0; i < dashCount; i++) {
      final start = rotation + (i / dashCount) * 2 * pi;
      const sweep = 0.20;
      canvas.drawArc(
        dashRing,
        start,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..color = JackDesign.greenHi.withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(_TargetHaloPainter old) =>
      old.target != target || old.pulse != pulse;
}
