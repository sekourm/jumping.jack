import 'package:flutter/material.dart';

import '../../game/jumping_jack_game.dart';
import '../../i18n/i18n.dart';
import '../../services/audio_manager.dart';
import '../../services/preferences.dart';
import '../../state/game_state.dart';
import '../theme/jack_design.dart';
import '../widgets/cosmic_background.dart';
import '../widgets/fortnite_button.dart';
import '../widgets/jack_ico.dart';
import '../widgets/jack_logo.dart';
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
              child: CosmicBackground(stage: JackStage.dark),
            ),
            Container(color: Colors.black.withValues(alpha: 0.55)),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 22,
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
    final showDelta = state.newBest ||
        (Preferences.bestScore > 0 && state.score < Preferences.bestScore);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _stagger(JackEndLogo(text: I18n.t.gameOver, gold: true), 0.0, 0.30),
        const SizedBox(height: 18),
        if (state.newBest) ...[
          _stagger(const _NewBestRibbon(), 0.15, 0.50),
          const SizedBox(height: 16),
        ],
        _stagger(
          _ScoreCard(
            score: state.score,
            bestScore: Preferences.bestScore,
            isNewBest: state.newBest,
            showDelta: showDelta,
          ),
          0.25,
          0.65,
        ),
        const SizedBox(height: 14),
        _stagger(_BestTile(score: Preferences.bestScore), 0.40, 0.80),
        const SizedBox(height: 28),
        _stagger(
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Row(
              // Same layout + color vocabulary as the Battle Royale end
              // screen so both result overlays read as one family: MENU
              // (cyan, secondary) on the left, REJOUER (epic / purple,
              // primary CTA) on the right.
              children: [
                Expanded(
                  child: FortniteButton(
                    label: I18n.t.menu,
                    icoName: IcoName.home,
                    style: FortniteButtonStyle.cyan,
                    height: 56,
                    fontSize: 14,
                    onPressed: () {
                      AudioManager.uiBack();
                      // Menu music restart is handled by home_screen's
                      // `.then` callback once GameScreen has actually
                      // been disposed. Calling playMenuMusic() here
                      // would race with GameScreen.dispose -> stopMusic
                      // and leave menu_loop frozen at a mid-fade volume.
                      Navigator.of(context).pop();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FortniteButton(
                    label: I18n.t.replay,
                    icoName: IcoName.play,
                    style: FortniteButtonStyle.epic,
                    height: 56,
                    fontSize: 14,
                    onPressed: () {
                      AudioManager.uiConfirm();
                      // Game.restart() handles the music switch internally.
                      game.restart();
                    },
                  ),
                ),
              ],
            ),
          ),
          0.55,
          1.00,
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
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) {
        final t = Curves.easeInOut.transform(_ctrl.value);
        return Transform.scale(
          scale: 1.0 + 0.04 * t,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              gradient: JackDesign.btnPrimary,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: JackDesign.brown, width: 2),
              boxShadow: [
                const BoxShadow(
                  color: JackDesign.brown,
                  offset: Offset(0, 3),
                ),
                BoxShadow(
                  color: JackDesign.yellow.withValues(alpha: 0.40),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Text(
              '★ ${I18n.t.newRecord} ★',
              style: JackDesign.bungee(
                fontSize: 12,
                color: JackDesign.brownInk,
                letterSpacing: 1.6,
              ),
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
    required this.showDelta,
  });
  final int score;
  final int bestScore;
  final bool isNewBest;
  final bool showDelta;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.04),
            Colors.black.withValues(alpha: 0.32),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: JackDesign.yellow.withValues(alpha: 0.28),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: JackDesign.yellow.withValues(alpha: 0.08),
            blurRadius: 24,
          ),
        ],
      ),
      child: Column(
        children: [
          ParticleScore(
            score: score,
            dotSize: 9,
            digitGap: 8,
            captionFontSize: 11,
            captionLetterSpacing: 2.5,
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
        style: JackDesign.manrope(
          fontSize: 11,
          weight: FontWeight.w800,
          color: JackDesign.green,
          letterSpacing: 2.5,
        ),
      );
    }
    final delta = bestScore - score;
    return Text(
      I18n.t.distanceFromRecord(delta),
      style: JackDesign.manrope(
        fontSize: 11,
        weight: FontWeight.w800,
        color: Colors.white.withValues(alpha: 0.70),
        letterSpacing: 2.0,
      ),
    );
  }
}

class _BestTile extends StatelessWidget {
  const _BestTile({required this.score});
  final int score;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.04),
            Colors.black.withValues(alpha: 0.30),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.10),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: JackDesign.yellow.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Center(
              child: JackIco(
                name: IcoName.trophy,
                size: 18,
                color: JackDesign.yellow,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              I18n.t.bestLabel,
              style: JackDesign.manrope(
                fontSize: 11,
                weight: FontWeight.w800,
                color: Colors.white.withValues(alpha: 0.70),
                letterSpacing: 2.5,
              ),
            ),
          ),
          Text(
            '$score',
            style: JackDesign.bungee(
              fontSize: 22,
              color: JackDesign.yellow,
              feature: const FontFeature.tabularFigures(),
            ),
          ),
        ],
      ),
    );
  }
}
