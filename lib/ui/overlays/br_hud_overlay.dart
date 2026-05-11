import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../game/jumping_jack_game.dart';
import '../../i18n/i18n.dart';
import '../../services/audio_manager.dart';
import '../../services/battle_royale_service.dart';
import '../theme/jack_design.dart';
import '../widgets/fortnite_button.dart';
import '../widgets/jack_ico.dart';
import '../widgets/jack_logo.dart';
import '../widgets/jack_mascot.dart';

/// Battle Royale HUD: kill / event feed (top-right) plus the spectator
/// badge + safe-window indicator (top-left, only when relevant).
class BrHudOverlay extends StatefulWidget {
  const BrHudOverlay({super.key, required this.game});

  final JumpingJackGame game;

  @override
  State<BrHudOverlay> createState() => _BrHudOverlayState();
}

class _BrHudOverlayState extends State<BrHudOverlay>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    // Drive a per-frame rebuild so the BR pre-game / win celebration
    // overlays animate smoothly with the game's internal countdown
    // timers (which aren't part of the BR service ChangeNotifier).
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
    final svc = BattleRoyaleService.instance;
    return AnimatedBuilder(
      animation: svc,
      builder: (context, _) {
        // The BR HUD is layered: the normal HUD (leaderboard, event feed,
        // SAFE badge, spectator quit) is always rendered so the player
        // already sees the full UI during the 3-2-1 countdown. The
        // pre-game and win-celebration overlays sit on top.
        final brWinProgress = game.brWinSequenceActive
            ? ((2.0 - game.brWinSequenceTimer) / 2.0).clamp(0.0, 1.0)
            : 0.0;
        return Stack(
          children: [
            // ------------------ Persistent HUD ------------------
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Stack(
                  children: [
                    // Safe-zone vignette is in the BACK so it never tints
                    // the event feed / leaderboard text on top.
                    if (game.brInvincibilityActive)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: _BrSafeVignette(
                            progress: 1.0 -
                                (game.brInvincibilityRemaining /
                                    JumpingJackGame.brInvincibilityDuration),
                          ),
                        ),
                      ),
                    // Top-left: contextual badges only (spectator + safe
                    // window). The event feed moved to the top-right slot.
                    if (svc.spectator || game.brInvincibilityActive)
                      Align(
                        alignment: Alignment.topLeft,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (svc.spectator) ...[
                              _SpectatorBadge(spectators: svc.spectatorCount),
                              const SizedBox(height: 8),
                            ],
                            if (game.brInvincibilityActive)
                              _BrSafeBadge(
                                remaining: game.brInvincibilityRemaining,
                              ),
                          ],
                        ),
                      ),
                    // Top-right: action / kill feed (replaces the player
                    // leaderboard, which felt redundant with the cube
                    // colours + name labels in-world).
                    Align(
                      alignment: Alignment.topRight,
                      child: _BrEventFeed(svc: svc),
                    ),
                    if (svc.spectator && svc.phase == BrPhase.playing)
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 24),
                          child: ConstrainedBox(
                            constraints:
                                const BoxConstraints(maxWidth: 220),
                            child: FortniteButton(
                              label: I18n.t.quit,
                              icoName: IcoName.close,
                              style: FortniteButtonStyle.cyan,
                              height: 52,
                              fontSize: 16,
                              onPressed: () => _quit(context),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // ------------------ Countdown overlay ------------------
            if (game.preGame)
              Positioned.fill(
                child: _BrCountdown(remaining: game.startCountdown),
              ),
            // ------------------ Win celebration ------------------
            if (game.brWinSequenceActive)
              Positioned.fill(
                child: _BrWinnerCelebration(
                  winnerId: game.brWinnerId ?? '',
                  svc: svc,
                  progress: brWinProgress,
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _quit(BuildContext context) async {
    AudioManager.uiBack();
    await BattleRoyaleService.instance.leaveMatch();
    BattleRoyaleService.resetInstance();
    if (!context.mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }
}

class _SpectatorBadge extends StatelessWidget {
  const _SpectatorBadge({required this.spectators});
  final int spectators;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: JackDesign.purple.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: JackDesign.purple, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const JackIco(
            name: IcoName.eye,
            size: 18,
            color: JackDesign.purpleHi,
          ),
          const SizedBox(width: 8),
          Text(
            '${I18n.t.spectatorLabel} · $spectators',
            style: JackDesign.bungee(
              fontSize: 12,
              color: Colors.white,
              letterSpacing: 1,
              feature: const FontFeature.tabularFigures(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pre-match 3-2-1-GO countdown shown for the first 3 seconds of a Battle
/// Royale run. Locks the world so the player isn't surprised.
class _BrCountdown extends StatelessWidget {
  const _BrCountdown({required this.remaining});
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
                color: JackDesign.purpleHi,
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 18),
            // Big pulsing number with a different scale per "tick".
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
                        color: JackDesign.purple.withValues(alpha: 0.85),
                        blurRadius: 28,
                      ),
                      Shadow(
                        color: JackDesign.yellow.withValues(alpha: 0.55),
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

/// Win celebration overlay — shown for 2 s after the last opponent dies.
/// Treats the winner like a star: dramatic zoom-in on the mascot, rotating
/// gold rays behind, sparkle particles, plus a flash of the WINNER logo.
class _BrWinnerCelebration extends StatelessWidget {
  const _BrWinnerCelebration({
    required this.winnerId,
    required this.svc,
    required this.progress,
  });
  final String winnerId;
  final BattleRoyaleService svc;
  /// 0 → 1 across the 2 s celebration window.
  final double progress;

  @override
  Widget build(BuildContext context) {
    BrPlayer? winner;
    for (final p in svc.players) {
      if (p.playerId == winnerId) {
        winner = p;
        break;
      }
    }
    final color = winner == null
        ? JackDesign.yellow
        : slotColor(winner.slotIndex);

    // WINNER logo is visible immediately so the user has clear feedback
    // that the sequence has started, even before the zoom finishes.
    final logoOpacity = (0.4 + progress * 0.6).clamp(0.0, 1.0);
    final logoScale = 0.85 + 0.15 * Curves.easeOutBack.transform(progress);

    // Subtle dim from the very first frame (so something visibly happens),
    // strengthening as the sequence progresses for the result hand-off.
    final raysAlpha = (0.3 + progress * 0.6).clamp(0.0, 0.9);
    final raysAngle = progress * 2.4; // radians
    final bgAlpha = (0.15 + progress * 0.30).clamp(0.0, 0.45);

    return Container(
      color: Colors.black.withValues(alpha: bgAlpha),
      child: SafeArea(
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Radial spotlight behind the mascot.
            IgnorePointer(
              child: Center(
                child: Container(
                  width: 480,
                  height: 480,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        color.withValues(alpha: 0.55 * raysAlpha),
                        color.withValues(alpha: 0.0),
                      ],
                      stops: const [0.0, 1.0],
                    ),
                  ),
                ),
              ),
            ),
            // Rotating gold rays.
            IgnorePointer(
              child: Transform.rotate(
                angle: raysAngle,
                child: SizedBox(
                  width: 520,
                  height: 520,
                  child: CustomPaint(
                    painter: _StarRaysPainter(
                      color: color,
                      alpha: raysAlpha,
                    ),
                  ),
                ),
              ),
            ),
            // Sparkle particles (deterministic positions).
            IgnorePointer(
              child: SizedBox(
                width: 360,
                height: 360,
                child: CustomPaint(
                  painter: _SparklesPainter(
                    progress: progress,
                    color: color,
                  ),
                ),
              ),
            ),
            // Center column: WINNER logo + mascot (in the winner's
            // colour) + name.
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Opacity(
                  opacity: logoOpacity,
                  child: Transform.scale(
                    scale: logoScale,
                    child: const JackEndLogo(
                      text: 'WINNER',
                      gold: true,
                      fontSize: 64,
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Transform.scale(
                  scale: 0.6 +
                      0.6 * Curves.easeOutBack.transform(progress.clamp(0.0, 1.0)),
                  child: JackMascot(
                    size: 130,
                    face: MascotFace.smile,
                    bodyColor: color,
                    glow: true,
                  ),
                ),
                const SizedBox(height: 18),
                if (winner != null)
                  Opacity(
                    opacity: ((progress - 0.20) / 0.30).clamp(0.0, 1.0),
                    child: Text(
                      winner.name,
                      style: JackDesign.bungee(
                        fontSize: 22,
                        color: Colors.white,
                        letterSpacing: 1,
                        shadows: [
                          Shadow(
                            color: color.withValues(alpha: 0.7),
                            blurRadius: 18,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StarRaysPainter extends CustomPainter {
  _StarRaysPainter({required this.color, required this.alpha});
  final Color color;
  final double alpha;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width * 0.55;
    const rays = 12;
    final paint = Paint()
      ..color = color.withValues(alpha: 0.35 * alpha)
      ..strokeWidth = 36
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < rays; i++) {
      final a = i * (2 * math.pi / rays);
      canvas.drawLine(
        Offset(cx, cy),
        Offset(cx + r * math.cos(a), cy + r * math.sin(a)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_StarRaysPainter old) =>
      old.alpha != alpha || old.color != color;
}

class _SparklesPainter extends CustomPainter {
  _SparklesPainter({required this.progress, required this.color});
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    const count = 14;
    for (var i = 0; i < count; i++) {
      final birth = (i / count) * 0.7;
      final age = (progress - birth) / 0.30;
      if (age < 0 || age > 1) continue;
      final a = i * (2 * math.pi / count) + progress * 0.6;
      final radius = 110.0 + (i % 3) * 28;
      final x = cx + radius * math.cos(a);
      final y = cy + radius * math.sin(a);
      final r = 6 * (1 - (age - 0.5).abs() * 1.4).clamp(0.0, 1.0);
      if (r <= 0) continue;
      canvas.drawCircle(
        Offset(x, y),
        r * 1.6,
        Paint()
          ..color = color.withValues(alpha: 0.55)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()..color = Colors.white.withValues(alpha: 0.95),
      );
    }
  }

  @override
  bool shouldRepaint(_SparklesPainter old) =>
      old.progress != progress || old.color != color;
}

/// Top-left BR event feed: replaces the score display in BR mode.
/// Renders the most recent events (death, kill, lead change). Events
/// stay visible until they're pushed out by newer ones (capped to
/// [_displayCount]). The fade is purely cosmetic for the *oldest*
/// visible row to hint at the rolling-history nature.
class _BrEventFeed extends StatelessWidget {
  const _BrEventFeed({required this.svc});
  final BattleRoyaleService svc;

  static const int _displayCount = 4;

  @override
  Widget build(BuildContext context) {
    final events = svc.events;
    if (events.isEmpty) return const SizedBox.shrink();
    final now = DateTime.now();
    final start = events.length > _displayCount
        ? events.length - _displayCount
        : 0;
    final slice = events.sublist(start);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: Column(
        // Right-aligned in its container so each pill hugs the right edge
        // of the screen now that the feed moved from top-left to top-right.
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < slice.length; i++) ...[
            _BrEventRow(
              event: slice[i],
              now: now,
              // The oldest visible row gets a slight dim so the rolling
              // history reads at a glance.
              dim: i == 0 && slice.length >= _displayCount,
            ),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }
}

class _BrEventRow extends StatelessWidget {
  const _BrEventRow({
    required this.event,
    required this.now,
    this.dim = false,
  });
  final BrEvent event;
  final DateTime now;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final opacity = dim ? 0.55 : 1.0;
    final text = _buildText(event, context);

    return Opacity(
      opacity: opacity,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.10),
            width: 1,
          ),
        ),
        child: text,
      ),
    );
  }

  Text _buildText(BrEvent e, BuildContext ctx) {
    final base = JackDesign.bungee(
      fontSize: 9,
      color: Colors.white,
      letterSpacing: 0.6,
    );
    Color colorOf(int? raw, Color fallback) =>
        raw == null ? fallback : Color(raw);

    switch (e.type) {
      case BrEventType.started:
        return Text(
          'GO !',
          style: base.copyWith(
            color: JackDesign.yellow,
            fontSize: 11,
          ),
        );
      case BrEventType.died:
        final name = e.victimName ?? '?';
        return Text.rich(
          TextSpan(
            style: base,
            children: [
              TextSpan(
                text: name,
                style: base.copyWith(
                  color: colorOf(e.victimColor, JackDesign.red),
                ),
              ),
              TextSpan(text: ' ${_diedSuffix(name)}'),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      case BrEventType.killed:
        return Text.rich(
          TextSpan(
            style: base,
            children: [
              TextSpan(
                text: e.killerName ?? '?',
                style: base.copyWith(
                  color: colorOf(e.killerColor, JackDesign.yellow),
                ),
              ),
              const TextSpan(text: '  ◎  '),
              TextSpan(
                text: e.victimName ?? '?',
                style: base.copyWith(
                  color: colorOf(e.victimColor, JackDesign.red),
                ),
              ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      case BrEventType.lead:
        return Text.rich(
          TextSpan(
            style: base,
            children: [
              TextSpan(
                text: e.leaderName ?? '?',
                style: base.copyWith(
                  color: colorOf(e.leaderColor, JackDesign.yellow),
                ),
              ),
              const TextSpan(text: '  ↑  '),
              TextSpan(
                text: I18n.t.feedLead('').trim(),
                style: base.copyWith(
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
    }
  }

  // Pulled from i18n: e.g. "JACK_3600 est mort" → suffix = "est mort".
  String _diedSuffix(String name) {
    final phrase = I18n.t.feedDied(name);
    if (phrase.startsWith(name)) {
      return phrase.substring(name.length).trim();
    }
    return phrase;
  }
}

/// Top-center pill: "🛡 SAFE · 5" countdown shown during the BR
/// invincibility window. Tells the player nobody can be eliminated yet.
class _BrSafeBadge extends StatelessWidget {
  const _BrSafeBadge({required this.remaining});
  final double remaining;

  @override
  Widget build(BuildContext context) {
    final secs = remaining.ceil().clamp(1, 99);
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: JackDesign.green.withValues(alpha: 0.18),
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
          const Icon(
            Icons.shield_rounded,
            size: 16,
            color: JackDesign.green,
          ),
          const SizedBox(width: 8),
          Text(
            'SAFE',
            style: JackDesign.bungee(
              fontSize: 13,
              color: JackDesign.green,
              letterSpacing: 2.0,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$secs',
            style: JackDesign.bungee(
              fontSize: 14,
              color: Colors.white,
              feature: const FontFeature.tabularFigures(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pulsing green-tinted vignette around the screen edges while the safety
/// window is active — a frame-of-the-screen cue that nobody can die yet.
class _BrSafeVignette extends StatelessWidget {
  const _BrSafeVignette({required this.progress});
  /// 0 → 1 across the safety window (0 = just started, 1 = window ended).
  final double progress;

  @override
  Widget build(BuildContext context) {
    // Fade out the green frame as the window expires so the player feels
    // the pressure rising right before kills become live.
    final intensity = (1.0 - progress).clamp(0.0, 1.0);
    if (intensity <= 0) return const SizedBox.shrink();
    return CustomPaint(painter: _VignettePainter(intensity: intensity));
  }
}

class _VignettePainter extends CustomPainter {
  _VignettePainter({required this.intensity});
  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 0.85,
          colors: [
            JackDesign.green.withValues(alpha: 0.0),
            JackDesign.green.withValues(alpha: 0.0),
            JackDesign.green.withValues(alpha: 0.32 * intensity),
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_VignettePainter old) => old.intensity != intensity;
}

