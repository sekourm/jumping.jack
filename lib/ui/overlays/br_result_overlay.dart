import 'package:flutter/material.dart';

import '../../game/config.dart';
import '../../game/jumping_jack_game.dart';
import '../../i18n/i18n.dart';
import '../../services/audio_manager.dart';
import '../../services/battle_royale_service.dart';
import '../../services/preferences.dart';
import '../screens/lobby_screen.dart';
import '../widgets/cosmic_background.dart';
import '../widgets/fortnite_button.dart';

/// Battle Royale result overlay. Two states:
///   1. The local player just died — choose Quitter or Spectateur.
///   2. The match is finished (last player standing) — show the winner big
///      with their character and a sorted leaderboard.
class BrResultOverlay extends StatelessWidget {
  const BrResultOverlay({super.key, required this.game});

  final JumpingJackGame game;

  // Per-slot accent colour, must match the BR HUD palette.
  static const slotColors = <Color>[
    GameConfig.playerColor,
    Color(0xFF6CD8FF),
    Color(0xFFFF6E94),
    Color(0xFF7AE091),
    Color(0xFFFFA64C),
  ];

  @override
  Widget build(BuildContext context) {
    final svc = BattleRoyaleService.instance;
    return AnimatedBuilder(
      animation: svc,
      builder: (context, _) {
        final showDeathChoice =
            svc.myDead && !svc.spectator && svc.phase == BrPhase.playing;
        final showFinal = svc.phase == BrPhase.finished;
        if (!showDeathChoice && !showFinal) {
          return const SizedBox.shrink();
        }
        return Stack(
          children: [
            Positioned.fill(child: CosmicBackground(platforms: 100)),
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
    await BattleRoyaleService.instance.leaveMatch();
    BattleRoyaleService.resetInstance();
    if (!context.mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  /// Tear the current match down then jump straight back into the
  /// matchmaking lobby for another round.
  Future<void> _replay(BuildContext context) async {
    AudioManager.click();
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
        _GradientTitle(I18n.t.youFell),
        const SizedBox(height: 16),
        if (rank != null)
          Text(
            I18n.t.position(rank, BattleRoyaleService.maxPlayers),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 4,
            ),
          ),
        const SizedBox(height: 6),
        Text(
          I18n.t.survivors(svc.aliveCount),
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 12,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 32),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: FortniteButton(
            label: I18n.t.staySpectator,
            icon: Icons.visibility_rounded,
            style: FortniteButtonStyle.epic,
            onPressed: onSpectate,
            height: 54,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: FortniteButton(
            label: I18n.t.quit,
            icon: Icons.close_rounded,
            style: FortniteButtonStyle.secondary,
            onPressed: onLeave,
            height: 50,
            fontSize: 15,
          ),
        ),
      ],
    );
  }
}

class _FinalResult extends StatelessWidget {
  const _FinalResult({
    required this.svc,
    required this.onLeave,
    required this.onReplay,
  });
  final BattleRoyaleService svc;
  final VoidCallback onLeave;
  final VoidCallback onReplay;

  @override
  Widget build(BuildContext context) {
    final myId = Preferences.playerId;
    final iWon = svc.winnerId == myId;
    final board = svc.leaderboardSnapshot();
    final winner = svc.winnerId == null
        ? null
        : board.firstWhere(
            (e) => e.player.playerId == svc.winnerId,
            orElse: () => board.first,
          );
    final winnerColor = winner == null
        ? GameConfig.playerColor
        : BrResultOverlay.slotColors[
            winner.player.slotIndex.clamp(
              0,
              BrResultOverlay.slotColors.length - 1,
            )
          ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _GradientTitle(
          iWon ? I18n.t.victory : I18n.t.matchOverTitle,
          accent: iWon ? GameConfig.playerColor : const Color(0xFFB14BFF),
        ),
        const SizedBox(height: 22),
        if (winner != null) ...[
          _CubeAvatar(color: winnerColor, happy: iWon, size: 100),
          const SizedBox(height: 14),
          Text(
            iWon ? I18n.t.youWin : I18n.t.winnerWins(winner.player.name),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: winnerColor,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 3,
              shadows: [
                Shadow(
                  color: winnerColor.withValues(alpha: 0.55),
                  blurRadius: 14,
                ),
                const Shadow(
                  color: Colors.black87,
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${winner.score} ${I18n.t.pointsShort}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
        const SizedBox(height: 26),
        _Leaderboard(board: board, myId: myId),
        const SizedBox(height: 26),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: FortniteButton(
            label: I18n.t.replayBattleRoyale,
            icon: Icons.local_fire_department_rounded,
            style: FortniteButtonStyle.epic,
            onPressed: onReplay,
            height: 54,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: FortniteButton(
            label: I18n.t.backToMenu,
            icon: Icons.home_rounded,
            style: FortniteButtonStyle.secondary,
            onPressed: onLeave,
            height: 50,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}

class _Leaderboard extends StatelessWidget {
  const _Leaderboard({required this.board, required this.myId});
  final List<({BrPlayer player, int score, bool alive, int? placement})>
      board;
  final String myId;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.10),
          width: 1.4,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < board.length; i++)
            _LeaderRow(
              rank: i + 1,
              entry: board[i],
              isMe: board[i].player.playerId == myId,
            ),
        ],
      ),
    );
  }
}

class _LeaderRow extends StatelessWidget {
  const _LeaderRow({
    required this.rank,
    required this.entry,
    required this.isMe,
  });
  final int rank;
  final ({BrPlayer player, int score, bool alive, int? placement}) entry;
  final bool isMe;

  Color _rankColor() {
    switch (rank) {
      case 1:
        return const Color(0xFFFFD24A);
      case 2:
        return const Color(0xFFCFD8E0);
      case 3:
        return const Color(0xFFD58A3E);
      default:
        return Colors.white38;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = BrResultOverlay.slotColors[
      entry.player.slotIndex
          .clamp(0, BrResultOverlay.slotColors.length - 1)
    ];
    final rankColor = _rankColor();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '$rank',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: rankColor,
                fontSize: 16,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: entry.alive ? color : Colors.white24,
              shape: BoxShape.circle,
              boxShadow: entry.alive
                  ? [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6)]
                  : null,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              entry.player.name,
              style: TextStyle(
                color: entry.alive ? Colors.white : Colors.white54,
                fontSize: 13,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: GameConfig.playerColor.withValues(alpha: 0.20),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: GameConfig.playerColor.withValues(alpha: 0.55),
                  width: 1,
                ),
              ),
              child: Text(
                I18n.t.you,
                style: const TextStyle(
                  color: GameConfig.playerColor,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ],
          const SizedBox(width: 10),
          Text(
            '${entry.score}',
            style: TextStyle(
              color: entry.alive ? Colors.white : Colors.white54,
              fontSize: 14,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Big stylised cube portrait with a face — used for the winner.
class _CubeAvatar extends StatelessWidget {
  const _CubeAvatar({
    required this.color,
    required this.happy,
    required this.size,
  });
  final Color color;
  final bool happy;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _CubePainter(color: color, happy: happy)),
    );
  }
}

class _CubePainter extends CustomPainter {
  _CubePainter({required this.color, required this.happy});
  final Color color;
  final bool happy;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cornerR = w * 0.20;
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, w, h),
      Radius.circular(cornerR),
    );

    // Outer glow halo so the winner cube pops against the cosmic backdrop.
    canvas.drawRRect(
      body.inflate(4),
      Paint()
        ..color = color.withValues(alpha: 0.50)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );

    // Vertical body gradient.
    canvas.drawRRect(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(color, Colors.white, 0.32)!,
            color,
            Color.lerp(color, Colors.black, 0.55)!,
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );

    // Top rim (toon highlight).
    final rim = RRect.fromLTRBAndCorners(
      2,
      2,
      w - 2,
      h * 0.30,
      topLeft: Radius.circular(cornerR * 0.85),
      topRight: Radius.circular(cornerR * 0.85),
    );
    canvas.drawRRect(
      rim,
      Paint()..color = Colors.white.withValues(alpha: 0.45),
    );

    // Outline.
    canvas.drawRRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.06
        ..color = Color.lerp(color, Colors.black, 0.55)!,
    );

    // ---- Face ----
    final eyeY = h * 0.42;
    final eyeOffset = w * 0.20;
    final eyeR = w * 0.13;
    final pupilR = eyeR * 0.55;
    final eyeWhite = Paint()..color = const Color(0xFFFFFAF0);
    final pupil = Paint()..color = const Color(0xFF1A1410);
    final shine = Paint()..color = Colors.white;
    for (final side in const [-1, 1]) {
      final ex = w / 2 + side * eyeOffset;
      canvas.drawCircle(Offset(ex, eyeY), eyeR, eyeWhite);
      canvas.drawCircle(Offset(ex, eyeY), pupilR, pupil);
      canvas.drawCircle(
        Offset(ex - pupilR * 0.30, eyeY - pupilR * 0.30),
        pupilR * 0.40,
        shine,
      );
    }

    // Mouth — big smile on victory, neutral line otherwise.
    final mouthY = h * 0.72;
    final mouthW = w * 0.34;
    final mouthPaint = Paint()
      ..color = const Color(0xFF3B1F00)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.05
      ..strokeCap = StrokeCap.round;
    if (happy) {
      final path = Path()
        ..moveTo(w / 2 - mouthW / 2, mouthY)
        ..quadraticBezierTo(
          w / 2,
          mouthY + mouthW * 0.55,
          w / 2 + mouthW / 2,
          mouthY,
        );
      canvas.drawPath(path, mouthPaint);
    } else {
      canvas.drawLine(
        Offset(w / 2 - mouthW / 2, mouthY),
        Offset(w / 2 + mouthW / 2, mouthY),
        mouthPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_CubePainter old) =>
      old.color != color || old.happy != happy;
}

class _GradientTitle extends StatelessWidget {
  const _GradientTitle(this.text, {this.accent = const Color(0xFFB14BFF)});
  final String text;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 38,
            fontWeight: FontWeight.w900,
            letterSpacing: 5,
            height: 1,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 5
              ..color = Colors.black.withValues(alpha: 0.9),
          ),
        ),
        ShaderMask(
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.lerp(accent, Colors.white, 0.45)!,
              accent,
              Color.lerp(accent, Colors.black, 0.45)!,
            ],
          ).createShader(rect),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 38,
              fontWeight: FontWeight.w900,
              letterSpacing: 5,
              height: 1,
              shadows: [
                Shadow(color: accent.withValues(alpha: 0.6), blurRadius: 22),
                const Shadow(
                  color: Colors.black87,
                  blurRadius: 8,
                  offset: Offset(0, 3),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
