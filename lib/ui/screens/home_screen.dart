import 'dart:async';
import 'dart:math' as math;
import 'dart:math' show Random;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/supabase_config.dart';
import '../../i18n/i18n.dart';
import '../../services/audio_manager.dart';
import '../../services/preferences.dart';
import '../theme/jack_design.dart';
import '../widgets/cosmic_background.dart';
import '../widgets/fortnite_button.dart';
import '../widgets/jack_ico.dart';
import '../widgets/jack_logo.dart';
import '../widgets/jack_mascot.dart';
import '../widgets/tap_burst.dart';
import 'game_screen.dart';
import 'lobby_screen.dart';

/// Bumped manually before each push so we can verify the deploy is live.
const String kAppVersion = 'v1.0';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // Picked once per HomeScreen mount → on every relaunch / return-to-menu the
  // background world is randomized.
  late final JackStage _stage;
  // GlobalKey on the BR button → lets us read its on-screen rect so the
  // tutorial-locked bubble can anchor right above it.
  final GlobalKey _brButtonKey = GlobalKey();
  // Tutorial-locked speech bubble state. Shown briefly when the user
  // taps the BR button before completing the tutorial; auto-dismissed
  // after ~3 s or on tap anywhere.
  bool _brLockedBubbleVisible = false;
  Timer? _brLockedBubbleTimer;

  // Intro animation — runs once on cold start. The mascot does two jumps
  // (squash → stretch → airborne arc → impact squash) with a ground shadow
  // that shrinks while it's airborne, then the rest of the UI (chips,
  // logo, pseudo, buttons) fades and slides in.
  // The cosmic background is drawn from frame 0 — the native launch
  // screen is a flat dark colour close to all stage gradients' bottom
  // band so the hand-off doesn't flash.
  // Only the first mount plays the intro; returning from a game pops
  // straight to the static home.
  static bool _introPlayed = false;
  static const int _introMs = 1500;
  late final AnimationController _introCtrl;
  late final Animation<double> _topFade;
  late final Animation<double> _logoFade;
  late final Animation<double> _bottomFade;
  late final Animation<Offset> _bottomSlide;

  @override
  void initState() {
    super.initState();
    final rng = Random();
    _stage = JackStage.worlds[rng.nextInt(JackStage.worlds.length)];
    WidgetsBinding.instance.addObserver(this);
    I18n.instance.addListener(_onLocaleChanged);
    AudioManager.preload().then((_) => AudioManager.startMenuMusic());
    _introCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: _introMs),
      value: _introPlayed ? 1.0 : 0.0,
    );
    // Jumps finish at t ≈ 0.53 of the controller (see _JumpingMascot).
    // The chips fade in around the second jump's apex, the logo joins
    // on the way down, and the buttons reveal after the final impact.
    _topFade = CurvedAnimation(
      parent: _introCtrl,
      curve: const Interval(0.40, 0.62, curve: Curves.easeOut),
    );
    _logoFade = CurvedAnimation(
      parent: _introCtrl,
      curve: const Interval(0.50, 0.75, curve: Curves.easeOut),
    );
    _bottomFade = CurvedAnimation(
      parent: _introCtrl,
      curve: const Interval(0.62, 1.0, curve: Curves.easeOut),
    );
    _bottomSlide = Tween<Offset>(
      begin: const Offset(0, 0.22),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _introCtrl,
      curve: const Interval(0.62, 1.0, curve: Curves.easeOutCubic),
    ));
    if (!_introPlayed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _introCtrl.forward().whenComplete(() => _introPlayed = true);
      });
    }
  }

  @override
  void dispose() {
    _introCtrl.dispose();
    _brLockedBubbleTimer?.cancel();
    I18n.instance.removeListener(_onLocaleChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onLocaleChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JackDesign.bg,
      body: Stack(
        children: [
          Positioned.fill(child: CosmicBackground(stage: _stage)),
          Positioned(
            right: 14,
            bottom: 10,
            child: SafeArea(
              child: Text(
                kAppVersion,
                style: JackDesign.manrope(
                  fontSize: 10,
                  color: Colors.white.withValues(alpha: 0.30),
                  letterSpacing: 2.5,
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FadeTransition(
                    opacity: _topFade,
                    child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _StatChip(
                            icoName: IcoName.trophy,
                            label: 'SCORE',
                            value: Preferences.bestScore > 0
                                ? '${Preferences.bestScore}'
                                : '—',
                            accent: JackDesign.yellow,
                          ),
                          const SizedBox(width: 8),
                          _StatChip(
                            icoName: IcoName.flame,
                            label: 'TOP 1',
                            value: '${Preferences.brWins}',
                            accent: JackDesign.purple,
                            iconColor: JackDesign.purpleHi,
                          ),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _LangChip(),
                          const SizedBox(width: 8),
                          // Help button is gated on tutorialCompleted:
                          // its only entry today is "Rejouer le
                          // tutoriel", which makes no sense for a
                          // player who hasn't completed it once.
                          if (Preferences.tutorialCompleted) ...[
                            _RoundIconBtn(
                              icoName: IcoName.help,
                              onPressed: _openHelp,
                              tooltip: I18n.t.helpTitle,
                            ),
                            const SizedBox(width: 8),
                          ],
                          _RoundIconBtn(
                            icoName: Preferences.muted
                                ? IcoName.volumeOff
                                : IcoName.volumeOn,
                            onPressed: _toggleMute,
                            tooltip: I18n.t.audioSection,
                          ),
                        ],
                      ),
                    ],
                  ),
                  ),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _JumpingMascot(intro: _introCtrl),
                        const SizedBox(height: 14),
                        FadeTransition(
                          opacity: _logoFade,
                          child: const JackLogo(),
                        ),
                      ],
                    ),
                  ),
                  // Pseudo chip sits just above the action buttons — same
                  // visual stack as the death / BR result overlays where
                  // the player identity reads right next to the CTA row.
                  FadeTransition(
                    opacity: _bottomFade,
                    child: SlideTransition(
                      position: _bottomSlide,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: _PseudoChip(onChanged: () => setState(() {})),
                          ),
                          const SizedBox(height: 14),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                            child: Row(
                      // Solo (primary yellow) on the left, BR (epic purple)
                      // on the right — same vocabulary as the death / BR
                      // result overlays so all three "where do I go next"
                      // screens read as one family.
                      children: [
                        Expanded(
                          child: FortniteButton(
                            label: I18n.t.playSolo,
                            icoName: IcoName.play,
                            onPressed: _startGame,
                            height: 60,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          // BR stays visible+tappable even before the
                          // tutorial is completed so the user can still
                          // tap it — they just get the locked-bubble
                          // pointing them at the solo tutorial. Opacity
                          // at 45 % mirrors the FortniteButton's own
                          // disabled styling so the lock state reads at
                          // a glance. GlobalKey lets the bubble anchor
                          // to this button's rect.
                          child: Opacity(
                            key: _brButtonKey,
                            opacity:
                                Preferences.tutorialCompleted ? 1.0 : 0.45,
                            child: FortniteButton(
                              label: I18n.t.battleRoyale,
                              icoName: IcoName.flame,
                              style: FortniteButtonStyle.epic,
                              onPressed: _openBattleRoyale,
                              height: 60,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Tutorial-locked speech bubble. Rendered at the top of the
          // home Stack (above the action buttons) so the tail sits
          // directly above the BR button without being clipped by the
          // SafeArea content.
          if (_brLockedBubbleVisible)
            _BrLockedBubbleAnchor(
              anchorKey: _brButtonKey,
              onTap: _hideBrLockedBubble,
            ),
        ],
      ),
    );
  }

  void _showBrLockedBubble() {
    _brLockedBubbleTimer?.cancel();
    setState(() => _brLockedBubbleVisible = true);
    _brLockedBubbleTimer = Timer(const Duration(milliseconds: 3500), () {
      if (mounted) _hideBrLockedBubble();
    });
  }

  void _hideBrLockedBubble() {
    _brLockedBubbleTimer?.cancel();
    _brLockedBubbleTimer = null;
    if (!_brLockedBubbleVisible) return;
    setState(() => _brLockedBubbleVisible = false);
  }

  void _startGame() {
    AudioManager.uiConfirm();
    // The game itself swaps to the right track in JumpingJackGame.onLoad
    // (solo_loop vs br_loop) — calling startGameMusic() here would force
    // solo_loop even for BR. Skip the music switch; the cross-fade lives
    // in the engine boot path.
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (_, a, b) => const GameScreen(),
        transitionDuration: const Duration(milliseconds: 180),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        transitionsBuilder: (_, animation, b, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    ).then((_) {
      if (mounted) {
        AudioManager.startMenuMusic();
        setState(() {});
      }
    });
  }

  Future<void> _openHelp() async {
    AudioManager.click();
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (ctx) => _HelpDialog(
        onReplayTutorial: () {
          AudioManager.uiConfirm();
          // No persisted change here on purpose: the replay flow uses
          // an in-memory `tutorialReplay: true` flag on the game so
          // closing the app mid-replay can't strand the user with the
          // BR button greyed out on next launch.
          Navigator.of(ctx).pop();
          _launchTutorialReplay();
        },
      ),
    );
  }

  /// Pushes the [GameScreen] in tutorial-replay mode. The overlay
  /// drives the lesson and pops back here on completion, so the user
  /// never lands in an actual solo run — they just watched the
  /// tutorial. Music and home state refresh on return.
  void _launchTutorialReplay() {
    Navigator.of(context)
        .push(
      PageRouteBuilder<void>(
        pageBuilder: (_, a, b) => const GameScreen(tutorialReplay: true),
        transitionDuration: const Duration(milliseconds: 180),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        transitionsBuilder: (_, animation, b, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    )
        .then((_) {
      if (!mounted) return;
      AudioManager.startMenuMusic();
      setState(() {});
    });
  }

  void _toggleMute() async {
    AudioManager.click();
    final next = !Preferences.muted;
    Preferences.muted = next;
    await AudioManager.setMuted(next);
    if (mounted) setState(() {});
  }

  void _openBattleRoyale() {
    AudioManager.click();
    if (!Preferences.tutorialCompleted) {
      _showBrLockedBubble();
      return;
    }
    if (!SupabaseConfig.isConfigured) {
      _showToast(I18n.t.backendNotConfigured);
      return;
    }
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        // Quick-join everywhere — replaces the previous full lobby
        // (player list, big countdown card, etc.). The minimal
        // "Recherche d'une partie..." spinner has the same join logic
        // underneath but reads as a much cleaner matchmaking step.
        // The old full UI is still in LobbyScreen behind
        // `quickJoin: false` if we ever want to bring it back.
        pageBuilder: (_, a, b) => const LobbyScreen(quickJoin: true),
        transitionDuration: const Duration(milliseconds: 200),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        transitionsBuilder: (_, animation, b, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    ).then((_) {
      if (!mounted) return;
      // Restart menu music after we've come back from the BR flow.
      // GameScreen.dispose stopped the in-game track during popUntil,
      // and this fires *after* every dispose down the stack — no race
      // with the music engine that the death-overlay path used to hit.
      AudioManager.playMenuMusic();
      setState(() {});
    });
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(20),
          backgroundColor: const Color(0xFF1F0F38),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: JackDesign.purple, width: 1.4),
          ),
          duration: const Duration(seconds: 2),
          content: Row(
            children: [
              const JackIco(
                name: IcoName.flame,
                color: JackDesign.purple,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: JackDesign.manrope(
                    fontSize: 13,
                    weight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
  }
}

/// Compact pill showing the local player's nickname with a pencil affordance
/// to edit it. Tapping anywhere on the chip opens an edit dialog; saving
/// persists via [Preferences.playerName] and notifies the parent so the
/// home re-renders.
class _PseudoChip extends StatelessWidget {
  const _PseudoChip({required this.onChanged});
  final VoidCallback onChanged;

  Future<void> _openEdit(BuildContext context) async {
    AudioManager.click();
    final controller = TextEditingController(text: Preferences.playerName);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1F0F38),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: JackDesign.purple, width: 1.5),
          ),
          title: Text(
            I18n.t.editName,
            style: JackDesign.bungee(
              fontSize: 14,
              color: Colors.white,
              letterSpacing: 1.2,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                maxLength: 18,
                textCapitalization: TextCapitalization.characters,
                style: JackDesign.bungee(
                  fontSize: 16,
                  color: Colors.white,
                  letterSpacing: 0.6,
                ),
                decoration: InputDecoration(
                  counterStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                  ),
                  filled: true,
                  fillColor: Colors.black.withValues(alpha: 0.35),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        BorderSide(color: Colors.white.withValues(alpha: 0.10)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        const BorderSide(color: JackDesign.yellow, width: 1.5),
                  ),
                ),
                onSubmitted: (v) => Navigator.of(ctx).pop(v),
              ),
              const SizedBox(height: 14),
              const _RecoveryCodeBlock(),
              const SizedBox(height: 8),
              _RestoreEntry(onRestored: () {
                Navigator.of(ctx).pop();
                onChanged();
              }),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                AudioManager.click();
                Navigator.of(ctx).pop();
              },
              child: Text(
                I18n.t.cancel,
                style: JackDesign.manrope(
                  fontSize: 12,
                  weight: FontWeight.w800,
                  color: Colors.white.withValues(alpha: 0.65),
                  letterSpacing: 1.6,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                AudioManager.click();
                Navigator.of(ctx).pop(controller.text);
              },
              child: Text(
                I18n.t.save,
                style: JackDesign.manrope(
                  fontSize: 12,
                  weight: FontWeight.w800,
                  color: JackDesign.yellow,
                  letterSpacing: 1.6,
                ),
              ),
            ),
          ],
        );
      },
    );
    if (result != null && result.trim().isNotEmpty) {
      Preferences.playerName = result;
      onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    return TapBurst(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => _openEdit(context),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.42),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.18),
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  I18n.t.pseudoLabel,
                  style: JackDesign.manrope(
                    fontSize: 9,
                    weight: FontWeight.w800,
                    color: Colors.white.withValues(alpha: 0.50),
                    letterSpacing: 2.0,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  Preferences.playerName,
                  style: JackDesign.bungee(
                    fontSize: 13,
                    color: Colors.white,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: JackDesign.yellow.withValues(alpha: 0.18),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.edit,
                    size: 12,
                    color: JackDesign.yellow,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icoName,
    required this.label,
    required this.value,
    required this.accent,
    this.iconColor,
  });

  final IcoName icoName;
  final String label;
  final String value;
  final Color accent;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final isPurple = accent == JackDesign.purple;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent, width: 2),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.20),
            blurRadius: 18,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: isPurple ? 0.22 : 0.18),
            ),
            child: JackIco(
              name: icoName,
              size: 16,
              color: iconColor ?? accent,
            ),
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: JackDesign.manrope(
                  fontSize: 9,
                  weight: FontWeight.w800,
                  color: isPurple ? JackDesign.purpleHi : accent,
                  letterSpacing: 1.6,
                  height: 1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: JackDesign.bungee(
                  fontSize: 14,
                  height: 1,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoundIconBtn extends StatelessWidget {
  const _RoundIconBtn({
    required this.icoName,
    required this.onPressed,
    required this.tooltip,
  });
  final IcoName icoName;
  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: TapBurst(
        child: Material(
          color: Colors.white.withValues(alpha: 0.06),
          shape: const CircleBorder(
            side: BorderSide(color: Colors.white24, width: 2),
          ),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Center(
                child: JackIco(name: icoName, size: 20),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact language chip — toggles between FR and EN. The active locale's
/// flag is shown; tapping switches to the other language.
class _LangChip extends StatefulWidget {
  @override
  State<_LangChip> createState() => _LangChipState();
}

class _LangChipState extends State<_LangChip> {
  void _toggle() {
    AudioManager.click();
    final next = I18n.instance.locale == AppLocale.fr
        ? AppLocale.en
        : AppLocale.fr;
    I18n.instance.setLocale(next);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isFr = I18n.instance.locale == AppLocale.fr;
    return TapBurst(
      child: Material(
        color: Colors.white.withValues(alpha: 0.06),
        shape: const CircleBorder(
          side: BorderSide(color: Colors.white24, width: 2),
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _toggle,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  width: 26,
                  height: 18,
                  child: isFr ? const _MiniFr() : const _MiniEn(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniFr extends StatelessWidget {
  const _MiniFr();
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Container(color: const Color(0xFF0055A4))),
        Expanded(child: Container(color: Colors.white)),
        Expanded(child: Container(color: const Color(0xFFEF4135))),
      ],
    );
  }
}

class _MiniEn extends StatelessWidget {
  const _MiniEn();
  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _MiniUnionJackPainter());
  }
}

class _MiniUnionJackPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()..color = const Color(0xFF012169),
    );
    final whiteThick = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    final redThin = Paint()
      ..color = const Color(0xFFC8102E)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    final whiteCross = Paint()
      ..color = Colors.white
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;
    final redCross = Paint()
      ..color = const Color(0xFFC8102E)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset.zero, Offset(w, h), whiteThick);
    canvas.drawLine(Offset(w, 0), Offset(0, h), whiteThick);
    canvas.drawLine(Offset.zero, Offset(w, h), redThin);
    canvas.drawLine(Offset(w, 0), Offset(0, h), redThin);
    canvas.drawLine(Offset(w / 2, 0), Offset(w / 2, h), whiteCross);
    canvas.drawLine(Offset(0, h / 2), Offset(w, h / 2), whiteCross);
    canvas.drawLine(Offset(w / 2, 0), Offset(w / 2, h), redCross);
    canvas.drawLine(Offset(0, h / 2), Offset(w, h / 2), redCross);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Read-only block shown inside the pseudo edit dialog: the recovery
/// code with a copy button and a one-line explanation. Replacement
/// path if the user loses access to this browser/device.
class _RecoveryCodeBlock extends StatefulWidget {
  const _RecoveryCodeBlock();

  @override
  State<_RecoveryCodeBlock> createState() => _RecoveryCodeBlockState();
}

class _RecoveryCodeBlockState extends State<_RecoveryCodeBlock> {
  bool _justCopied = false;

  Future<void> _copy() async {
    AudioManager.click();
    await Clipboard.setData(ClipboardData(text: Preferences.recoveryCode));
    if (!mounted) return;
    setState(() => _justCopied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _justCopied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: JackDesign.yellow.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            I18n.t.recoveryCodeLabel,
            style: JackDesign.manrope(
              fontSize: 9,
              weight: FontWeight.w800,
              color: JackDesign.yellow,
              letterSpacing: 2.0,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  Preferences.recoveryCode,
                  style: JackDesign.bungee(
                    fontSize: 14,
                    color: Colors.white,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              TextButton(
                onPressed: _copy,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 30),
                ),
                child: Text(
                  _justCopied ? I18n.t.codeCopied : I18n.t.copyCode,
                  style: JackDesign.manrope(
                    fontSize: 10,
                    weight: FontWeight.w800,
                    color: _justCopied
                        ? JackDesign.green
                        : JackDesign.yellow,
                    letterSpacing: 1.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            I18n.t.recoveryCodeHelp,
            style: JackDesign.manrope(
              fontSize: 10,
              weight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Restore profile" trigger row + modal. Opens a sub-dialog asking
/// for a recovery code, calls Supabase, then reports the result.
class _RestoreEntry extends StatelessWidget {
  const _RestoreEntry({required this.onRestored});
  final VoidCallback onRestored;

  Future<void> _openRestore(BuildContext context) async {
    AudioManager.click();
    final controller = TextEditingController();
    String? errorText;
    var loading = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            Future<void> submit() async {
              if (loading) return;
              final raw = controller.text;
              final canon = Preferences.canonicalizeRecoveryCode(raw);
              if (!Preferences.isValidRecoveryCode(canon)) {
                setState(() => errorText = I18n.t.restoreInvalidCode);
                return;
              }
              setState(() {
                loading = true;
                errorText = null;
              });
              final ok = await Preferences.restoreFromRecoveryCode(canon);
              if (!ctx.mounted) return;
              if (ok) {
                ScaffoldMessenger.of(ctx)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(SnackBar(
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: const Color(0xFF1F0F38),
                    content: Text(
                      I18n.t.restoreSuccess,
                      style: JackDesign.manrope(
                        weight: FontWeight.w800,
                        color: JackDesign.green,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ));
                Navigator.of(ctx).pop();
                onRestored();
              } else {
                setState(() {
                  loading = false;
                  errorText = I18n.t.restoreNotFound;
                });
              }
            }

            return AlertDialog(
              backgroundColor: const Color(0xFF1F0F38),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: const BorderSide(color: JackDesign.purple, width: 1.5),
              ),
              title: Text(
                I18n.t.restoreProfileTitle,
                style: JackDesign.bungee(
                  fontSize: 14,
                  color: Colors.white,
                  letterSpacing: 1.2,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    I18n.t.restoreProfileDesc,
                    style: JackDesign.manrope(
                      fontSize: 11,
                      weight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    textCapitalization: TextCapitalization.characters,
                    style: JackDesign.bungee(
                      fontSize: 16,
                      color: Colors.white,
                      letterSpacing: 1.2,
                    ),
                    decoration: InputDecoration(
                      hintText: I18n.t.pasteCodeHint,
                      hintStyle: JackDesign.bungee(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.25),
                        letterSpacing: 1.2,
                      ),
                      errorText: errorText,
                      filled: true,
                      fillColor: Colors.black.withValues(alpha: 0.35),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.10),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                          color: JackDesign.yellow,
                          width: 1.5,
                        ),
                      ),
                    ),
                    onSubmitted: (_) => submit(),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: loading
                      ? null
                      : () {
                          AudioManager.click();
                          Navigator.of(ctx).pop();
                        },
                  child: Text(
                    I18n.t.cancel,
                    style: JackDesign.manrope(
                      fontSize: 12,
                      weight: FontWeight.w800,
                      color: Colors.white.withValues(alpha: 0.65),
                      letterSpacing: 1.6,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: loading ? null : submit,
                  child: Text(
                    I18n.t.restoreCta,
                    style: JackDesign.manrope(
                      fontSize: 12,
                      weight: FontWeight.w800,
                      color: JackDesign.yellow,
                      letterSpacing: 1.6,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton(
        onPressed: () => _openRestore(context),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          minimumSize: const Size(0, 28),
        ),
        child: Text(
          I18n.t.restoreProfile,
          style: JackDesign.manrope(
            fontSize: 10,
            weight: FontWeight.w800,
            color: Colors.white.withValues(alpha: 0.55),
            letterSpacing: 1.6,
          ).copyWith(decoration: TextDecoration.underline),
        ),
      ),
    );
  }
}

/// Speech-bubble overlay shown above the BR button when the user taps
/// it before completing the tutorial. Anchors to [anchorKey]'s render
/// box so the tail points at the exact button rect; falls back to a
/// centred-above-the-bottom position if the layout hasn't settled yet.
///
/// Tap anywhere on the bubble (or the surrounding transparent area) to
/// dismiss; the parent also auto-dismisses on a timer to avoid a stuck
/// hint if the user navigates elsewhere.
class _BrLockedBubbleAnchor extends StatefulWidget {
  const _BrLockedBubbleAnchor({
    required this.anchorKey,
    required this.onTap,
  });

  final GlobalKey anchorKey;
  final VoidCallback onTap;

  @override
  State<_BrLockedBubbleAnchor> createState() =>
      _BrLockedBubbleAnchorState();
}

class _BrLockedBubbleAnchorState extends State<_BrLockedBubbleAnchor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    )..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Mid-X of the BR button (so the bubble's tail sits at its centre).
  /// Returns null if the render box isn't ready — happens on the very
  /// first frame after a state change; the parent will rebuild as soon
  /// as it is.
  ({double centerX, double topY})? _anchorRect() {
    final ctx = widget.anchorKey.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final origin = box.localToGlobal(Offset.zero);
    return (
      centerX: origin.dx + box.size.width / 2,
      topY: origin.dy,
    );
  }

  @override
  Widget build(BuildContext context) {
    final anchor = _anchorRect();
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, child) {
            final t = Curves.easeOutBack.transform(_ctrl.value);
            return Opacity(
              opacity: _ctrl.value,
              child: Transform.translate(
                offset: Offset(0, 8 * (1 - t)),
                child: child,
              ),
            );
          },
          child: anchor == null
              ? const SizedBox.shrink()
              : _BrLockedBubble(
                  anchorCenterX: anchor.centerX,
                  anchorTopY: anchor.topY,
                ),
        ),
      ),
    );
  }
}

class _BrLockedBubble extends StatelessWidget {
  const _BrLockedBubble({
    required this.anchorCenterX,
    required this.anchorTopY,
  });

  /// Centre-X of the BR button in screen space — used both to centre
  /// the bubble horizontally above the button and to place the tail.
  final double anchorCenterX;
  /// Top edge of the BR button in screen space — the tail sits a few
  /// pixels above this.
  final double anchorTopY;

  @override
  Widget build(BuildContext context) {
    const tailHeight = 12.0;
    const gap = 8.0;
    // Estimated bubble height for positioning. Slight over-shoot so the
    // bubble's bottom (tail base) lands cleanly above the button.
    const bubbleEstHeight = 86.0;
    final size = MediaQuery.of(context).size;
    final bubbleTop =
        (anchorTopY - bubbleEstHeight - tailHeight - gap).clamp(40.0, double.infinity);
    return Stack(
      children: [
        Positioned(
          top: bubbleTop,
          left: 20,
          right: 20,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: CustomPaint(
                painter: _BrBubbleTailPainter(
                  // Tail x in the painter's local coords. We need to
                  // know where the bubble actually ends up on screen
                  // to anchor the tail under it.
                  bubbleScreenCenterX: size.width / 2,
                  anchorScreenCenterX: anchorCenterX,
                ),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: JackDesign.bg.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: JackDesign.purple, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: JackDesign.purple.withValues(alpha: 0.55),
                        blurRadius: 18,
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.40),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const JackIco(
                        name: IcoName.flame,
                        color: JackDesign.purple,
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          I18n.t.tutorialRequiredForBr,
                          style: JackDesign.manrope(
                            fontSize: 12,
                            weight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 1.0,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Draws the downward-pointing triangle below the BR-locked bubble.
/// The tail aims at the BR button's centre X regardless of where the
/// bubble itself ended up sitting (which is constrained by max-width
/// + screen padding).
class _BrBubbleTailPainter extends CustomPainter {
  _BrBubbleTailPainter({
    required this.bubbleScreenCenterX,
    required this.anchorScreenCenterX,
  });
  final double bubbleScreenCenterX;
  final double anchorScreenCenterX;

  @override
  void paint(Canvas canvas, Size size) {
    // Tail x within the bubble's local coords. We approximate the
    // bubble's local center as size.width/2 and offset toward the
    // anchor — clamped to stay inside the bubble's width with a 24 px
    // margin from each edge so the tail can't pop off.
    final delta = anchorScreenCenterX - bubbleScreenCenterX;
    final cx = (size.width / 2 + delta).clamp(24.0, size.width - 24.0);
    const tailWidth = 18.0;
    const tailHeight = 12.0;
    final baseY = size.height;
    final fill = Paint()..color = JackDesign.bg.withValues(alpha: 0.94);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round
      ..color = JackDesign.purple;
    final path = Path()
      ..moveTo(cx - tailWidth / 2, baseY - 1)
      ..lineTo(cx, baseY + tailHeight)
      ..lineTo(cx + tailWidth / 2, baseY - 1);
    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(_BrBubbleTailPainter old) =>
      old.bubbleScreenCenterX != bubbleScreenCenterX ||
      old.anchorScreenCenterX != anchorScreenCenterX;
}

/// Help dialog opened from the home's `?` icon. Currently exposes a
/// single action — replay the solo tutorial — but the layout is built
/// as a list so additional entries (FAQ links, support contact, etc.)
/// can drop in later without restructuring.
class _HelpDialog extends StatelessWidget {
  const _HelpDialog({required this.onReplayTutorial});
  final VoidCallback onReplayTutorial;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
        decoration: BoxDecoration(
          color: JackDesign.bg.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: JackDesign.yellow, width: 2),
          boxShadow: [
            BoxShadow(
              color: JackDesign.yellow.withValues(alpha: 0.35),
              blurRadius: 24,
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.55),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const JackIco(name: IcoName.help, color: JackDesign.yellow),
                const SizedBox(width: 10),
                Text(
                  I18n.t.helpTitle,
                  style: JackDesign.bungee(
                    fontSize: 18,
                    color: JackDesign.yellow,
                    letterSpacing: 3,
                  ),
                ),
                const Spacer(),
                _RoundIconBtn(
                  icoName: IcoName.close,
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'X',
                ),
              ],
            ),
            const SizedBox(height: 16),
            _HelpEntry(
              label: I18n.t.helpReplayTutorial,
              desc: I18n.t.helpReplayTutorialDesc,
              icoName: IcoName.replay,
              onPressed: onReplayTutorial,
            ),
          ],
        ),
      ),
    );
  }
}

/// One clickable row inside the help dialog. Icon on the left, label +
/// description on the right, full-width hit target. Same look-and-feel
/// as a list item so adding more entries doesn't break the rhythm.
class _HelpEntry extends StatelessWidget {
  const _HelpEntry({
    required this.label,
    required this.desc,
    required this.icoName,
    required this.onPressed,
  });
  final String label;
  final String desc;
  final IcoName icoName;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              JackIco(name: icoName, color: JackDesign.yellow),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: JackDesign.manrope(
                        fontSize: 13,
                        weight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 1.6,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      desc,
                      style: JackDesign.manrope(
                        fontSize: 11,
                        weight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.60),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cold-start intro for the home mascot: two squash-and-stretch jumps
/// (low + high) with a ground-locked shadow that shrinks while the cube
/// is airborne, then settles into the regular [JackMascot] (with its
/// idle wink). The controller finishing leaves the widget in a clean
/// resting pose — no extra animation while the user is on the home.
class _JumpingMascot extends StatelessWidget {
  const _JumpingMascot({required this.intro});

  final Animation<double> intro;

  static const double _mascotSize = 84;
  // JackMascot's SVG body occupies y=14..106 inside a 120-unit viewport,
  // so in an 84 px box the body's visible bottom sits at 84 * 106/120 =
  // 74.2 px (≈ 9.8 px of empty space below it). The squash anchor and
  // the ground shadow are both placed against this visible bottom so the
  // cube reads as compressing against the floor rather than against an
  // invisible point 10 px lower.
  static const double _bodyBottomFrac = 106 / 120; // 0.883
  // Alignment.y maps -1 (top) → 1 (bottom). 0.883 of the height in a
  // top-anchored space = 2 * 0.883 - 1 = 0.766.
  static const double _squashAnchorY = 2 * _bodyBottomFrac - 1;
  // Headroom = highest peak + small safety. Second jump peaks at 110.
  static const double _slotHeight = _mascotSize + 130;

  // Highest point each jump reaches (px above resting ground). The first
  // jump is deliberately smaller to read as "preparing" before the
  // second, weightier hop.
  static const double _jump1Height = 60;
  static const double _jump2Height = 100;

  // Timeline (fraction of the intro controller, total 1500 ms):
  //   0.000 → 0.233 : jump 1 (≈ 350 ms)
  //   0.233 → 0.533 : jump 2 (≈ 450 ms)
  //   0.533 → 1.000 : settled (UI fade-in zone)
  static const double _jump1End = 0.233;
  static const double _jump2End = 0.533;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _mascotSize + 40,
      height: _slotHeight,
      child: AnimatedBuilder(
        animation: intro,
        builder: (context, _) {
          final pose = _poseFor(intro.value);
          // Cube's mascot box bottom is placed so the body's visible
          // bottom rests at `groundFromSlotBottom` (= 14 px from the
          // slot bottom, matching the shadow line). 14 px chosen so the
          // shadow has enough room below without clipping.
          const groundFromSlotBottom = 14.0;
          final boxBottom = groundFromSlotBottom -
              _mascotSize * (1 - _bodyBottomFrac);
          return Stack(
            alignment: Alignment.bottomCenter,
            clipBehavior: Clip.none,
            children: [
              // Ground shadow — sits exactly on the cube's visible
              // baseline, shrinks and fades while the cube is in the
              // air, then fades out completely once we settle so the
              // home screen doesn't keep a permanent oval on the floor.
              Positioned(
                bottom: groundFromSlotBottom - 4,
                child: Opacity(
                  opacity: pose.shadowAlpha,
                  child: Container(
                    width: 64 * pose.shadowScale,
                    height: 8 * pose.shadowScale,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius:
                          const BorderRadius.all(Radius.elliptical(32, 4)),
                    ),
                  ),
                ),
              ),
              // Cube — translate then squash. The squash is anchored on
              // the body's visible bottom (not the SizedBox bottom) so
              // the compression visibly meets the floor.
              Positioned(
                bottom: boxBottom,
                child: Transform.translate(
                  offset: Offset(0, pose.dy),
                  child: Transform(
                    alignment: const Alignment(0, _squashAnchorY),
                    transform: Matrix4.diagonal3Values(pose.sx, pose.sy, 1),
                    // Glow stays on but the cube's own internal drop
                    // shadow follows it skyward — that's an attached
                    // ambient shadow, not a ground shadow, so it reads
                    // as "the cube has weight" without competing with
                    // the floor shadow that's doing the lift narrative.
                    child: const JackMascot(
                      size: _mascotSize,
                      face: MascotFace.smile,
                      idleAnimated: true,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Returns the mascot pose for a given controller fraction `t`.
  static _MascotPose _poseFor(double t) {
    _MascotPose pose;
    if (t < _jump1End) {
      pose = _jumpPose(t / _jump1End, _jump1Height);
    } else if (t < _jump2End) {
      pose = _jumpPose((t - _jump1End) / (_jump2End - _jump1End),
          _jump2Height);
    } else {
      pose = const _MascotPose(0, 1, 1, 1, 1);
    }
    // Once the jumps are done fade the ground shadow out over ~150 ms
    // so the home screen doesn't end with a permanent dark oval under
    // the mascot.
    if (t > _jump2End) {
      final fade =
          ((t - _jump2End) / 0.10).clamp(0.0, 1.0);
      pose = _MascotPose(
        pose.dy,
        pose.sx,
        pose.sy,
        pose.shadowScale,
        pose.shadowAlpha * (1.0 - fade),
      );
    }
    return pose;
  }

  /// Single-jump envelope. `p ∈ [0, 1]` is the local progress through
  /// one jump cycle. dy = 0 at both endpoints so jumps chain cleanly
  /// without a vertical discontinuity at the boundary; squash and
  /// stretch run through every phase smoothly.
  ///
  /// Phases (within one jump):
  ///   0.00 → 0.12 : crouch  (sy 1.00 → 0.70, sx 1.00 → 1.25)
  ///   0.12 → 0.20 : push    (sy 0.70 → 1.25, sx 1.25 → 0.92)
  ///   0.20 → 0.82 : airborne (sine arc, sy 1.05, sx 0.95)
  ///   0.82 → 0.90 : impact  (sy 1.05 → 0.62, sx 0.95 → 1.30)
  ///   0.90 → 1.00 : recover (sy 0.62 → 1.00, sx 1.30 → 1.00)
  static _MascotPose _jumpPose(double p, double height) {
    p = p.clamp(0.0, 1.0);
    double dy = 0, sx = 1, sy = 1;
    if (p < 0.12) {
      final k = p / 0.12;
      sy = 1.00 - 0.30 * k;
      sx = 1.00 + 0.25 * k;
    } else if (p < 0.20) {
      final k = (p - 0.12) / 0.08;
      sy = 0.70 + 0.55 * k;
      sx = 1.25 - 0.33 * k;
    } else if (p < 0.82) {
      final k = (p - 0.20) / 0.62;
      dy = -math.sin(k * math.pi) * height;
      sy = 1.05;
      sx = 0.95;
    } else if (p < 0.90) {
      final k = (p - 0.82) / 0.08;
      sy = 1.05 - 0.43 * k;
      sx = 0.95 + 0.35 * k;
    } else {
      final k = (p - 0.90) / 0.10;
      sy = 0.62 + 0.38 * k;
      sx = 1.30 - 0.30 * k;
    }
    // Ground shadow scales with how high the cube is — biggest when the
    // cube is grounded, smallest (and faintest) at the apex.
    final airborne = (-dy / height).clamp(0.0, 1.0);
    final shadowK = 1.0 - 0.60 * airborne;
    return _MascotPose(dy, sx, sy, shadowK, shadowK);
  }
}

class _MascotPose {
  const _MascotPose(
    this.dy,
    this.sx,
    this.sy,
    this.shadowScale,
    this.shadowAlpha,
  );
  final double dy;
  final double sx;
  final double sy;
  final double shadowScale;
  final double shadowAlpha;
}
