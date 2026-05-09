import 'dart:math';

import 'package:flutter/material.dart';

import '../../game/config.dart';
import '../../game/jumping_jack_game.dart';
import '../../services/audio_manager.dart';
import '../../services/preferences.dart';
import '../widgets/fortnite_button.dart';

/// Onboarding tutorial: pauses the game, plays an animated demo of the
/// hold → drag → release gesture, and only resumes when the player taps
/// "JE SUIS PRÊT".
class TutorialOverlay extends StatefulWidget {
  const TutorialOverlay({super.key, required this.game});

  final JumpingJackGame game;

  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<TutorialOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _dismissed = false;
  bool _dontShowAgain = false;

  static const _demoDuration = Duration(milliseconds: 5000);

  @override
  void initState() {
    super.initState();
    // If the player disabled the tutorial, dismiss immediately without
    // pausing the engine.
    if (!Preferences.showTutorial) {
      _dismissed = true;
      _controller = AnimationController(vsync: this);
      return;
    }
    // Pause the engine so the game world is frozen behind the tutorial.
    widget.game.pauseEngine();
    _controller = AnimationController(
      vsync: this,
      duration: _demoDuration,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    if (!_dismissed) widget.game.resumeEngine();
    super.dispose();
  }

  void _ready() {
    AudioManager.click();
    Preferences.showTutorial = !_dontShowAgain;
    widget.game.resumeEngine();
    _controller.stop();
    setState(() => _dismissed = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();

    return Stack(
      children: [
        // Backdrop
        Positioned.fill(
          child: Container(color: Colors.black.withValues(alpha: 0.55)),
        ),
        // Animated demo (finger + trail) — fullscreen painter
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => CustomPaint(
              painter: _DemoPainter(t: _controller.value),
            ),
          ),
        ),
        // Top: step text
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => _StepText(t: _controller.value),
              ),
            ),
          ),
        ),
        // Bottom: ready button + "Ne plus afficher" checkbox
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ReadyButton(onPressed: _ready),
                  const SizedBox(height: 14),
                  _DontShowToggle(
                    value: _dontShowAgain,
                    onChanged: (v) =>
                        setState(() => _dontShowAgain = v),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DemoPainter extends CustomPainter {
  _DemoPainter({required this.t});
  final double t;

  // Phase boundaries on the [0..1] timeline
  static const double _fadeIn = 0.04;
  static const double _holdEnd = 0.30;
  static const double _dragEnd = 0.65;
  static const double _releaseEnd = 0.82;

  @override
  void paint(Canvas canvas, Size size) {
    // Anchor: where the player roughly sits on screen.
    final start = Offset(size.width / 2, size.height * 0.70);
    // Drag target: up-right of the player.
    final target = Offset(size.width / 2 + 75, size.height * 0.40);

    Offset fingerPos;
    double scale;
    double alpha;
    bool drawTrail = false;
    double dragProgress = 0;

    if (t < _fadeIn) {
      // Fade in
      alpha = t / _fadeIn;
      fingerPos = start;
      scale = 1.4 - alpha * 0.7; // 1.4 → 0.7
    } else if (t < _holdEnd) {
      // Hold — slight pulse to communicate "press and hold"
      final p = (t - _fadeIn) / (_holdEnd - _fadeIn);
      fingerPos = start;
      scale = 0.7 + 0.06 * sin(p * pi * 4);
      alpha = 1.0;
    } else if (t < _dragEnd) {
      // Drag from start to target
      final p = (t - _holdEnd) / (_dragEnd - _holdEnd);
      final eased = Curves.easeInOut.transform(p);
      fingerPos = Offset.lerp(start, target, eased)!;
      scale = 0.7;
      alpha = 1.0;
      drawTrail = true;
      dragProgress = eased;
    } else if (t < _releaseEnd) {
      // Release — scale up + fade out
      final p = (t - _dragEnd) / (_releaseEnd - _dragEnd);
      fingerPos = target;
      scale = 0.7 + p * 0.7; // 0.7 → 1.4
      alpha = (1 - p).clamp(0.0, 1.0);
      drawTrail = true;
      dragProgress = 1.0;
    } else {
      return; // gap before next loop
    }

    // Trail of yellow dots from start to current finger position
    if (drawTrail && dragProgress > 0) {
      final trailEnd =
          Offset.lerp(start, target, dragProgress)!;
      const dotCount = 8;
      for (var i = 0; i < dotCount; i++) {
        final tt = (i + 1) / (dotCount + 1);
        final pos = Offset.lerp(start, trailEnd, tt)!;
        final dotAlpha = (1 - tt * 0.6) * 0.8 * alpha;
        final radius = 4.5 - tt * 1.5;
        canvas.drawCircle(
          pos,
          radius,
          Paint()
            ..color =
                GameConfig.playerColor.withValues(alpha: dotAlpha),
        );
      }
    }

    // Glow halo
    canvas.drawCircle(
      fingerPos,
      26 * scale,
      Paint()
        ..color = GameConfig.playerColor.withValues(alpha: 0.45 * alpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
    // Outer ring
    canvas.drawCircle(
      fingerPos,
      19 * scale,
      Paint()..color = GameConfig.playerColor.withValues(alpha: alpha),
    );
    // Bright core
    canvas.drawCircle(
      fingerPos,
      8 * scale,
      Paint()..color = Colors.white.withValues(alpha: 0.92 * alpha),
    );
  }

  @override
  bool shouldRepaint(_DemoPainter old) => old.t != t;
}

class _StepText extends StatelessWidget {
  const _StepText({required this.t});
  final double t;

  @override
  Widget build(BuildContext context) {
    final String title;
    final String subtitle;

    if (t < _DemoPainter._holdEnd) {
      title = 'MAINTIENS';
      subtitle = 'Appuie et garde ton doigt enfoncé';
    } else if (t < _DemoPainter._dragEnd) {
      title = 'VISE';
      subtitle = 'Glisse ton doigt vers la direction du saut';
    } else {
      title = 'RELÂCHE';
      subtitle = 'Le saut part dans la direction visée';
    }

    final step = t < _DemoPainter._holdEnd
        ? 1
        : t < _DemoPainter._dragEnd
            ? 2
            : 3;

    return Column(
      children: [
        Text(
          'TUTORIEL  —  $step / 3',
          style: const TextStyle(
            color: GameConfig.textMuted,
            fontSize: 11,
            letterSpacing: 5,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: GameConfig.playerColor,
            fontSize: 32,
            fontWeight: FontWeight.w900,
            letterSpacing: 6,
            shadows: [
              Shadow(
                color: GameConfig.playerColor.withValues(alpha: 0.55),
                blurRadius: 16,
              ),
              const Shadow(
                color: Colors.black54,
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}

class _DontShowToggle extends StatelessWidget {
  const _DontShowToggle({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        AudioManager.click();
        onChanged(!value);
      },
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: value
                    ? GameConfig.playerColor
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: value
                      ? GameConfig.playerColor
                      : Colors.white54,
                  width: 2,
                ),
              ),
              child: value
                  ? const Icon(Icons.check,
                      size: 14, color: GameConfig.bgColor)
                  : null,
            ),
            const SizedBox(width: 10),
            const Text(
              'Ne plus afficher',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadyButton extends StatelessWidget {
  const _ReadyButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: FortniteButton(
        label: 'JE SUIS PRÊT',
        icon: Icons.rocket_launch_rounded,
        onPressed: onPressed,
        height: 60,
      ),
    );
  }
}
