import 'package:flutter/material.dart';

import '../theme/jack_design.dart';

enum MascotFace { smile, excited, determined, charge, dead }

/// Vector mascot cube — Flutter port of the Mascot SVG component from the
/// design handoff. 5 face variants, optional glow. The body defaults to
/// the JJ yellow but can be tinted (used by the BR result screen so the
/// winner's mascot reflects their slot colour).
class JackMascot extends StatelessWidget {
  const JackMascot({
    super.key,
    this.size = 80,
    this.face = MascotFace.smile,
    this.glow = true,
    this.bodyColor,
  });

  final double size;
  final MascotFace face;
  final bool glow;
  final Color? bodyColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _MascotPainter(
          face: face,
          glow: glow,
          bodyColor: bodyColor ?? JackDesign.yellow,
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
  });
  final MascotFace face;
  final bool glow;
  final Color bodyColor;

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
    canvas.drawOval(const Rect.fromLTWH(37, 49, 18, 22), _white);
    canvas.drawOval(const Rect.fromLTWH(65, 49, 18, 22), _white);
    canvas.drawCircle(const Offset(48, 62), 4, _ink);
    canvas.drawCircle(const Offset(76, 62), 4, _ink);
    final path = Path()
      ..moveTo(45, 80)
      ..quadraticBezierTo(60, 92, 75, 80);
    canvas.drawPath(path, _stroke(JackDesign.brown, 4));
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
      old.face != face || old.glow != glow || old.bodyColor != bodyColor;
}
