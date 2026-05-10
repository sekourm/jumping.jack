import 'package:flutter/material.dart';

import '../../game/config.dart';
import '../../game/jumping_jack_game.dart';
import '../../i18n/i18n.dart';
import '../../services/audio_manager.dart';
import '../../services/preferences.dart';
import '../../state/game_state.dart';
import '../widgets/cosmic_background.dart';
import '../widgets/fortnite_button.dart';
import '../widgets/particle_score.dart';

class DeathOverlay extends StatelessWidget {
  const DeathOverlay({super.key, required this.game});

  final JumpingJackGame game;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: game.gameState,
      builder: (context, _) {
        final state = game.gameState;
        if (state.status != GameStatus.dead) return const SizedBox.shrink();
        return Stack(
          children: [
            Positioned.fill(
              child: CosmicBackground(platforms: state.platformsReached),
            ),
            Container(color: Colors.black.withValues(alpha: 0.55)),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 28,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 380),
                    child: _DeathContent(game: game, state: state),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Stateful so the entrance animation only plays once per death (not on
/// every parent rebuild driven by GameState ticks).
class _DeathContent extends StatefulWidget {
  const _DeathContent({required this.game, required this.state});
  final JumpingJackGame game;
  final GameState state;

  @override
  State<_DeathContent> createState() => _DeathContentState();
}

class _DeathContentState extends State<_DeathContent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 750),
  )..forward();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Widget _stagger(Widget child, double startAt, double endAt) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final raw = ((_ctrl.value - startAt) / (endAt - startAt))
            .clamp(0.0, 1.0);
        final eased = Curves.easeOutCubic.transform(raw);
        return Opacity(
          opacity: eased,
          child: Transform.translate(
            offset: Offset(0, (1 - eased) * 14),
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final game = widget.game;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _stagger(const _GameOverTitle(), 0.0, 0.30),
        const SizedBox(height: 22),
        if (state.newBest) ...[
          _stagger(const _NewBestRibbon(), 0.15, 0.50),
          const SizedBox(height: 16),
        ],
        _stagger(
          _ScoreCard(
            score: state.score,
            bestScore: Preferences.bestScore,
            isNewBest: state.newBest,
          ),
          0.25,
          0.60,
        ),
        const SizedBox(height: 14),
        _stagger(
          _BestTile(score: Preferences.bestScore),
          0.40,
          0.75,
        ),
        const SizedBox(height: 28),
        _stagger(
          FortniteButton(
            label: I18n.t.replay,
            icon: Icons.replay_rounded,
            height: 60,
            onPressed: () {
              AudioManager.click();
              AudioManager.startGameMusic();
              game.restart();
            },
          ),
          0.55,
          0.90,
        ),
        const SizedBox(height: 12),
        _stagger(
          FortniteButton(
            label: I18n.t.menu,
            icon: Icons.home_rounded,
            style: FortniteButtonStyle.secondary,
            height: 56,
            fontSize: 16,
            onPressed: () {
              AudioManager.click();
              AudioManager.startMenuMusic();
              Navigator.of(context).pop();
            },
          ),
          0.65,
          1.00,
        ),
      ],
    );
  }
}

class _GameOverTitle extends StatelessWidget {
  const _GameOverTitle();

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Text(
          I18n.t.gameOver,
          style: TextStyle(
            fontSize: 44,
            fontWeight: FontWeight.w900,
            letterSpacing: 6,
            height: 1,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 6
              ..color = Colors.black.withValues(alpha: 0.85),
          ),
        ),
        ShaderMask(
          shaderCallback: (rect) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFFFE198),
              Color(0xFFFFC857),
              Color(0xFFFF9C2A),
            ],
            stops: [0.0, 0.55, 1.0],
          ).createShader(rect),
          child: Text(
            I18n.t.gameOver,
            style: TextStyle(
              fontSize: 44,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 6,
              height: 1,
              shadows: [
                Shadow(
                  color: GameConfig.playerColor.withValues(alpha: 0.65),
                  blurRadius: 22,
                ),
                Shadow(
                  color: GameConfig.playerColor.withValues(alpha: 0.30),
                  blurRadius: 44,
                ),
                const Shadow(
                  color: Colors.black87,
                  blurRadius: 8,
                  offset: Offset(0, 4),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _NewBestRibbon extends StatefulWidget {
  const _NewBestRibbon();

  @override
  State<_NewBestRibbon> createState() => _NewBestRibbonState();
}

class _NewBestRibbonState extends State<_NewBestRibbon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = GameConfig.playerColor;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_ctrl.value);
        final glow = 16.0 + 14.0 * t;
        final scale = 1.0 + 0.04 * t;
        return Transform.scale(
          scale: scale,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.65),
                  blurRadius: glow,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.emoji_events,
                  color: GameConfig.bgColor,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Text(
                  I18n.t.newRecord,
                  style: const TextStyle(
                    color: GameConfig.bgColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({
    required this.score,
    required this.bestScore,
    required this.isNewBest,
  });
  final int score;
  final int bestScore;
  final bool isNewBest;

  @override
  Widget build(BuildContext context) {
    final showDelta = isNewBest || (bestScore > 0 && score < bestScore);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.10),
          width: 1.4,
        ),
      ),
      child: Column(
        children: [
          ParticleScore(
            score: score,
            dotSize: 8,
            digitGap: 7,
            captionFontSize: 12,
            captionLetterSpacing: 7,
            captionGap: 8,
          ),
          if (showDelta) ...[
            const SizedBox(height: 14),
            _DeltaLine(
              score: score,
              bestScore: bestScore,
              isNewBest: isNewBest,
            ),
          ],
        ],
      ),
    );
  }
}

class _DeltaLine extends StatelessWidget {
  const _DeltaLine({
    required this.score,
    required this.bestScore,
    required this.isNewBest,
  });
  final int score;
  final int bestScore;
  final bool isNewBest;

  @override
  Widget build(BuildContext context) {
    if (isNewBest) {
      return Text(
        I18n.t.recordBeaten,
        style: TextStyle(
          color: GameConfig.playerColor,
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: 4,
        ),
      );
    }
    final delta = bestScore - score;
    return Text(
      I18n.t.distanceFromRecord(delta),
      style: const TextStyle(
        color: GameConfig.textMuted,
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 3,
      ),
    );
  }
}

class _BestTile extends StatelessWidget {
  const _BestTile({required this.score});
  final int score;

  @override
  Widget build(BuildContext context) {
    final accent = GameConfig.playerColor;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: accent.withValues(alpha: 0.22),
          width: 1.2,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                Icons.emoji_events,
                color: accent.withValues(alpha: 0.9),
                size: 18,
              ),
              const SizedBox(width: 10),
              Text(
                I18n.t.bestLabel,
                style: TextStyle(
                  color: accent.withValues(alpha: 0.9),
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.5,
                ),
              ),
            ],
          ),
          Text(
            '$score',
            style: TextStyle(
              color: accent,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

