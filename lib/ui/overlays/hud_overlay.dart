import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../game/config.dart';
import '../../game/jumping_jack_game.dart';
import '../../state/game_state.dart';
import '../theme/jack_design.dart';
import '../widgets/particle_score.dart';

class HudOverlay extends StatefulWidget {
  const HudOverlay({super.key, required this.game});

  final JumpingJackGame game;

  @override
  State<HudOverlay> createState() => _HudOverlayState();
}

class _HudOverlayState extends State<HudOverlay>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    // Drive a per-frame rebuild so the "PRÊT? 3-2-1-GO" countdown — which
    // lives on JumpingJackGame, not the GameState ChangeNotifier — stays
    // in sync visually. Cheap: the existing AnimatedBuilder structure
    // already short-circuits when the player isn't in the playing state.
    _ticker = createTicker((_) {
      if (mounted) setState(() {});
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    return AnimatedBuilder(
      animation: game.gameState,
      builder: (context, _) {
        final state = game.gameState;
        if (state.status != GameStatus.playing) return const SizedBox.shrink();
        return Stack(
          children: [
            // Safe-area-constrained HUD widgets (score, combo, timer)
            // stay inside SafeArea so the iPhone notch doesn't clip them.
            SafeArea(
              child: Stack(
                children: [
                  // Solo: dot-matrix score at the top. BR hides it in
                  // favour of the kill / event feed (rendered in the BR
                  // HUD overlay). Tutorial coaching also hides it — the
                  // new player has no points to track yet and the
                  // empty "0" would just look broken.
                  if (!game.isBattleRoyale && !game.tutorialCoachingActive)
                    Positioned(
                      top: 8,
                      left: 16,
                      right: 16,
                      child: Center(
                        child: ParticleScore(
                          score: state.score,
                          dotSize: 6,
                          digitGap: 6,
                          captionFontSize: 10,
                          captionLetterSpacing: 2.5,
                        ),
                      ),
                    ),
                  if (state.comboCount >= GameConfig.comboMinDisplay &&
                      !game.tutorialCoachingActive)
                    Positioned(
                      // BR has no score row at the top, so the combo
                      // slides up to the very edge and reads as a
                      // primary stat. Solo keeps its previous offset
                      // that clears the dot-matrix score line.
                      top: game.isBattleRoyale ? 12 : 90,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: _ComboBadge(
                          count: state.comboCount,
                          multiplier: state.comboMultiplier,
                          timerFraction: (state.comboTimerRemaining /
                                  GameConfig.comboWindow)
                              .clamp(0.0, 1.0),
                          frozen: state.comboFrozen,
                        ),
                      ),
                    ),
                  if (state.timerActive)
                    Positioned(
                      top: 90,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Text(
                          state.timerRemaining.toStringAsFixed(1),
                          style: TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w800,
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ],
                            color: state.timerRemaining <
                                    GameConfig.timerWarnThreshold
                                ? GameConfig.timerWarnColor
                                : GameConfig.timerColor,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Solo mode pre-game countdown ("PRÊT? 3 / 2 / 1 / GO"). Sits
            // OUTSIDE the SafeArea so the dim + "3" reach the very edges
            // of the iPhone screen (including the sliver around the
            // notch), mirroring the BR countdown's edge-to-edge behaviour.
            // BR ships its own countdown inside BrHudOverlay so don't
            // double-render here. The engine is paused while the tutorial
            // overlay is on top, so this stays frozen at "3" until the
            // tutorial is dismissed — exactly the order the user asked
            // for.
            if (!game.isBattleRoyale && game.preGame)
              Positioned.fill(
                child: _SoloCountdown(remaining: game.startCountdown),
              ),
          ],
        );
      },
    );
  }
}

/// Pre-match 3-2-1-GO countdown shown in solo. Same visual vocabulary
/// as the BR variant but yellow-tinted so the player reads the mode at a
/// glance. Locks the world so the player isn't surprised when their
/// first tap fires the launch.
class _SoloCountdown extends StatelessWidget {
  const _SoloCountdown({required this.remaining});
  final double remaining;

  @override
  Widget build(BuildContext context) {
    final n = remaining.ceil().clamp(1, 3);
    final isGo = remaining <= 0.4;
    return Container(
      color: Colors.black.withValues(alpha: 0.55),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'PRÊT ?',
              style: JackDesign.manrope(
                fontSize: 13,
                weight: FontWeight.w800,
                color: JackDesign.yellowHi,
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 18),
            TweenAnimationBuilder<double>(
              key: ValueKey<int>(isGo ? -1 : n),
              tween: Tween(begin: 1.4, end: 1.0),
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutBack,
              builder: (_, t, child) => Transform.scale(
                scale: t,
                child: Text(
                  isGo ? 'GO !' : '$n',
                  style: JackDesign.bungee(
                    fontSize: isGo ? 96 : 120,
                    color: Colors.white,
                    height: 1,
                    feature: const FontFeature.tabularFigures(),
                    shadows: [
                      Shadow(
                        color: JackDesign.yellow.withValues(alpha: 0.85),
                        blurRadius: 28,
                      ),
                      Shadow(
                        color: JackDesign.red.withValues(alpha: 0.45),
                        blurRadius: 50,
                      ),
                      const Shadow(
                        color: Colors.black,
                        offset: Offset(0, 6),
                      ),
                    ],
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

/// Punchy combo chip that pulses on each new chain step and escalates from
/// yellow → orange → red as the count climbs. Designed to make you feel
/// the momentum and want to chain another jump immediately.
class _ComboBadge extends StatefulWidget {
  const _ComboBadge({
    required this.count,
    required this.multiplier,
    required this.timerFraction,
    required this.frozen,
  });

  final int count;
  final double multiplier;
  final double timerFraction;
  final bool frozen;

  @override
  State<_ComboBadge> createState() => _ComboBadgeState();
}

class _ComboBadgeState extends State<_ComboBadge>
    with TickerProviderStateMixin {
  late final AnimationController _pop;
  late final AnimationController _idle;
  int _lastCount = 0;

  @override
  void initState() {
    super.initState();
    _pop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
    _idle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
    _lastCount = widget.count;
  }

  @override
  void didUpdateWidget(covariant _ComboBadge old) {
    super.didUpdateWidget(old);
    if (widget.count > _lastCount) {
      _pop
        ..reset()
        ..forward();
    }
    _lastCount = widget.count;
  }

  @override
  void dispose() {
    _pop.dispose();
    _idle.dispose();
    super.dispose();
  }

  /// Tier-based colour palette so each combo step looks visibly hotter.
  /// 2 = warm yellow, 3-4 = orange, 5+ = red, frozen = pink.
  ({Color top, Color mid, Color bottom, Color glow, Color border}) get _tier {
    if (widget.frozen) {
      return (
        top: const Color(0xFFFFC4D8),
        mid: const Color(0xFFFF6E94),
        bottom: const Color(0xFF7A1735),
        glow: const Color(0xFFFF6E94),
        border: const Color(0xFF7A1735),
      );
    }
    if (widget.count >= 5) {
      return (
        top: const Color(0xFFFFAFAD),
        mid: JackDesign.red,
        bottom: const Color(0xFFB22320),
        glow: JackDesign.red,
        border: const Color(0xFF6E1212),
      );
    }
    if (widget.count >= 3) {
      return (
        top: const Color(0xFFFFD08A),
        mid: JackDesign.mars,
        bottom: const Color(0xFFB04020),
        glow: JackDesign.mars,
        border: const Color(0xFF6E2310),
      );
    }
    return (
      top: JackDesign.yellowHi,
      mid: JackDesign.yellow,
      bottom: JackDesign.yellowDk,
      glow: JackDesign.yellow,
      border: JackDesign.brown,
    );
  }

  @override
  Widget build(BuildContext context) {
    final mult = widget.multiplier.toStringAsFixed(2);
    final t = _tier;

    return AnimatedBuilder(
      animation: Listenable.merge([_pop, _idle]),
      builder: (context, _) {
        // Pop pulse on increment: scale 1.35 → 1.0 with overshoot.
        final pop = _pop.isAnimating
            ? Curves.easeOutBack.transform(_pop.value)
            : 0.0;
        final scale = _pop.isAnimating ? 1.0 + 0.15 * (1.0 - pop) : 1.0;
        // Subtle idle breathing so it feels alive even when stable.
        final breathe = 1.0 + 0.012 * sin(_idle.value * 2 * pi);

        // Flash white burst at impact for the first 120 ms.
        final flash =
            _pop.isAnimating ? (1.0 - (_pop.value / 0.30)).clamp(0.0, 1.0) : 0.0;

        final timer = widget.frozen ? 1.0 : widget.timerFraction;
        // The bar warms up as it depletes — green-yellow when fresh, red at
        // the very end. Subtle but reinforces "jump now or lose it".
        final urgent = timer < 0.30;

        return Transform.scale(
          scale: scale * breathe,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(8, 2, 8, 3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [t.top, t.mid, t.bottom],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                  border: Border.all(color: t.border, width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: t.border.withValues(alpha: 0.85),
                      offset: const Offset(0, 1.5),
                      blurRadius: 0,
                    ),
                    BoxShadow(
                      color: t.glow.withValues(alpha: 0.18 + 0.20 * flash),
                      blurRadius: 6 + 6 * flash,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Glossy highlight (::before equivalent).
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: FractionallySizedBox(
                            heightFactor: 0.55,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.white.withValues(alpha: 0.45),
                                    Colors.white.withValues(alpha: 0.0),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // White flash on hit.
                    if (flash > 0)
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: Container(
                            color: Colors.white.withValues(alpha: 0.55 * flash),
                          ),
                        ),
                      ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          '×${widget.count}',
                          style: JackDesign.bungee(
                            fontSize: 12,
                            color: Colors.white,
                            letterSpacing: 0.4,
                            feature: const FontFeature.tabularFigures(),
                            shadows: [
                              Shadow(
                                color: t.border.withValues(alpha: 0.85),
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '×$mult',
                          style: JackDesign.bungee(
                            fontSize: 9,
                            color: Colors.white.withValues(alpha: 0.85),
                            feature: const FontFeature.tabularFigures(),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 3),
              // Discreet timer bar — thin, subtle, just enough to read the
              // remaining combo window.
              Container(
                width: 80,
                height: 3,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: timer.clamp(0.0, 1.0),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        decoration: BoxDecoration(
                          color: urgent ? JackDesign.red : t.mid,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
