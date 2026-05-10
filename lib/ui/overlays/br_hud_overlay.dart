import 'package:flutter/material.dart';

import '../../game/config.dart';
import '../../game/jumping_jack_game.dart';
import '../../i18n/i18n.dart';
import '../../services/audio_manager.dart';
import '../../services/battle_royale_service.dart';
import '../../services/preferences.dart';
import '../widgets/fortnite_button.dart';

/// Battle Royale HUD: live leaderboard (top-right) plus the spectator eye
/// + survivor counter (top-left, only visible when watching).
class BrHudOverlay extends StatelessWidget {
  const BrHudOverlay({super.key, required this.game});

  final JumpingJackGame game;

  // Per-slot accent colour so players are visually distinct on the
  // leaderboard.
  static const _slotColors = <Color>[
    GameConfig.playerColor,           // yellow — local player by default
    Color(0xFF6CD8FF),                // cyan
    Color(0xFFFF6E94),                // pink
    Color(0xFF7AE091),                // green
    Color(0xFFFFA64C),                // orange
  ];

  @override
  Widget build(BuildContext context) {
    final svc = BattleRoyaleService.instance;
    return AnimatedBuilder(
      animation: svc,
      builder: (context, _) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Stack(
              children: [
                if (svc.spectator)
                  Align(
                    alignment: Alignment.topLeft,
                    child: _SpectatorBadge(survivors: svc.aliveCount),
                  ),
                Align(
                  alignment: Alignment.topRight,
                  child: _Leaderboard(svc: svc),
                ),
                if (svc.spectator && svc.phase == BrPhase.playing)
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 320),
                        child: FortniteButton(
                          label: I18n.t.quit,
                          icon: Icons.close_rounded,
                          style: FortniteButtonStyle.secondary,
                          height: 56,
                          fontSize: 16,
                          onPressed: () => _quit(context),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _quit(BuildContext context) async {
    AudioManager.click();
    await BattleRoyaleService.instance.leaveMatch();
    BattleRoyaleService.resetInstance();
    if (!context.mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }
}

class _SpectatorBadge extends StatelessWidget {
  const _SpectatorBadge({required this.survivors});
  final int survivors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: const Color(0xFFB14BFF).withValues(alpha: 0.6),
          width: 1.2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.visibility_rounded,
            color: Color(0xFFE8B5FF),
            size: 16,
          ),
          const SizedBox(width: 6),
          Text(
            '$survivors',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _Leaderboard extends StatelessWidget {
  const _Leaderboard({required this.svc});
  final BattleRoyaleService svc;

  @override
  Widget build(BuildContext context) {
    final players = svc.players;
    if (players.isEmpty) return const SizedBox.shrink();
    final me = Preferences.playerId;
    // IntrinsicWidth keeps the leaderboard exactly as wide as its widest
    // row — without it the Align(topRight) gives unbounded width and
    // CrossAxisAlignment.stretch makes the Column expand across the
    // whole screen, hiding the player's main HUD score.
    return IntrinsicWidth(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final p in players)
              _LeaderRow(
                player: p,
                state: svc.playerStates[p.playerId],
                isMe: p.playerId == me,
              ),
          ],
        ),
      ),
    );
  }
}

class _LeaderRow extends StatelessWidget {
  const _LeaderRow({
    required this.player,
    required this.state,
    required this.isMe,
  });
  final BrPlayer player;
  final BrPlayerState? state;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final color = BrHudOverlay._slotColors[
      player.slotIndex.clamp(0, BrHudOverlay._slotColors.length - 1)
    ];
    final alive = state?.alive ?? true;
    final score = state?.score ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: alive ? color : Colors.white24,
              shape: BoxShape.circle,
              boxShadow: alive
                  ? [BoxShadow(color: color.withValues(alpha: 0.7), blurRadius: 6)]
                  : null,
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 80,
            child: Text(
              isMe ? 'TOI' : _truncate(player.name, 10),
              style: TextStyle(
                color: alive ? Colors.white : Colors.white38,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                decoration:
                    alive ? TextDecoration.none : TextDecoration.lineThrough,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            alive ? '$score' : '✗',
            style: TextStyle(
              color: alive ? color : Colors.white38,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  String _truncate(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}…';
}
