import 'package:flutter/material.dart';

import '../../game/config.dart';
import '../../game/jumping_jack_game.dart';
import '../../state/game_state.dart';
import '../widgets/particle_score.dart';

class HudOverlay extends StatelessWidget {
  const HudOverlay({super.key, required this.game});

  final JumpingJackGame game;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: game.gameState,
      builder: (context, _) {
        final state = game.gameState;
        if (state.status != GameStatus.playing) return const SizedBox.shrink();
        return SafeArea(
          child: Stack(
            children: [
              Positioned(
                top: 8,
                left: 16,
                right: 16,
                child: Center(child: ParticleScore(score: state.score)),
              ),
              if (state.comboCount >= GameConfig.comboMinDisplay)
                Positioned(
                  top: 84,
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
                  top: 84,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Text(
                      state.timerRemaining.toStringAsFixed(1),
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: state.timerRemaining < GameConfig.timerWarnThreshold
                            ? GameConfig.timerWarnColor
                            : GameConfig.timerColor,
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

class _ComboBadge extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final mult = multiplier.toStringAsFixed(2);
    final accent = frozen ? const Color(0xFFFF6E94) : GameConfig.playerColor;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: '$count',
                style: TextStyle(
                  color: accent,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  shadows: [
                    Shadow(
                      color: accent.withValues(alpha: 0.4),
                      blurRadius: 12,
                    ),
                  ],
                ),
              ),
              const TextSpan(
                text: ' COMBO',
                style: TextStyle(
                  color: GameConfig.textColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 3,
                ),
              ),
              TextSpan(
                text: '  ×$mult',
                style: const TextStyle(
                  color: GameConfig.gaugeFgColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 120,
          height: 3,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: frozen ? 1.0 : timerFraction,
              backgroundColor: GameConfig.gaugeBgColor,
              valueColor: AlwaysStoppedAnimation(accent),
            ),
          ),
        ),
      ],
    );
  }
}
