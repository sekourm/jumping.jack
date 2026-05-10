import 'package:flutter/material.dart';

enum GemKind { star, crystal, heart, vision, teleport }

class GemPalette {
  const GemPalette(this.light, this.dark, this.halo);
  final Color light;
  final Color dark;
  final Color halo;
}

/// Per-kind palette matching the design handoff (`components.jsx`).
const Map<GemKind, GemPalette> kGemPalettes = <GemKind, GemPalette>{
  GemKind.star: GemPalette(
    Color(0xFFFFE198),
    Color(0xFFC8861A),
    Color(0xFFFFFFFF),
  ),
  GemKind.crystal: GemPalette(
    Color(0xFF7CC0FF),
    Color(0xFF1C4A8A),
    Color(0xFF7CC0FF),
  ),
  GemKind.heart: GemPalette(
    Color(0xFFFF8AC7),
    Color(0xFF7A1F55),
    Color(0xFFFF8AC7),
  ),
  GemKind.vision: GemPalette(
    Color(0xFF7AE091),
    Color(0xFF1F6E2E),
    Color(0xFF7AE091),
  ),
  GemKind.teleport: GemPalette(
    Color(0xFFD896FF),
    Color(0xFF5C1A8A),
    Color(0xFFD896FF),
  ),
};

/// Vector pickup gem — port of the SVG Gem component. Linear gradient body,
/// 2px black outline, white shine ellipse.
class JackGem extends StatelessWidget {
  const JackGem({super.key, required this.kind, this.size = 36});
  final GemKind kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _GemPainter(kind: kind)),
    );
  }
}

class _GemPainter extends CustomPainter {
  _GemPainter({required this.kind});
  final GemKind kind;

  @override
  void paint(Canvas canvas, Size size) {
    paintJackGem(canvas, size, kind, drawHalo: true);
  }

  @override
  bool shouldRepaint(_GemPainter old) => old.kind != kind;
}

/// Paints a [GemKind] onto [canvas] inside a square area of [size].
/// Matches the SVG Gem component from the design handoff.
///
/// [drawHalo] adds a soft coloured glow behind the gem; [pulseScale] applies
/// a uniform scale around the gem center (used by the in-game pickups for
/// a subtle bob).
void paintJackGem(
  Canvas canvas,
  Size size,
  GemKind kind, {
  bool drawHalo = true,
  double pulseScale = 1.0,
  double outlineWidth = 2.0,
}) {
  final s = size.width / 48;
  canvas.save();
  canvas.scale(s, s);
  if (pulseScale != 1.0) {
    canvas.translate(24, 24);
    canvas.scale(pulseScale);
    canvas.translate(-24, -24);
  }

  final p = kGemPalettes[kind]!;

  if (drawHalo) {
    canvas.drawCircle(
      const Offset(24, 24),
      26,
      Paint()
        ..color = p.halo.withValues(alpha: 0.50)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
  }

  final shader = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Colors.white.withValues(alpha: 0.90),
      p.light,
      p.dark,
    ],
    stops: const [0.0, 0.40, 1.0],
  ).createShader(const Rect.fromLTWH(0, 0, 48, 48));

  final fill = Paint()..shader = shader;
  final stroke = Paint()
    ..color = const Color(0xFF1A1A1A)
    ..style = PaintingStyle.stroke
    ..strokeWidth = outlineWidth
    ..strokeJoin = StrokeJoin.round;

  Path? path;
  switch (kind) {
    case GemKind.star:
      path = Path()
        ..moveTo(24, 4)
        ..lineTo(29, 18)
        ..lineTo(44, 19)
        ..lineTo(32, 28)
        ..lineTo(36, 42)
        ..lineTo(24, 33)
        ..lineTo(12, 42)
        ..lineTo(16, 28)
        ..lineTo(4, 19)
        ..lineTo(19, 18)
        ..close();
    case GemKind.crystal:
      path = Path()
        ..moveTo(24, 4)
        ..lineTo(40, 20)
        ..lineTo(24, 44)
        ..lineTo(8, 20)
        ..close();
    case GemKind.heart:
      path = Path()
        ..moveTo(24, 42)
        ..cubicTo(4, 28, 4, 12, 16, 12)
        ..cubicTo(20, 12, 24, 16, 24, 20)
        ..cubicTo(24, 16, 28, 12, 32, 12)
        ..cubicTo(44, 12, 44, 28, 24, 42)
        ..close();
    case GemKind.vision:
      canvas.drawOval(const Rect.fromLTWH(6, 12, 36, 24), fill);
      canvas.drawOval(const Rect.fromLTWH(6, 12, 36, 24), stroke);
      canvas.drawCircle(
        const Offset(24, 24),
        6,
        Paint()..color = const Color(0xFF1A1A1A),
      );
      canvas.drawCircle(
        const Offset(22, 22),
        2,
        Paint()..color = Colors.white,
      );
      path = null;
    case GemKind.teleport:
      canvas.drawCircle(const Offset(24, 24), 18, fill);
      canvas.drawCircle(const Offset(24, 24), 18, stroke);
      canvas.drawCircle(
        const Offset(24, 24),
        11,
        Paint()
          ..color = const Color(0xFF1A1A1A)
          ..style = PaintingStyle.stroke
          ..strokeWidth = outlineWidth,
      );
      canvas.drawCircle(
        const Offset(24, 24),
        5,
        Paint()..color = const Color(0xFF1A1A1A),
      );
      path = null;
  }
  if (path != null) {
    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);
  }

  canvas.drawOval(
    const Rect.fromLTWH(14, 11.5, 8, 5),
    Paint()..color = Colors.white.withValues(alpha: 0.70),
  );

  canvas.restore();
}
