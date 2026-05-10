import 'package:flutter/material.dart';

import '../../game/jumping_jack_game.dart';
import '../../i18n/i18n.dart';
import '../../services/audio_manager.dart';
import '../../services/battle_royale_service.dart';
import '../../services/preferences.dart';
import '../screens/lobby_screen.dart';
import '../theme/jack_design.dart';
import '../widgets/cosmic_background.dart';
import '../widgets/fortnite_button.dart';
import '../widgets/jack_ico.dart';
import '../widgets/jack_logo.dart';
import '../widgets/jack_mascot.dart';

/// Battle Royale result overlay. Two states:
///   1. The local player just died — choose Quitter or Spectateur.
///   2. The match is finished (last player standing) — show the winner big
///      with their character and a sorted leaderboard.
///
/// Final state is held back for 2 s after the BR phase becomes finished so
/// the win celebration overlay (slow-mo + zoom + WINNER text) can play.
class BrResultOverlay extends StatefulWidget {
  const BrResultOverlay({super.key, required this.game});

  final JumpingJackGame game;

  @override
  State<BrResultOverlay> createState() => _BrResultOverlayState();
}

class _BrResultOverlayState extends State<BrResultOverlay> {
  bool _wasFinished = false;
  bool _celebrationDone = false;

  @override
  void initState() {
    super.initState();
    BattleRoyaleService.instance.addListener(_onBrChanged);
  }

  @override
  void dispose() {
    BattleRoyaleService.instance.removeListener(_onBrChanged);
    super.dispose();
  }

  void _onBrChanged() {
    final svc = BattleRoyaleService.instance;
    final isFinished = svc.phase == BrPhase.finished;
    if (isFinished && !_wasFinished) {
      _wasFinished = true;
      // Belt-and-suspenders: ensure Preferences.brWins is bumped before the
      // user can dismiss the result overlay. The service already triggers
      // this from both the local and realtime end-condition paths, but if a
      // race pushed the realtime broadcast past the moment the user taps
      // "back to menu", the home would re-render with the stale count.
      svc.commitFinalWinIfNeeded();
      // 3 s celebration window before the result screen appears — matches
      // the in-game win sequence (`brWinSequenceDuration`) so the camera
      // zoom on the winner and the VICTOIRE / DÉFAITE banner finish at the
      // same instant the leaderboard slides in.
      Future<void>.delayed(const Duration(milliseconds: 3050), () {
        if (!mounted) return;
        setState(() => _celebrationDone = true);
      });
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final svc = BattleRoyaleService.instance;
    return Builder(
      builder: (context) {
        final showDeathChoice =
            svc.myDead && !svc.spectator && svc.phase == BrPhase.playing;
        final showFinal =
            svc.phase == BrPhase.finished && _celebrationDone;
        // Celebration window: phase has flipped to finished but we're still
        // in the 3 s zoom-on-the-winner sequence. Don't draw the dimmed
        // backdrop or leaderboard — just float a big VICTOIRE / DÉFAITE
        // banner so the moment lands.
        final showCelebration =
            svc.phase == BrPhase.finished && !_celebrationDone;
        if (!showDeathChoice && !showFinal && !showCelebration) {
          return const SizedBox.shrink();
        }
        final iWon = svc.winnerId == Preferences.playerId;
        if (showCelebration) {
          // Only celebrate the winner — losers slide straight into the
          // leaderboard once the camera zoom finishes, no "TU ES TOMBÉ"
          // banner clogging the screen.
          if (!iWon) return const SizedBox.shrink();
          return const IgnorePointer(
            child: _VictoryBanner(),
          );
        }
        return Stack(
          children: [
            Positioned.fill(
              child: CosmicBackground(
                stage: showFinal && iWon ? JackStage.nebula : JackStage.dark,
              ),
            ),
            Container(color: Colors.black.withValues(alpha: 0.55)),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 24,
                          ),
                          child: ConstrainedBox(
                            constraints:
                                const BoxConstraints(maxWidth: 380),
                            child: showFinal
                                ? _FinalResult(
                                    svc: svc,
                                    iWon: iWon,
                                    onLeave: () => _leave(context),
                                    onReplay: () => _replay(context),
                                  )
                                : _DeathChoice(
                                    svc: svc,
                                    onLeave: () => _leave(context),
                                    onSpectate: () {
                                      AudioManager.click();
                                      svc.becomeSpectator();
                                    },
                                  ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _leave(BuildContext context) async {
    AudioManager.click();
    // Last chance to record the win — safe to call repeatedly (guarded by
    // the service's `_myWinRecorded` flag). Catches the edge case where
    // the user reaches the result screen before any end-condition path
    // has run, e.g. very fast dismissal during the celebration banner.
    BattleRoyaleService.instance.commitFinalWinIfNeeded();
    await BattleRoyaleService.instance.leaveMatch();
    BattleRoyaleService.resetInstance();
    if (!context.mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _replay(BuildContext context) async {
    AudioManager.click();
    BattleRoyaleService.instance.commitFinalWinIfNeeded();
    await BattleRoyaleService.instance.leaveMatch();
    BattleRoyaleService.resetInstance();
    if (!context.mounted) return;
    final navigator = Navigator.of(context);
    navigator.popUntil((r) => r.isFirst);
    navigator.push(
      PageRouteBuilder<void>(
        pageBuilder: (_, a, b) => const LobbyScreen(),
        transitionDuration: const Duration(milliseconds: 200),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        transitionsBuilder: (_, animation, b, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }
}

/// Big VICTOIRE banner shown for the 3 s celebration window while the
/// in-game camera zooms on the winner. Fades + scales in, holds, then
/// fades out so the leaderboard transition feels smooth instead of a
/// hard cut. Only rendered for the local winner — losers see no banner
/// and go straight to the ranking.
class _VictoryBanner extends StatefulWidget {
  const _VictoryBanner();

  @override
  State<_VictoryBanner> createState() => _VictoryBannerState();
}

class _VictoryBannerState extends State<_VictoryBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3000),
  )..forward();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        // Three-stage envelope: fade-in (0 → 0.25), hold (0.25 → 0.80),
        // fade-out (0.80 → 1.0). The scale punches up on entrance with a
        // slight overshoot for a celebratory feel.
        final t = _ctrl.value;
        final fadeIn = (t / 0.25).clamp(0.0, 1.0);
        final fadeOut = ((1.0 - t) / 0.20).clamp(0.0, 1.0);
        final alpha = (fadeIn * fadeOut).clamp(0.0, 1.0);
        final entranceT = Curves.easeOutBack.transform(fadeIn);
        final scale = 0.6 + 0.4 * entranceT;

        return Center(
          child: Opacity(
            opacity: alpha,
            child: Transform.scale(
              scale: scale,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: JackEndLogo(
                  text: I18n.t.victory,
                  gold: true,
                  fontSize: 64,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DeathChoice extends StatelessWidget {
  const _DeathChoice({
    required this.svc,
    required this.onLeave,
    required this.onSpectate,
  });

  final BattleRoyaleService svc;
  final VoidCallback onLeave;
  final VoidCallback onSpectate;

  @override
  Widget build(BuildContext context) {
    final rank = svc.myFinalRank;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        JackEndLogo(text: I18n.t.youFell, gold: false, fontSize: 48),
        const SizedBox(height: 16),
        if (rank != null)
          Text(
            I18n.t.position(rank, BattleRoyaleService.maxPlayers),
            style: JackDesign.manrope(
              fontSize: 12,
              weight: FontWeight.w800,
              color: Colors.white.withValues(alpha: 0.70),
              letterSpacing: 2.5,
            ),
          ),
        const SizedBox(height: 6),
        Text(
          I18n.t.survivors(svc.aliveCount),
          style: JackDesign.manrope(
            fontSize: 11,
            weight: FontWeight.w800,
            color: Colors.white.withValues(alpha: 0.50),
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(height: 32),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: FortniteButton(
            label: I18n.t.staySpectator,
            icoName: IcoName.eye,
            style: FortniteButtonStyle.epic,
            onPressed: onSpectate,
            height: 56,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: FortniteButton(
            label: I18n.t.quit,
            icoName: IcoName.close,
            style: FortniteButtonStyle.cyan,
            onPressed: onLeave,
            height: 52,
            fontSize: 15,
          ),
        ),
      ],
    );
  }
}

class _FinalResult extends StatefulWidget {
  const _FinalResult({
    required this.svc,
    required this.iWon,
    required this.onLeave,
    required this.onReplay,
  });
  final BattleRoyaleService svc;
  final bool iWon;
  final VoidCallback onLeave;
  final VoidCallback onReplay;

  @override
  State<_FinalResult> createState() => _FinalResultState();
}

class _FinalResultState extends State<_FinalResult>
    with SingleTickerProviderStateMixin {
  // Same block-by-block reveal as the solo death overlay — each section
  // fades + slides in within its own slice of the timeline.
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
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
    final myId = Preferences.playerId;
    final svc = widget.svc;
    final iWon = widget.iWon;
    final board = svc.leaderboardSnapshot();
    final winner = svc.winnerId == null
        ? null
        : board.firstWhere(
            (e) => e.player.playerId == svc.winnerId,
            orElse: () => board.first,
          );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // No big "VICTOIRE" title here — the celebration banner already
        // showed it during the win sequence. The portrait's "GAGNANT" label
        // is enough context on the leaderboard.
        if (winner != null) ...[
          _stagger(
            _WinnerPortrait(
              name: winner.player.name,
              score: winner.score,
              iWon: iWon,
              color: slotColor(winner.player.slotIndex),
              // We only know the BR wins count for the local player —
              // other players' lifetime stats aren't broadcast.
              brWins: iWon ? Preferences.brWins : 0,
            ),
            0.0,
            0.35,
          ),
        ],
        const SizedBox(height: 22),
        _stagger(
          _RankingCard(board: board, myId: myId),
          0.30,
          0.70,
        ),
        const SizedBox(height: 26),
        _stagger(
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Row(
              children: [
                Expanded(
                  child: FortniteButton(
                    // Short labels — the side-by-side layout doesn't have
                    // room for "RETOUR AU MENU" / "NOUVELLE PARTIE" at this
                    // font size without overflowing.
                    label: I18n.t.menu,
                    icoName: IcoName.home,
                    style: FortniteButtonStyle.cyan,
                    onPressed: widget.onLeave,
                    height: 56,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FortniteButton(
                    label: I18n.t.replay,
                    icoName: IcoName.flame,
                    style: FortniteButtonStyle.epic,
                    onPressed: widget.onReplay,
                    height: 56,
                    fontSize: 14,
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

class _WinnerPortrait extends StatelessWidget {
  const _WinnerPortrait({
    required this.name,
    required this.score,
    required this.iWon,
    required this.color,
    required this.brWins,
  });
  final String name;
  final int score;
  final bool iWon;
  final Color color;
  /// Lifetime BR wins for the winner (only known for the local player).
  /// 0 hides the badge.
  final int brWins;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            JackMascot(
              size: 92,
              face: iWon ? MascotFace.excited : MascotFace.smile,
              glow: true,
              bodyColor: color,
            ),
            Positioned(
              top: -6,
              right: -6,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: JackDesign.btnPrimary,
                  border: Border.all(color: JackDesign.brown, width: 2),
                ),
                alignment: Alignment.center,
                child: Text(
                  '1',
                  style: JackDesign.bungee(
                    fontSize: 13,
                    color: JackDesign.brownInk,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              I18n.t.winnerLabel,
              style: JackDesign.manrope(
                fontSize: 9,
                weight: FontWeight.w800,
                color: Colors.white.withValues(alpha: 0.50),
                letterSpacing: 2.0,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    name,
                    style: JackDesign.bungee(
                      fontSize: 18,
                      color: Colors.white,
                      letterSpacing: 0.6,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (brWins > 0) ...[
                  const SizedBox(width: 8),
                  _BrWinsBadge(count: brWins),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '$score',
              style: JackDesign.bungee(
                fontSize: 24,
                color: JackDesign.yellow,
                feature: const FontFeature.tabularFigures(),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Small purple badge showing how many Battle Royales the winner has won
/// in their lifetime (`Preferences.brWins`). Sits next to the winner's
/// name on the BR result screen.
class _BrWinsBadge extends StatelessWidget {
  const _BrWinsBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: JackDesign.purple.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: JackDesign.purple, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.local_fire_department_rounded,
            color: JackDesign.purpleHi,
            size: 12,
          ),
          const SizedBox(width: 4),
          Text(
            '$count',
            style: JackDesign.bungee(
              fontSize: 11,
              color: JackDesign.purpleHi,
              feature: const FontFeature.tabularFigures(),
            ),
          ),
        ],
      ),
    );
  }
}

class _RankingCard extends StatelessWidget {
  const _RankingCard({required this.board, required this.myId});
  final List<({
    BrPlayer player,
    int score,
    bool alive,
    int? placement,
    int kills,
    Duration? survivalTime,
  })> board;
  final String myId;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
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
          color: Colors.white.withValues(alpha: 0.10),
          width: 1.5,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              I18n.t.ranking,
              style: JackDesign.manrope(
                fontSize: 10,
                weight: FontWeight.w800,
                color: Colors.white.withValues(alpha: 0.50),
                letterSpacing: 2.5,
              ),
            ),
          ),
          for (var i = 0; i < board.length; i++) ...[
            if (i > 0) const SizedBox(height: 6),
            _LbRow(
              rank: i + 1,
              entry: board[i],
              isMe: board[i].player.playerId == myId,
            ),
          ],
        ],
      ),
    );
  }
}

class _LbRow extends StatelessWidget {
  const _LbRow({
    required this.rank,
    required this.entry,
    required this.isMe,
  });
  final int rank;
  final ({
    BrPlayer player,
    int score,
    bool alive,
    int? placement,
    int kills,
    Duration? survivalTime,
  }) entry;
  final bool isMe;

  String _formatTime(Duration? d) {
    if (d == null) return '—';
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    if (m > 0) {
      return '${m}m${s.toString().padLeft(2, '0')}s';
    }
    return '${s}s';
  }

  Color _rankColor() {
    switch (rank) {
      case 1:
        return const Color(0xFFFFD24A);
      case 2:
        return const Color(0xFFC0C8D2);
      case 3:
        return const Color(0xFFC18A4F);
      default:
        return const Color(0xFF7E889A);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rankColor = _rankColor();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isMe
            ? JackDesign.yellow.withValues(alpha: 0.10)
            : Colors.black.withValues(alpha: 0.40),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isMe
              ? JackDesign.yellow
              : Colors.white.withValues(alpha: 0.06),
          width: 1,
        ),
      ),
      child: Opacity(
        opacity: entry.alive ? 1.0 : 0.55,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: rank <= 3
                        ? rankColor
                        : Colors.white.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$rank',
                    style: JackDesign.bungee(
                      fontSize: 11,
                      color: rank <= 3
                          ? const Color(0xFF1A1A1A)
                          : Colors.white.withValues(alpha: 0.60),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    entry.player.name,
                    style: JackDesign.bungee(
                      fontSize: 12,
                      color: Colors.white,
                      letterSpacing: 0.6,
                    ).copyWith(
                      decoration: entry.alive
                          ? TextDecoration.none
                          : TextDecoration.lineThrough,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(5),
                      border:
                          Border.all(color: JackDesign.yellow, width: 1.5),
                    ),
                    child: Text(
                      I18n.t.you,
                      style: JackDesign.bungee(
                        fontSize: 9,
                        color: JackDesign.yellow,
                        letterSpacing: 1.6,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 10),
                Text(
                  '${entry.score}',
                  style: JackDesign.bungee(
                    fontSize: 14,
                    color: Colors.white,
                    feature: const FontFeature.tabularFigures(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Stat strip — kills, survival time. Uses small icons + chunky
            // numbers for at-a-glance readability.
            Padding(
              padding: const EdgeInsets.only(left: 32),
              child: Row(
                children: [
                  _StatPill(
                    icon: Icons.adjust,
                    label: '${entry.kills}',
                    color: const Color(0xFFFF6E94),
                  ),
                  const SizedBox(width: 8),
                  _StatPill(
                    icon: Icons.timer_outlined,
                    label: _formatTime(entry.survivalTime),
                    color: JackDesign.cyan,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact stat pill (icon-or-glyph + Bungee number) used in BR rows.
/// Provide either [icon] (Material) or [text] (e.g. an "✕" glyph).
class _StatPill extends StatelessWidget {
  const _StatPill({
    this.icon,
    this.text,
    required this.label,
    required this.color,
  }) : assert(icon != null || text != null);
  final IconData? icon;
  final String? text;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.45), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (text != null)
            Text(
              text!,
              style: JackDesign.bungee(
                fontSize: 11,
                color: color,
              ),
            )
          else
            Icon(icon, color: color, size: 11),
          const SizedBox(width: 4),
          Text(
            label,
            style: JackDesign.bungee(
              fontSize: 10,
              color: color,
              feature: const FontFeature.tabularFigures(),
            ),
          ),
        ],
      ),
    );
  }
}
