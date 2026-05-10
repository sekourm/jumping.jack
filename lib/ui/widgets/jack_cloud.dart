import 'package:flutter/material.dart';

enum CloudKind { standard, moving, bouncy }

/// Vector cloud platform — port of the SVG Cloud component. Used in static
/// UI contexts (tutorial, debug). The actual in-game platforms still use
/// `lib/game/components/platform.dart`.
class JackCloud extends StatelessWidget {
  const JackCloud({
    super.key,
    this.kind = CloudKind.standard,
    this.cracked = false,
    this.width = 120,
  });

  final CloudKind kind;
  final bool cracked;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: width * 0.50,
      child: CustomPaint(
        painter: _CloudPainter(kind: kind, cracked: cracked),
      ),
    );
  }
}

class _CloudPainter extends CustomPainter {
  _CloudPainter({required this.kind, required this.cracked});
  final CloudKind kind;
  final bool cracked;

  @override
  void paint(Canvas canvas, Size size) {
    // Authored on a 120×60 viewBox.
    final sx = size.width / 120;
    final sy = size.height / 60;
    canvas.save();
    canvas.scale(sx, sy);

    Color fill;
    Color shadow;
    Color chevron = const Color(0xFF3D8F4F);
    switch (kind) {
      case CloudKind.standard:
        fill = const Color(0xFFFFFFFF);
        shadow = const Color(0xFFC8CDD6);
      case CloudKind.moving:
        fill = const Color(0xFFFFB890);
        shadow = const Color(0xFFA35C3A);
      case CloudKind.bouncy:
        fill = const Color(0xFFA8EDB6);
        shadow = const Color(0xFF3D8F4F);
    }

    final shadowPaint = Paint()..color = shadow;
    final bodyPaint = Paint()..color = fill;

    // Drop shadow under the cloud.
    canvas.drawOval(
      const Rect.fromLTWH(8, 36, 104, 18),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.30)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    // Lower (shadow) row of puffs.
    canvas.drawOval(const Rect.fromLTWH(2, 14, 40, 36), shadowPaint);
    canvas.drawOval(const Rect.fromLTWH(24, 6, 44, 40), shadowPaint);
    canvas.drawOval(const Rect.fromLTWH(52, 6, 44, 40), shadowPaint);
    canvas.drawOval(const Rect.fromLTWH(78, 14, 40, 36), shadowPaint);

    // Body row of puffs (shifted up).
    canvas.drawOval(const Rect.fromLTWH(4, 12, 36, 32), bodyPaint);
    canvas.drawOval(const Rect.fromLTWH(26, 4, 40, 36), bodyPaint);
    canvas.drawOval(const Rect.fromLTWH(54, 4, 40, 36), bodyPaint);
    canvas.drawOval(const Rect.fromLTWH(80, 12, 36, 32), bodyPaint);

    // Crown highlights (kiss-of-light).
    final highlight = Paint()..color = Colors.white.withValues(alpha: 0.70);
    canvas.drawOval(const Rect.fromLTWH(30, 6, 32, 12), highlight);
    canvas.drawOval(const Rect.fromLTWH(58, 6, 32, 12), highlight);

    // Bouncy chevrons.
    if (kind == CloudKind.bouncy) {
      final p = Paint()
        ..color = chevron
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;
      final c1 = Path()
        ..moveTo(50, 4)
        ..lineTo(56, -2)
        ..lineTo(62, 4);
      final c2 = Path()
        ..moveTo(64, 4)
        ..lineTo(70, -2)
        ..lineTo(76, 4);
      canvas.drawPath(c1, p);
      canvas.drawPath(c2, p);
    }

    if (cracked) {
      final p = Paint()
        ..color = const Color(0xFF1A1A1A).withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round;
      final c1 = Path()
        ..moveTo(40, 18)
        ..lineTo(46, 22)
        ..lineTo(42, 28)
        ..lineTo(50, 30);
      final c2 = Path()
        ..moveTo(70, 16)
        ..lineTo(76, 22)
        ..lineTo(72, 28);
      canvas.drawPath(c1, p);
      canvas.drawPath(c2, p);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_CloudPainter old) =>
      old.kind != kind || old.cracked != cracked;
}
