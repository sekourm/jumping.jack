import 'package:flutter/material.dart';

import '../../i18n/i18n.dart';
import '../../services/audio_manager.dart';
import '../../services/battle_royale_service.dart';
import '../theme/jack_design.dart';
import '../widgets/cosmic_background.dart';
import '../widgets/fortnite_button.dart';
import '../widgets/jack_ico.dart';
import '../widgets/jack_logo.dart';
import 'game_screen.dart';

/// Battle Royale matchmaking lobby. Owns a [BattleRoyaleService] for its
/// lifetime — joining the match on push, leaving on pop.
///
/// [quickJoin] mode (used by the BR result overlay's "Rejouer" button)
/// hides the full matchmaking UI and shows a minimal "Recherche d'une
/// partie..." spinner. The underlying join/wait/transition logic is
/// identical — only the visuals differ. As soon as `phase == playing`
/// the screen is replaced by the GameScreen exactly like the normal
/// lobby.
class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key, this.quickJoin = false});

  final bool quickJoin;

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  late final BattleRoyaleService _service;
  bool _navigatedToGame = false;

  @override
  void initState() {
    super.initState();
    // Keep the menu music running through matchmaking — the BR theme
    // only kicks in once the actual game loads (JumpingJackGame.onLoad
    // calls playBrMusic). If we just landed here from the home screen
    // it's already playing and this is a no-op; if we got here from
    // any other path (e.g. retry after a previous game) it restarts.
    AudioManager.playMenuMusic();
    _service = BattleRoyaleService.instance;
    // Quick-join mode (post-BR replay) silences the 5-4-3-2-1 lobby
    // ticks — the player already heard them once, no need to double up.
    _service.silentCountdown = widget.quickJoin;
    _service.addListener(_onChanged);
    _service.joinMatch();
  }

  void _onChanged() {
    if (!mounted) return;
    setState(() {});
    if (_service.phase == BrPhase.playing && !_navigatedToGame) {
      _navigatedToGame = true;
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          PageRouteBuilder<void>(
            pageBuilder: (_, a, b) =>
                const GameScreen(isBattleRoyale: true),
            transitionDuration: const Duration(milliseconds: 200),
            reverseTransitionDuration: const Duration(milliseconds: 200),
            transitionsBuilder: (_, animation, b, child) =>
                FadeTransition(opacity: animation, child: child),
          ),
        );
      });
    }
  }

  @override
  void dispose() {
    _service.removeListener(_onChanged);
    if (!_navigatedToGame) {
      _service.leaveMatch();
      BattleRoyaleService.resetInstance();
    }
    super.dispose();
  }

  void _cancel() {
    AudioManager.click();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.quickJoin) return _buildQuickJoin();
    return _buildFullLobby();
  }

  /// Minimal "Recherche d'une partie..." UI used after a BR replay.
  /// No player list, no countdown — just a spinner and a cancel button.
  /// The service still runs the normal join/wait flow underneath and
  /// the GameScreen takes over as soon as `phase == playing`.
  Widget _buildQuickJoin() {
    final phase = _service.phase;
    return Scaffold(
      backgroundColor: JackDesign.bg,
      body: Stack(
        children: [
          Positioned.fill(child: CosmicBackground(stage: JackStage.battle)),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const JackBrLogo(fontSize: 32),
                    const SizedBox(height: 32),
                    const SizedBox(
                      width: 44,
                      height: 44,
                      child: CircularProgressIndicator(
                        strokeWidth: 4,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(JackDesign.purpleHi),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _quickJoinStatusLabel(phase),
                      textAlign: TextAlign.center,
                      style: JackDesign.manrope(
                        fontSize: 14,
                        weight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 2.5,
                      ),
                    ),
                    const SizedBox(height: 40),
                    FortniteButton(
                      label: I18n.t.leaveLobby,
                      icoName: IcoName.close,
                      style: FortniteButtonStyle.cyan,
                      onPressed: _cancel,
                      enabled: phase == BrPhase.joining ||
                          (phase == BrPhase.waiting &&
                              _service.countdownRemaining.inMilliseconds >
                                  3000),
                      height: 52,
                      fontSize: 14,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _quickJoinStatusLabel(BrPhase phase) {
    switch (phase) {
      case BrPhase.joining:
      case BrPhase.waiting:
      case BrPhase.ended:
        return 'RECHERCHE D\'UNE PARTIE…';
      case BrPhase.starting:
      case BrPhase.playing:
        return 'DÉMARRAGE…';
      case BrPhase.finished:
        return 'FIN DE PARTIE';
      case BrPhase.error:
        return 'ERREUR';
    }
  }

  Widget _buildFullLobby() {
    return Scaffold(
      backgroundColor: JackDesign.bg,
      body: Stack(
        children: [
          Positioned.fill(child: CosmicBackground(stage: JackStage.battle)),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 40, 20, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const JackBrLogo(fontSize: 36),
                          const SizedBox(height: 22),
                          _PhaseStatus(service: _service),
                          const SizedBox(height: 22),
                          _PlayerList(service: _service),
                          const SizedBox(height: 36),
                          Builder(builder: (_) {
                            // Lobby leave button states:
                            //  • joining / waiting > 3 s          → enabled
                            //  • waiting ≤ 3 s / starting / playing → disabled
                            //    (greyed but still on screen — the player
                            //    sees the cut-off without the button popping
                            //    in and out as the phase transitions).
                            final phase = _service.phase;
                            final remaining =
                                _service.countdownRemaining.inMilliseconds;
                            final locked = phase == BrPhase.starting ||
                                phase == BrPhase.playing ||
                                (phase == BrPhase.waiting &&
                                    remaining <= 3000);
                            return ConstrainedBox(
                              constraints:
                                  const BoxConstraints(maxWidth: 320),
                              child: FortniteButton(
                                label: I18n.t.leaveLobby,
                                icoName: IcoName.close,
                                style: FortniteButtonStyle.cyan,
                                onPressed: _cancel,
                                enabled: !locked,
                                height: 56,
                                fontSize: 16,
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PhaseStatus extends StatelessWidget {
  const _PhaseStatus({required this.service});
  final BattleRoyaleService service;

  @override
  Widget build(BuildContext context) {
    switch (service.phase) {
      case BrPhase.joining:
        return _StatusBlock(line1: I18n.t.connecting, showSpinner: true);
      case BrPhase.waiting:
        final s = service.countdownRemaining.inSeconds + 1;
        final clamped = s.clamp(
          0,
          BattleRoyaleService.countdownDuration.inSeconds,
        );
        return _StatusBlock(
          line1: I18n.t.searchingPlayers,
          countdown: clamped,
          subtitle:
              '${service.players.length} / ${BattleRoyaleService.maxPlayers}',
        );
      case BrPhase.starting:
        return _StatusBlock(line1: I18n.t.launching, showSpinner: true);
      case BrPhase.playing:
        return _StatusBlock(line1: I18n.t.matchStarted);
      case BrPhase.finished:
        return _StatusBlock(line1: I18n.t.matchEnded);
      case BrPhase.ended:
        return _StatusBlock(line1: I18n.t.matchClosed);
      case BrPhase.error:
        return _StatusBlock(
          line1: I18n.t.errorTitle,
          subtitle: service.error ?? '?',
          isError: true,
        );
    }
  }
}

class _StatusBlock extends StatelessWidget {
  const _StatusBlock({
    required this.line1,
    this.subtitle,
    this.countdown,
    this.showSpinner = false,
    this.isError = false,
  });

  final String line1;
  final String? subtitle;
  final int? countdown;
  final bool showSpinner;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final accent = isError ? JackDesign.red : JackDesign.purpleHi;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (showSpinner) ...[
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: JackDesign.purpleHi,
                ),
              ),
              const SizedBox(width: 12),
            ],
            Text(
              line1,
              style: JackDesign.manrope(
                fontSize: 11,
                weight: FontWeight.w800,
                color: accent,
                letterSpacing: 2.5,
              ),
            ),
          ],
        ),
        if (countdown != null) ...[
          const SizedBox(height: 14),
          Text(
            '$countdown',
            style: JackDesign.bungee(
              fontSize: 80,
              color: Colors.white,
              height: 1,
              shadows: [
                Shadow(
                  color: JackDesign.purple.withValues(alpha: 0.70),
                  blurRadius: 24,
                ),
                const Shadow(
                  color: Colors.black87,
                  blurRadius: 6,
                  offset: Offset(0, 3),
                ),
              ],
            ),
          ),
        ],
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle!,
            style: JackDesign.manrope(
              fontSize: 11,
              weight: FontWeight.w800,
              color: isError ? accent : Colors.white.withValues(alpha: 0.45),
              letterSpacing: 2.0,
            ),
          ),
        ],
      ],
    );
  }
}

class _PlayerList extends StatelessWidget {
  const _PlayerList({required this.service});
  final BattleRoyaleService service;

  @override
  Widget build(BuildContext context) {
    final mySlot = service.mySlot;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
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
            color: JackDesign.purple.withValues(alpha: 0.28),
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(BattleRoyaleService.maxPlayers, (i) {
            BrPlayer? player;
            for (final p in service.players) {
              if (p.slotIndex == i) {
                player = p;
                break;
              }
            }
            // Lobby UX: empty slots are pre-filled with placeholder bots
            // so the player sees a full match from the start. As real
            // humans join, they take the lowest empty slot, displacing
            // the placeholder. When the countdown ends the room actually
            // commits the remaining bots into the DB.
            final isPlaceholder = player == null;
            final displayPlayer = player ??
                BrPlayer(
                  playerId: 'preview_bot_$i',
                  name: I18n.t.searchingSlot,
                  slotIndex: i,
                  isBot: true,
                );
            final isLast = i == BattleRoyaleService.maxPlayers - 1;
            return Container(
              decoration: BoxDecoration(
                border: isLast
                    ? null
                    : Border(
                        bottom: BorderSide(
                          color: Colors.white.withValues(alpha: 0.05),
                          width: 1,
                        ),
                      ),
              ),
              child: _SlotRow(
                slot: i,
                player: displayPlayer,
                isMe: !isPlaceholder && player.slotIndex == mySlot,
                isPlaceholder: isPlaceholder,
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _SlotRow extends StatelessWidget {
  const _SlotRow({
    required this.slot,
    required this.player,
    required this.isMe,
    this.isPlaceholder = false,
  });

  final int slot;
  final BrPlayer player;
  final bool isMe;
  final bool isPlaceholder;

  @override
  Widget build(BuildContext context) {
    final isBot = player.isBot;
    final color = slotColor(slot);
    final isHumanOpponent = !isBot && !isMe;
    Color dotColor;
    if (isMe) {
      dotColor = JackDesign.yellow;
    } else if (isHumanOpponent) {
      dotColor = JackDesign.green;
    } else {
      dotColor = color;
    }
    final dimmed = isPlaceholder;
    final opacity = dimmed ? 0.55 : 1.0;
    return Opacity(
      opacity: opacity,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 6),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
                boxShadow: dimmed
                    ? null
                    : [BoxShadow(color: dotColor, blurRadius: 12)],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                player.name,
                overflow: TextOverflow.ellipsis,
                style: JackDesign.bungee(
                  fontSize: 13,
                  color: Colors.white,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            if (isBot && !isPlaceholder && !isMe) ...[
              _Tag(label: I18n.t.bot, color: JackDesign.cyan),
              const SizedBox(width: 8),
            ],
            if (!isPlaceholder) _WinsBadge(wins: player.wins, color: dotColor),
          ],
        ),
      ),
    );
  }
}

/// "🔥 N" badge shown beside each non-placeholder player's name. Uses the
/// same flame icon as the home screen's TOP 1 chip, tinted with the row's
/// accent color (yellow for me, green for human opponents, slot color
/// for bots) so the badge echoes the row's identity dot.
class _WinsBadge extends StatelessWidget {
  const _WinsBadge({required this.wins, required this.color});
  final int wins;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        JackIco(name: IcoName.flame, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          '$wins',
          style: JackDesign.bungee(
            fontSize: 11,
            color: color.withValues(alpha: 0.95),
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Text(
        label,
        style: JackDesign.bungee(
          fontSize: 10,
          color: color,
          letterSpacing: 1.6,
        ),
      ),
    );
  }
}
