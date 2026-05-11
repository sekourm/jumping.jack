import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/jack_design.dart';

enum MascotFace { smile, excited, determined, charge, dead }

/// Vector mascot cube — Flutter port of the Mascot SVG component from the
/// design handoff. 5 face variants, optional glow. The body defaults to
/// the JJ yellow but can be tinted (used by the BR result screen so the
/// winner's mascot reflects their slot colour).
///
/// When [idleAnimated] is true the mascot adds a subtle life-of-its-own
/// behaviour: it occasionally winks (alternating eyes, random 2.5-6 s
/// interval). Only the [MascotFace.smile] face renders the wink — for
/// the other faces the flag is a no-op so the screen stays as designed.
class JackMascot extends StatefulWidget {
  const JackMascot({
    super.key,
    this.size = 80,
    this.face = MascotFace.smile,
    this.glow = true,
    this.bodyColor,
    this.idleAnimated = false,
  });

  final double size;
  final MascotFace face;
  final bool glow;
  final Color? bodyColor;

  /// Enables the autonomous wink animation. Opt-in: most places (lobby,
  /// BR result, tutorial) want the static face so the wink doesn't pull
  /// the eye away from the rest of the UI. The home screen turns it on.
  final bool idleAnimated;

  @override
  State<JackMascot> createState() => _JackMascotState();
}

class _JackMascotState extends State<JackMascot>
    with SingleTickerProviderStateMixin {
  /// Drives the wink envelope: 0 → 1 → 0 in ~600 ms. Reset to 0 between
  /// winks. Kept as a single controller for the lifetime of the widget so
  /// we don't allocate/dispose on every wink (a wink fires every few
  /// seconds, but allocating a controller in a 60 fps build cycle still
  /// shows up in the trace).
  AnimationController? _winkCtrl;
  Timer? _winkTimer;
  bool _winkLeftEye = true;
  final Random _rng = Random();

  @override
  void initState() {
    super.initState();
    if (_shouldAnimate()) _initWinkController();
  }

  @override
  void didUpdateWidget(JackMascot old) {
    super.didUpdateWidget(old);
    final now = _shouldAnimate();
    final was = old.idleAnimated && old.face == MascotFace.smile;
    if (now && !was) {
      _initWinkController();
    } else if (!now && was) {
      _disposeWink();
    }
  }

  @override
  void dispose() {
    _disposeWink();
    super.dispose();
  }

  bool _shouldAnimate() =>
      widget.idleAnimated && widget.face == MascotFace.smile;

  void _initWinkController() {
    _winkCtrl ??= AnimationController(
      vsync: this,
      // Closing + opening together feels like a single ~600 ms wink.
      // Curves.easeInOutQuad on top of this gives a believable lid
      // motion (acceleration into the close, deceleration out of it).
      duration: const Duration(milliseconds: 300),
    )..addListener(_repaintOnTick)
      ..addStatusListener(_onWinkStatus);
    _scheduleNextWink(initial: true);
  }

  void _disposeWink() {
    _winkTimer?.cancel();
    _winkTimer = null;
    _winkCtrl?.dispose();
    _winkCtrl = null;
  }

  void _repaintOnTick() {
    if (mounted) setState(() {});
  }

  void _onWinkStatus(AnimationStatus status) {
    if (!mounted) return;
    if (status == AnimationStatus.completed) {
      // Lid fully closed — reverse to open the eye.
      _winkCtrl?.reverse();
    } else if (status == AnimationStatus.dismissed) {
      // Eye back open — queue the next wink.
      _scheduleNextWink();
    }
  }

  void _scheduleNextWink({bool initial = false}) {
    _winkTimer?.cancel();
    // 20 s between winks (4 s for the first one so something visibly
    // happens shortly after the home screen lands — otherwise the user
    // would wait a full 20 s for the first sign of life). Tuned by user
    // request: less frequent than a natural blink, just enough to feel
    // alive without being distracting on a screen the user lingers on.
    final delay = Duration(seconds: initial ? 4 : 20);
    _winkTimer = Timer(delay, () {
      if (!mounted || _winkCtrl == null) return;
      _winkLeftEye = _rng.nextBool();
      _winkCtrl!.forward(from: 0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final winkProgress = _winkCtrl == null
        ? 0.0
        : Curves.easeInOut.transform(_winkCtrl!.value);
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: CustomPaint(
        painter: _MascotPainter(
          face: widget.face,
          glow: widget.glow,
          bodyColor: widget.bodyColor ?? JackDesign.yellow,
          winkProgress: winkProgress,
          winkLeftEye: _winkLeftEye,
        ),
      ),
    );
  }
}

class _MascotPainter extends CustomPainter {
  _MascotPainter({
    required this.face,
    required this.glow,
    required this.bodyColor,
    this.winkProgress = 0,
    this.winkLeftEye = true,
  });
  final MascotFace face;
  final bool glow;
  final Color bodyColor;

  /// 0 = both eyes open, 1 = the [winkLeftEye] eye fully closed. Only
  /// consulted by [_drawSmile]; the other faces don't have a wink frame.
  final double winkProgress;
  final bool winkLeftEye;

  @override
  void paint(Canvas canvas, Size size) {
    // The SVG is authored in a 120x120 viewBox.
    final s = size.width / 120;
    canvas.save();
    canvas.scale(s, s);

    if (glow) {
      // Soft glow halo behind the cube.
      final glowRect = Rect.fromLTWH(8, 8, 104, 104);
      canvas.drawRRect(
        RRect.fromRectAndRadius(glowRect, const Radius.circular(22)),
        Paint()
          ..color = bodyColor.withValues(alpha: 0.40)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
      );
      // Drop shadow under the cube.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(14, 22, 92, 92),
          const Radius.circular(18),
        ),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.40)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }

    // Body — gradient (light → base → dark) with darkened stroke.
    final lightTop = Color.lerp(bodyColor, Colors.white, 0.40)!;
    final darkBottom = Color.lerp(bodyColor, Colors.black, 0.50)!;
    final stroke = Color.lerp(bodyColor, Colors.black, 0.65)!;
    final body = RRect.fromRectAndRadius(
      const Rect.fromLTWH(14, 14, 92, 92),
      const Radius.circular(18),
    );
    final bodyRect = Rect.fromLTWH(14, 14, 92, 92);
    canvas.drawRRect(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [lightTop, bodyColor, darkBottom],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(bodyRect),
    );
    canvas.drawRRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeJoin = StrokeJoin.round
        ..color = stroke,
    );

    // Top crown highlight (white-fade band).
    final crown = RRect.fromRectAndRadius(
      const Rect.fromLTWH(22, 20, 76, 14),
      const Radius.circular(8),
    );
    canvas.drawRRect(
      crown,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.80),
            Colors.white.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.5],
        ).createShader(const Rect.fromLTWH(22, 20, 76, 14))
        ..colorFilter = ColorFilter.mode(
          Colors.white.withValues(alpha: 0.7),
          BlendMode.dstIn,
        ),
    );

    // Face per variant.
    switch (face) {
      case MascotFace.smile:
        _drawSmile(canvas);
      case MascotFace.excited:
        _drawExcited(canvas);
      case MascotFace.determined:
        _drawDetermined(canvas);
      case MascotFace.charge:
        _drawCharge(canvas);
      case MascotFace.dead:
        _drawDead(canvas);
    }

    canvas.restore();
  }

  static final _ink = Paint()..color = const Color(0xFF1A1A1A);
  static final _white = Paint()..color = Colors.white;

  static Paint _stroke(Color c, double w) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round
    ..color = c;

  void _drawSmile(Canvas canvas) {
    const leftEye = Rect.fromLTWH(37, 49, 18, 22);
    const rightEye = Rect.fromLTWH(65, 49, 18, 22);
    const leftPupil = Offset(48, 62);
    const rightPupil = Offset(76, 62);
    _drawEye(canvas, leftEye, leftPupil,
        winkProgress: winkLeftEye ? winkProgress : 0);
    _drawEye(canvas, rightEye, rightPupil,
        winkProgress: winkLeftEye ? 0 : winkProgress);
    final path = Path()
      ..moveTo(45, 80)
      ..quadraticBezierTo(60, 92, 75, 80);
    canvas.drawPath(path, _stroke(JackDesign.brown, 4));
  }

  /// Renders one eye — open by default, partially or fully closed when
  /// [winkProgress] > 0. Implementation: shrink the white oval vertically
  /// toward its center as the lid closes, then cross-fade to a small
  /// upward arc (a closed-eye smile) for the last segment of the wink.
  void _drawEye(
    Canvas canvas,
    Rect openRect,
    Offset pupilCenter, {
    required double winkProgress,
  }) {
    if (winkProgress <= 0) {
      canvas.drawOval(openRect, _white);
      canvas.drawCircle(pupilCenter, 4, _ink);
      return;
    }
    final closed = winkProgress.clamp(0.0, 1.0);
    // Phase 1 (0 → 0.85): shrink the open eye vertically.
    if (closed < 0.95) {
      final shrinkPx = openRect.height * 0.45 * closed;
      final shrunk = Rect.fromLTRB(
        openRect.left,
        openRect.top + shrinkPx,
        openRect.right,
        openRect.bottom - shrinkPx,
      );
      if (shrunk.height > 1) {
        canvas.drawOval(shrunk, _white);
        if (shrunk.height > 8) {
          canvas.drawCircle(pupilCenter, 4, _ink);
        }
      }
    }
    // Phase 2 (0.6 → 1.0): fade in the closed-eye arc.
    if (closed > 0.6) {
      final arcAlpha = ((closed - 0.6) / 0.4).clamp(0.0, 1.0);
      final cx = openRect.center.dx;
      final cy = openRect.center.dy + 1;
      final path = Path()
        ..moveTo(cx - 8, cy + 2)
        ..quadraticBezierTo(cx, cy - 4, cx + 8, cy + 2);
      canvas.drawPath(
        path,
        _stroke(JackDesign.brown.withValues(alpha: arcAlpha), 3),
      );
    }
  }

  void _drawExcited(Canvas canvas) {
    canvas.drawOval(const Rect.fromLTWH(37, 47, 18, 22), _white);
    canvas.drawOval(const Rect.fromLTWH(65, 47, 18, 22), _white);
    canvas.drawCircle(const Offset(46, 58), 5, _ink);
    canvas.drawCircle(const Offset(74, 58), 5, _ink);
    canvas.drawOval(
      const Rect.fromLTWH(52, 75, 16, 18),
      Paint()..color = JackDesign.brown,
    );
    canvas.drawOval(
      const Rect.fromLTWH(55, 77, 10, 10),
      Paint()..color = const Color(0xFF3A1F00),
    );
  }

  void _drawDetermined(Canvas canvas) {
    final brow = Paint()..color = JackDesign.brown;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(38, 56, 16, 6),
        const Radius.circular(3),
      ),
      brow,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(66, 56, 16, 6),
        const Radius.circular(3),
      ),
      brow,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(44, 80, 32, 6),
        const Radius.circular(3),
      ),
      brow,
    );
  }

  void _drawCharge(Canvas canvas) {
    canvas.drawLine(
      const Offset(38, 58),
      const Offset(54, 64),
      _stroke(JackDesign.brown, 5),
    );
    canvas.drawLine(
      const Offset(66, 64),
      const Offset(82, 58),
      _stroke(JackDesign.brown, 5),
    );
    final mouth = RRect.fromRectAndRadius(
      const Rect.fromLTWH(44, 80, 32, 8),
      const Radius.circular(2),
    );
    canvas.drawRRect(mouth, _white);
    canvas.drawRRect(
      mouth,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = JackDesign.brown,
    );
    final tooth = _stroke(JackDesign.brown, 2);
    canvas.drawLine(const Offset(50, 80), const Offset(50, 88), tooth);
    canvas.drawLine(const Offset(58, 80), const Offset(58, 88), tooth);
    canvas.drawLine(const Offset(66, 80), const Offset(66, 88), tooth);
  }

  void _drawDead(Canvas canvas) {
    final s = _stroke(JackDesign.brown, 4);
    // Left X
    canvas.drawLine(const Offset(40, 56), const Offset(52, 68), s);
    canvas.drawLine(const Offset(52, 56), const Offset(40, 68), s);
    // Right X
    canvas.drawLine(const Offset(68, 56), const Offset(80, 68), s);
    canvas.drawLine(const Offset(80, 56), const Offset(68, 68), s);
    // Frown
    final path = Path()
      ..moveTo(45, 84)
      ..quadraticBezierTo(60, 76, 75, 84);
    canvas.drawPath(path, s..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(_MascotPainter old) =>
      old.face != face ||
      old.glow != glow ||
      old.bodyColor != bodyColor ||
      old.winkProgress != winkProgress ||
      old.winkLeftEye != winkLeftEye;
}
