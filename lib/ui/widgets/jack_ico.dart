import 'package:flutter/material.dart';

/// Vector icons matching the SVG `<Ico/>` set in the design handoff.
/// Each icon is authored on a 24×24 viewBox; we scale to [size].
enum IcoName {
  trophy,
  flame,
  gear,
  play,
  home,
  replay,
  close,
  arrowLeft,
  eye,
  check,
  music,
  sfx,
  cap,
  globe,
  finger,
  volumeOn,
  volumeOff,
}

class JackIco extends StatelessWidget {
  const JackIco({
    super.key,
    required this.name,
    this.size = 18,
    this.color = Colors.white,
  });

  final IcoName name;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _IcoPainter(name: name, color: color)),
    );
  }
}

class _IcoPainter extends CustomPainter {
  _IcoPainter({required this.name, required this.color});
  final IcoName name;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    canvas.save();
    canvas.scale(s, s);

    final fill = Paint()..color = color;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (name) {
      case IcoName.trophy:
        _trophy(canvas, fill, stroke);
      case IcoName.flame:
        _flame(canvas, fill);
      case IcoName.gear:
        _gear(canvas, stroke);
      case IcoName.play:
        _play(canvas, fill);
      case IcoName.home:
        _home(canvas, fill);
      case IcoName.replay:
        _replay(canvas, stroke);
      case IcoName.close:
        _close(canvas, stroke);
      case IcoName.arrowLeft:
        _arrowLeft(canvas, stroke);
      case IcoName.eye:
        _eye(canvas, stroke);
      case IcoName.check:
        _check(canvas, stroke);
      case IcoName.music:
        _music(canvas, fill, stroke);
      case IcoName.sfx:
        _sfx(canvas, stroke);
      case IcoName.cap:
        _cap(canvas, fill, stroke);
      case IcoName.globe:
        _globe(canvas, stroke);
      case IcoName.finger:
        _finger(canvas, stroke);
      case IcoName.volumeOn:
        _volumeOn(canvas, fill, stroke);
      case IcoName.volumeOff:
        _volumeOff(canvas, fill, stroke);
    }
    canvas.restore();
  }

  void _volumeOn(Canvas c, Paint fill, Paint stroke) {
    final speaker = Path()
      ..moveTo(4, 9)
      ..lineTo(9, 9)
      ..lineTo(14, 5)
      ..lineTo(14, 19)
      ..lineTo(9, 15)
      ..lineTo(4, 15)
      ..close();
    c.drawPath(speaker, fill);
    final wave1 = Path()
      ..moveTo(17, 9)
      ..arcToPoint(const Offset(17, 15), radius: const Radius.circular(3));
    final wave2 = Path()
      ..moveTo(20, 6)
      ..arcToPoint(const Offset(20, 18), radius: const Radius.circular(6));
    c.drawPath(wave1, stroke);
    c.drawPath(wave2, stroke);
  }

  void _volumeOff(Canvas c, Paint fill, Paint stroke) {
    final speaker = Path()
      ..moveTo(4, 9)
      ..lineTo(9, 9)
      ..lineTo(14, 5)
      ..lineTo(14, 19)
      ..lineTo(9, 15)
      ..lineTo(4, 15)
      ..close();
    c.drawPath(speaker, fill);
    c.drawLine(const Offset(17, 9), const Offset(22, 14), stroke);
    c.drawLine(const Offset(22, 9), const Offset(17, 14), stroke);
  }

  void _trophy(Canvas c, Paint fill, Paint stroke) {
    final cup = Path()
      ..moveTo(6, 4)
      ..lineTo(18, 4)
      ..lineTo(18, 8)
      ..arcToPoint(const Offset(6, 8), radius: const Radius.circular(6))
      ..close();
    c.drawPath(cup, fill);
    final arms = Path()
      ..moveTo(3, 5)
      ..lineTo(6, 5)
      ..lineTo(6, 7)
      ..arcToPoint(
        const Offset(9, 10),
        radius: const Radius.circular(3),
        clockwise: false,
      )
      ..moveTo(21, 5)
      ..lineTo(18, 5)
      ..lineTo(18, 7)
      ..arcToPoint(
        const Offset(15, 10),
        radius: const Radius.circular(3),
      );
    c.drawPath(arms, stroke);
    c.drawRect(const Rect.fromLTWH(10, 14, 4, 4), fill);
    c.drawLine(const Offset(8, 20), const Offset(16, 20), stroke);
  }

  void _flame(Canvas c, Paint fill) {
    final p = Path()
      ..moveTo(12, 3)
      ..cubicTo(13, 7, 17, 8, 17, 13)
      ..arcToPoint(const Offset(7, 13), radius: const Radius.circular(5))
      ..cubicTo(7, 11, 8, 10, 9, 9)
      ..cubicTo(9, 11, 10, 12, 11, 12)
      ..cubicTo(10, 9, 11, 6, 12, 3)
      ..close();
    c.drawPath(p, fill);
  }

  void _gear(Canvas c, Paint stroke) {
    c.drawCircle(const Offset(12, 12), 3, stroke);
    final spokes = [
      [12.0, 2.0, 12.0, 5.0],
      [12.0, 19.0, 12.0, 22.0],
      [4.2, 4.2, 6.3, 6.3],
      [17.7, 17.7, 19.8, 19.8],
      [2.0, 12.0, 5.0, 12.0],
      [19.0, 12.0, 22.0, 12.0],
      [4.2, 19.8, 6.3, 17.7],
      [17.7, 6.3, 19.8, 4.2],
    ];
    for (final s in spokes) {
      c.drawLine(Offset(s[0], s[1]), Offset(s[2], s[3]), stroke);
    }
  }

  void _play(Canvas c, Paint fill) {
    final p = Path()
      ..moveTo(7, 4)
      ..lineTo(20, 12)
      ..lineTo(7, 20)
      ..close();
    c.drawPath(p, fill);
  }

  void _home(Canvas c, Paint fill) {
    final p = Path()
      ..moveTo(3, 11)
      ..lineTo(12, 3)
      ..lineTo(21, 11)
      ..lineTo(21, 20)
      ..arcToPoint(const Offset(20, 21), radius: const Radius.circular(1))
      ..lineTo(15, 21)
      ..lineTo(15, 14)
      ..lineTo(9, 14)
      ..lineTo(9, 21)
      ..lineTo(4, 21)
      ..arcToPoint(const Offset(3, 20), radius: const Radius.circular(1))
      ..close();
    c.drawPath(p, fill);
  }

  void _replay(Canvas c, Paint stroke) {
    final arc = Path()
      ..addArc(
        Rect.fromCircle(center: const Offset(12, 12), radius: 9),
        -1.4,
        4.7,
      );
    c.drawPath(arc, stroke);
    c.drawLine(const Offset(3, 6), const Offset(3, 12), stroke);
    c.drawLine(const Offset(3, 12), const Offset(9, 12), stroke);
  }

  void _close(Canvas c, Paint stroke) {
    c.drawLine(const Offset(5, 5), const Offset(19, 19), stroke);
    c.drawLine(const Offset(19, 5), const Offset(5, 19), stroke);
  }

  void _arrowLeft(Canvas c, Paint stroke) {
    c.drawLine(const Offset(14, 6), const Offset(8, 12), stroke);
    c.drawLine(const Offset(8, 12), const Offset(14, 18), stroke);
  }

  void _eye(Canvas c, Paint stroke) {
    final path = Path()
      ..moveTo(2, 12)
      ..cubicTo(2, 12, 6, 5, 12, 5)
      ..cubicTo(18, 5, 22, 12, 22, 12)
      ..cubicTo(22, 12, 18, 19, 12, 19)
      ..cubicTo(6, 19, 2, 12, 2, 12)
      ..close();
    c.drawPath(path, stroke);
    c.drawCircle(const Offset(12, 12), 3, stroke);
  }

  void _check(Canvas c, Paint stroke) {
    c.drawLine(const Offset(5, 13), const Offset(9, 17), stroke);
    c.drawLine(const Offset(9, 17), const Offset(19, 7), stroke);
  }

  void _music(Canvas c, Paint fill, Paint stroke) {
    final stem = Path()
      ..moveTo(9, 18)
      ..lineTo(9, 5)
      ..lineTo(21, 3)
      ..lineTo(21, 16);
    c.drawPath(stem, stroke);
    c.drawCircle(const Offset(6, 18), 3, fill);
    c.drawCircle(const Offset(18, 16), 3, fill);
  }

  void _sfx(Canvas c, Paint stroke) {
    c.drawLine(const Offset(3, 12), const Offset(5, 12), stroke);
    c.drawLine(const Offset(7, 8), const Offset(7, 16), stroke);
    c.drawLine(const Offset(11, 5), const Offset(11, 19), stroke);
    c.drawLine(const Offset(15, 8), const Offset(15, 16), stroke);
    c.drawLine(const Offset(19, 11), const Offset(19, 13), stroke);
  }

  void _cap(Canvas c, Paint fill, Paint stroke) {
    final brim = Path()
      ..moveTo(2, 9)
      ..lineTo(12, 5)
      ..lineTo(22, 9)
      ..lineTo(12, 13)
      ..close();
    c.drawPath(brim, fill);
    final crown = Path()
      ..moveTo(6, 11)
      ..lineTo(6, 16)
      ..arcToPoint(const Offset(18, 16), radius: const Radius.circular(6))
      ..lineTo(18, 11);
    c.drawPath(crown, stroke);
  }

  void _globe(Canvas c, Paint stroke) {
    c.drawCircle(const Offset(12, 12), 9, stroke);
    c.drawLine(const Offset(3, 12), const Offset(21, 12), stroke);
    final v1 = Path()
      ..moveTo(12, 3)
      ..arcToPoint(const Offset(12, 21), radius: const Radius.circular(8))
      ..arcToPoint(
        const Offset(12, 3),
        radius: const Radius.circular(8),
      );
    c.drawPath(v1, stroke);
  }

  void _finger(Canvas c, Paint stroke) {
    final p = Path()
      ..moveTo(9, 11)
      ..lineTo(9, 5)
      ..arcToPoint(const Offset(13, 5), radius: const Radius.circular(2))
      ..lineTo(13, 12)
      ..lineTo(16, 10)
      ..arcToPoint(const Offset(19, 11.7), radius: const Radius.circular(2))
      ..lineTo(19, 15)
      ..arcToPoint(const Offset(13, 21), radius: const Radius.circular(6))
      ..lineTo(11, 21)
      ..arcToPoint(const Offset(7, 18), radius: const Radius.circular(4))
      ..lineTo(5, 13)
      ..arcToPoint(const Offset(7.6, 11.6), radius: const Radius.circular(1.5))
      ..lineTo(9, 13);
    c.drawPath(
      p,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.10)
        ..style = PaintingStyle.fill,
    );
    c.drawPath(p, stroke..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_IcoPainter old) =>
      old.name != name || old.color != color;
}
