import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../game/jumping_jack_game.dart';
import '../../i18n/i18n.dart';
import '../../services/audio_manager.dart';
import '../../services/preferences.dart';
import '../theme/jack_design.dart';
import '../widgets/fortnite_button.dart';
import '../widgets/jack_cloud.dart';
import '../widgets/jack_ico.dart';
import '../widgets/jack_mascot.dart';

/// Onboarding tutorial: pauses the game, walks through the
/// HOLD → AIM → RELEASE phases. The user can either tap a phase tab or
/// swipe horizontally between phases.
class TutorialOverlay extends StatefulWidget {
  const TutorialOverlay({super.key, required this.game});

  final JumpingJackGame game;

  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<TutorialOverlay>
    with SingleTickerProviderStateMixin {
  late final PageController _pageController;
  late final AnimationController _controller;
  bool _dismissed = false;
  int _phase = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    if (!Preferences.showTutorial) {
      _dismissed = true;
      _controller = AnimationController(vsync: this);
      return;
    }
    widget.game.pauseEngine();
    // Continuous loop driving the demo animations (finger pulse, gauge,
    // mascot float). Independent of the page navigation.
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _controller.dispose();
    if (!_dismissed) widget.game.resumeEngine();
    super.dispose();
  }

  void _selectPhase(int p) {
    AudioManager.click();
    _pageController.animateToPage(
      p,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _ready() {
    AudioManager.uiConfirm();
    // Tapping "JE SUIS PRÊT" implicitly dismisses the tutorial for good —
    // no opt-in checkbox. Players who want the tutorial back can re-enable
    // it from settings (or by reinstalling).
    Preferences.showTutorial = false;
    widget.game.resumeEngine();
    _controller.stop();
    setState(() => _dismissed = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();

    final titles = [
      I18n.t.tutorialHold,
      I18n.t.tutorialAim,
      I18n.t.tutorialRelease,
    ];
    final descriptions = [
      I18n.t.tutorialHoldDesc,
      I18n.t.tutorialAimDesc,
      I18n.t.tutorialReleaseDesc,
    ];
    final isLastPhase = _phase == 2;

    return Stack(
      // `StackFit.expand` forces the Stack to grow to the parent's full
      // size — without it the Stack would shrink to its non-positioned
      // child (the SafeArea + Column, only as wide as the inner content)
      // and the dimmed backdrop wouldn't cover the screen edges, leaving
      // the decorative clouds visible on the sides.
      fit: StackFit.expand,
      children: [
        // Faint platforms behind, then dimmed backdrop.
        Positioned.fill(
          child: Stack(
            children: const [
              Positioned(
                left: 28,
                top: 110,
                child: Opacity(opacity: 0.40, child: JackCloud(width: 100)),
              ),
              Positioned(
                right: 24,
                top: 200,
                child: Opacity(opacity: 0.40, child: JackCloud(width: 100)),
              ),
            ],
          ),
        ),
        Positioned.fill(
          child: ColoredBox(color: Colors.black.withValues(alpha: 0.88)),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
            child: Column(
              children: [
                // Swipeable phase content (titre + description + démo).
                Expanded(
                  // Web: Flutter's default ScrollBehavior excludes mouse
                  // drag. Override here so the user can slide the slider
                  // with the mouse, not just touch / scroll wheel.
                  child: ScrollConfiguration(
                    behavior: const _DragMouseScrollBehavior(),
                    child: PageView.builder(
                      controller: _pageController,
                      itemCount: 3,
                      // Bouncy physics so the user clearly feels the swipe
                      // is available — and overscroll bounces back on edge
                      // pages.
                      physics: const BouncingScrollPhysics(),
                      onPageChanged: (i) => setState(() => _phase = i),
                      itemBuilder: (_, i) {
                        return _PhasePage(
                          phase: i,
                          title: titles[i],
                          description: descriptions[i],
                          controller: _controller,
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Step counter — "1 / 3" sits just above the button row,
                // right-aligned + right-padded to line up with the trailing
                // edge of the right button (compensates for the letter-
                // spaced last digit + a small breathing margin).
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      I18n.t.tutorialStep(_phase + 1),
                      style: JackDesign.manrope(
                        fontSize: 11,
                        weight: FontWeight.w800,
                        color: Colors.white.withValues(alpha: 0.55),
                        letterSpacing: 2.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // RETOUR (cyan) on the left, SUIVANT / PRÊT (primary or
                // epic) on the right. Same vocabulary as the death / BR
                // result screens so the navigation feels consistent. Swipe
                // also still works thanks to the PageView underneath.
                Row(
                  children: [
                    if (_phase > 0) ...[
                      Expanded(
                        child: FortniteButton(
                          label: I18n.t.back,
                          icoName: IcoName.arrowLeft,
                          style: FortniteButtonStyle.cyan,
                          onPressed: () => _selectPhase(_phase - 1),
                          height: 56,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: FortniteButton(
                        label: isLastPhase ? I18n.t.ready : I18n.t.next,
                        icoName: isLastPhase ? IcoName.check : IcoName.play,
                        // SUIVANT en jaune, JE SUIS PRÊT en vert — le vert
                        // (validation / go) tranche clairement du violet
                        // BR pour éviter toute confusion de mode.
                        style: isLastPhase
                            ? FortniteButtonStyle.green
                            : FortniteButtonStyle.primary,
                        onPressed: isLastPhase
                            ? _ready
                            : () => _selectPhase(_phase + 1),
                        height: 56,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PhasePage extends StatelessWidget {
  const _PhasePage({
    required this.phase,
    required this.title,
    required this.description,
    required this.controller,
  });
  final int phase;
  final String title;
  final String description;
  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: JackDesign.bungee(
            fontSize: 28,
            color: JackDesign.yellow,
            letterSpacing: 2,
            shadows: [
              const Shadow(
                color: JackDesign.brown,
                offset: Offset(0, 2),
              ),
              Shadow(
                color: JackDesign.yellow.withValues(alpha: 0.35),
                blurRadius: 18,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // One-liner sitting under the big phase title. Spells out *what* to
        // do — the big word alone (e.g. "MAINTIENS") doesn't tell a new
        // player which gesture to perform.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            description,
            textAlign: TextAlign.center,
            style: JackDesign.manrope(
              fontSize: 13,
              weight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.78),
              letterSpacing: 0.4,
              height: 1.35,
            ),
          ),
        ),
        const SizedBox(height: 20),
        AnimatedBuilder(
          animation: controller,
          builder: (_, child) => _Demo(phase: phase, t: controller.value),
        ),
      ],
    );
  }
}

/// Adds mouse to the set of pointer kinds that can drag a Scrollable —
/// Flutter's default `MaterialScrollBehavior` only listens to touch +
/// stylus, so on the web the tutorial slider can't be dragged with a
/// mouse without this override.
class _DragMouseScrollBehavior extends MaterialScrollBehavior {
  const _DragMouseScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.trackpad,
      };
}

class _Demo extends StatelessWidget {
  const _Demo({required this.phase, required this.t});
  final int phase;
  final double t;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      height: 240,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Cloud platform.
          const Positioned(
            bottom: 30,
            child: JackCloud(width: 120),
          ),
          // Mascot face per phase.
          Positioned(
            bottom: 70 + (phase == 2 ? 6 * sin(t * pi * 2) : 0),
            child: JackMascot(
              size: 64,
              face: phase == 2
                  ? MascotFace.excited
                  : phase == 1
                      ? MascotFace.determined
                      : MascotFace.charge,
            ),
          ),
          // Aim arc (phase 1).
          if (phase == 1)
            Positioned.fill(
              child: CustomPaint(painter: _AimArcPainter()),
            ),
          // Charge gauge (phase 0).
          if (phase == 0)
            Positioned(
              bottom: 6,
              child: SizedBox(
                width: 80,
                height: 6,
                child: CustomPaint(painter: _GaugePainter(t: t)),
              ),
            ),
          // Finger pulse.
          Positioned(
            bottom: 0 + 8 * (sin(t * pi * 2) * 0.5 + 0.5),
            child: const JackIco(
              name: IcoName.finger,
              size: 42,
              color: JackDesign.yellow,
            ),
          ),
        ],
      ),
    );
  }
}

class _AimArcPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = JackDesign.yellow.withValues(alpha: 0.80)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final dashed = _dashPath(
      Path()
        ..moveTo(size.width * 0.50, size.height * 0.54)
        ..quadraticBezierTo(
          size.width * 0.78,
          size.height * 0.20,
          size.width * 0.92,
          size.height * 0.34,
        ),
      dash: 4,
      gap: 6,
    );
    canvas.drawPath(dashed, paint);
    canvas.drawCircle(
      Offset(size.width * 0.92, size.height * 0.34),
      6,
      Paint()..color = JackDesign.yellow,
    );
  }

  Path _dashPath(Path src, {required double dash, required double gap}) {
    final out = Path();
    for (final m in src.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        out.addPath(m.extractPath(d, d + dash), Offset.zero);
        d += dash + gap;
      }
    }
    return out;
  }

  @override
  bool shouldRepaint(_AimArcPainter old) => false;
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({required this.t});
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final r = const Radius.circular(999);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, r),
      Paint()..color = Colors.white.withValues(alpha: 0.10),
    );
    final fillW = size.width * (0.30 + 0.70 * (sin(t * pi * 2) * 0.5 + 0.5));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, fillW, size.height),
        r,
      ),
      Paint()
        ..shader = const LinearGradient(
          colors: [JackDesign.yellowHi, JackDesign.yellow, JackDesign.red],
        ).createShader(Rect.fromLTWH(0, 0, fillW, size.height)),
    );
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.t != t;
}

