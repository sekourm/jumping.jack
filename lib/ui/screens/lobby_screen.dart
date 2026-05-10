import 'package:flutter/material.dart';

import '../../game/config.dart';
import '../../i18n/i18n.dart';
import '../../services/audio_manager.dart';
import '../../services/battle_royale_service.dart';
import '../widgets/cosmic_background.dart';
import '../widgets/fortnite_button.dart';
import 'game_screen.dart';

/// Battle Royale matchmaking lobby. Owns a [BattleRoyaleService] for its
/// lifetime — joining the match on push, leaving on pop.
class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  late final BattleRoyaleService _service;
  bool _navigatedToGame = false;

  @override
  void initState() {
    super.initState();
    _service = BattleRoyaleService.instance;
    _service.addListener(_onChanged);
    _service.joinMatch();
  }

  void _onChanged() {
    if (!mounted) return;
    setState(() {});
    if (_service.phase == BrPhase.playing && !_navigatedToGame) {
      _navigatedToGame = true;
      // The singleton stays alive across the lobby → game transition so
      // the BR HUD / death broadcast keep working.
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
      // User cancelled the lobby — leave the match cleanly. If we did
      // navigate to the game, the singleton keeps running.
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
    return Scaffold(
      backgroundColor: GameConfig.bgColor,
      body: Stack(
        children: [
          Positioned.fill(child: CosmicBackground(platforms: 100)),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 24,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const _Title(),
                          const SizedBox(height: 32),
                          _PhaseStatus(service: _service),
                          const SizedBox(height: 24),
                          _PlayerList(service: _service),
                          const SizedBox(height: 36),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 280),
                            child: FortniteButton(
                              label: I18n.t.cancel,
                              icon: Icons.close_rounded,
                              style: FortniteButtonStyle.secondary,
                              onPressed: _cancel,
                              height: 52,
                              fontSize: 16,
                            ),
                          ),
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

class _Title extends StatelessWidget {
  const _Title();

  @override
  Widget build(BuildContext context) {
    final title = I18n.t.matchmakingTitle;
    return Stack(
      alignment: Alignment.center,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            letterSpacing: 4,
            height: 1,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 5
              ..color = Colors.black.withValues(alpha: 0.85),
          ),
        ),
        ShaderMask(
          shaderCallback: (rect) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFE8B5FF),
              Color(0xFFB14BFF),
              Color(0xFF6B1FA0),
            ],
          ).createShader(rect),
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: 4,
              height: 1,
              shadows: [
                Shadow(
                  color: Color(0xFFB14BFF),
                  blurRadius: 22,
                ),
                Shadow(
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

class _PhaseStatus extends StatelessWidget {
  const _PhaseStatus({required this.service});
  final BattleRoyaleService service;

  @override
  Widget build(BuildContext context) {
    switch (service.phase) {
      case BrPhase.joining:
        return _StatusBlock(
          line1: I18n.t.connecting,
          showSpinner: true,
        );
      case BrPhase.waiting:
        final s = service.countdownRemaining.inSeconds + 1;
        final clamped = s.clamp(0, BattleRoyaleService.countdownDuration.inSeconds);
        return _StatusBlock(
          line1: I18n.t.searchingPlayers,
          countdown: clamped,
          subtitle: '${service.players.length}/${BattleRoyaleService.maxPlayers}',
        );
      case BrPhase.starting:
        return _StatusBlock(
          line1: I18n.t.launching,
          showSpinner: true,
        );
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
    final accent = isError ? const Color(0xFFFF5E5B) : const Color(0xFFB14BFF);
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
                  color: Colors.white70,
                ),
              ),
              const SizedBox(width: 12),
            ],
            Text(
              line1,
              style: TextStyle(
                color: accent,
                fontSize: 13,
                fontWeight: FontWeight.w900,
                letterSpacing: 4,
              ),
            ),
          ],
        ),
        if (countdown != null) ...[
          const SizedBox(height: 14),
          Text(
            '$countdown',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 56,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
              height: 1,
              fontFeatures: [FontFeature.tabularFigures()],
              shadows: [
                Shadow(
                  color: Color(0xFFB14BFF),
                  blurRadius: 24,
                ),
                Shadow(
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
            style: TextStyle(
              color: isError ? accent : Colors.white60,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
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
          children: List.generate(BattleRoyaleService.maxPlayers, (i) {
            BrPlayer? player;
            for (final p in service.players) {
              if (p.slotIndex == i) {
                player = p;
                break;
              }
            }
            return _SlotRow(
              slot: i,
              player: player,
              isMe: player != null && player.slotIndex == mySlot,
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
  });

  final int slot;
  final BrPlayer? player;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final empty = player == null;
    final isBot = player?.isBot ?? false;
    Color dotColor;
    if (empty) {
      dotColor = Colors.white24;
    } else if (isBot) {
      dotColor = const Color(0xFFFF7B47);
    } else if (isMe) {
      dotColor = GameConfig.playerColor;
    } else {
      dotColor = const Color(0xFF7CC0FF);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
              boxShadow: empty
                  ? null
                  : [BoxShadow(color: dotColor.withValues(alpha: 0.6), blurRadius: 8)],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              empty ? I18n.t.waitingSlot : player!.name,
              style: TextStyle(
                color: empty ? Colors.white38 : Colors.white,
                fontSize: 14,
                fontWeight: empty ? FontWeight.w600 : FontWeight.w900,
                letterSpacing: 2,
                fontStyle: empty ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ),
          if (isMe)
            _Tag(label: I18n.t.you, color: GameConfig.playerColor)
          else if (isBot)
            _Tag(label: I18n.t.bot, color: const Color(0xFFFF7B47)),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  // ignore: unused_element_parameter
  const _Tag({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.55), width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}
