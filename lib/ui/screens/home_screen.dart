import 'dart:math';

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
const String kAppVersion = 'v3.0';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  // Picked once per HomeScreen mount → on every relaunch / return-to-menu the
  // background world is randomized.
  late final JackStage _stage;
  late final AnimationController _floatCtrl;

  @override
  void initState() {
    super.initState();
    final rng = Random();
    _stage = JackStage.worlds[rng.nextInt(JackStage.worlds.length)];
    _floatCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat(reverse: true);
    WidgetsBinding.instance.addObserver(this);
    I18n.instance.addListener(_onLocaleChanged);
    AudioManager.preload().then((_) => AudioManager.startMenuMusic());
  }

  @override
  void dispose() {
    _floatCtrl.dispose();
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
                  Row(
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
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedBuilder(
                          animation: _floatCtrl,
                          builder: (context, child) {
                            final t = Curves.easeInOut.transform(_floatCtrl.value);
                            return Transform.translate(
                              offset: Offset(0, -6 * t),
                              child: child,
                            );
                          },
                          child: const JackMascot(size: 84, face: MascotFace.smile),
                        ),
                        const SizedBox(height: 14),
                        const JackLogo(),
                      ],
                    ),
                  ),
                  // Pseudo chip sits just above the action buttons — same
                  // visual stack as the death / BR result overlays where
                  // the player identity reads right next to the CTA row.
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
                          child: FortniteButton(
                            label: I18n.t.battleRoyale,
                            icoName: IcoName.flame,
                            style: FortniteButtonStyle.epic,
                            onPressed: _openBattleRoyale,
                            height: 60,
                            fontSize: 14,
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
    );
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

  void _toggleMute() async {
    AudioManager.click();
    final next = !Preferences.muted;
    Preferences.muted = next;
    await AudioManager.setMuted(next);
    if (mounted) setState(() {});
  }

  void _openBattleRoyale() {
    AudioManager.click();
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
