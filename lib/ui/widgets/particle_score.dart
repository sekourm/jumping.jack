import 'dart:math';

import 'package:flutter/material.dart';

import '../../game/config.dart';

/// A score rendered as a 5x7 dot-matrix per digit, where each "ON" cell pulses
/// subtly. Same visual language as the in-game energy particles, used both
/// for the HUD score and the end-of-run score on the death screen (with a
/// bigger [dotSize]).
class ParticleScore extends StatefulWidget {
  const ParticleScore({
    super.key,
    required this.score,
    this.dotSize = 4.0,
    this.digitGap = 4.0,
    this.captionFontSize = 10.0,
    this.captionLetterSpacing = 5.0,
    this.captionGap = 4.0,
    this.color = GameConfig.playerColor,
  });

  final int score;
  final double dotSize;
  final double digitGap;
  final double captionFontSize;
  final double captionLetterSpacing;
  final double captionGap;
  final Color color;

  double get dotCell => dotSize + 1.0;

  @override
  State<ParticleScore> createState() => _ParticleScoreState();
}

class _ParticleScoreState extends State<ParticleScore>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final digitCount = '${widget.score}'.length;
        final dotCell = widget.dotCell;
        final digitW = 5 * dotCell;
        final scoreW =
            digitCount * digitW + (digitCount - 1) * widget.digitGap;
        final captionH = widget.captionFontSize + 4;
        final dotsH = 7 * dotCell;
        return CustomPaint(
          painter: _ParticleScorePainter(
            score: widget.score,
            phase: _controller.value * 2 * pi,
            dotSize: widget.dotSize,
            dotCell: dotCell,
            digitGap: widget.digitGap,
            captionFontSize: widget.captionFontSize,
            captionLetterSpacing: widget.captionLetterSpacing,
            captionGap: widget.captionGap,
            color: widget.color,
          ),
          size: Size(scoreW + 12, captionH + widget.captionGap + dotsH),
        );
      },
    );
  }
}

/// 5x7 bitmap font for digits 0..9.
const List<List<List<int>>> _digitPatterns = <List<List<int>>>[
  [ // 0
    [0, 1, 1, 1, 0],
    [1, 0, 0, 0, 1],
    [1, 0, 0, 1, 1],
    [1, 0, 1, 0, 1],
    [1, 1, 0, 0, 1],
    [1, 0, 0, 0, 1],
    [0, 1, 1, 1, 0],
  ],
  [ // 1
    [0, 0, 1, 0, 0],
    [0, 1, 1, 0, 0],
    [0, 0, 1, 0, 0],
    [0, 0, 1, 0, 0],
    [0, 0, 1, 0, 0],
    [0, 0, 1, 0, 0],
    [0, 1, 1, 1, 0],
  ],
  [ // 2
    [0, 1, 1, 1, 0],
    [1, 0, 0, 0, 1],
    [0, 0, 0, 0, 1],
    [0, 0, 0, 1, 0],
    [0, 0, 1, 0, 0],
    [0, 1, 0, 0, 0],
    [1, 1, 1, 1, 1],
  ],
  [ // 3
    [1, 1, 1, 1, 1],
    [0, 0, 0, 1, 0],
    [0, 0, 1, 0, 0],
    [0, 0, 0, 1, 0],
    [0, 0, 0, 0, 1],
    [1, 0, 0, 0, 1],
    [0, 1, 1, 1, 0],
  ],
  [ // 4
    [0, 0, 0, 1, 0],
    [0, 0, 1, 1, 0],
    [0, 1, 0, 1, 0],
    [1, 0, 0, 1, 0],
    [1, 1, 1, 1, 1],
    [0, 0, 0, 1, 0],
    [0, 0, 0, 1, 0],
  ],
  [ // 5
    [1, 1, 1, 1, 1],
    [1, 0, 0, 0, 0],
    [1, 1, 1, 1, 0],
    [0, 0, 0, 0, 1],
    [0, 0, 0, 0, 1],
    [1, 0, 0, 0, 1],
    [0, 1, 1, 1, 0],
  ],
  [ // 6
    [0, 0, 1, 1, 0],
    [0, 1, 0, 0, 0],
    [1, 0, 0, 0, 0],
    [1, 1, 1, 1, 0],
    [1, 0, 0, 0, 1],
    [1, 0, 0, 0, 1],
    [0, 1, 1, 1, 0],
  ],
  [ // 7
    [1, 1, 1, 1, 1],
    [0, 0, 0, 0, 1],
    [0, 0, 0, 1, 0],
    [0, 0, 1, 0, 0],
    [0, 1, 0, 0, 0],
    [0, 1, 0, 0, 0],
    [0, 1, 0, 0, 0],
  ],
  [ // 8
    [0, 1, 1, 1, 0],
    [1, 0, 0, 0, 1],
    [1, 0, 0, 0, 1],
    [0, 1, 1, 1, 0],
    [1, 0, 0, 0, 1],
    [1, 0, 0, 0, 1],
    [0, 1, 1, 1, 0],
  ],
  [ // 9
    [0, 1, 1, 1, 0],
    [1, 0, 0, 0, 1],
    [1, 0, 0, 0, 1],
    [0, 1, 1, 1, 1],
    [0, 0, 0, 0, 1],
    [0, 0, 0, 1, 0],
    [0, 1, 1, 0, 0],
  ],
];

class _ParticleScorePainter extends CustomPainter {
  _ParticleScorePainter({
    required this.score,
    required this.phase,
    required this.dotSize,
    required this.dotCell,
    required this.digitGap,
    required this.captionFontSize,
    required this.captionLetterSpacing,
    required this.captionGap,
    required this.color,
  });

  final int score;
  final double phase;
  final double dotSize;
  final double dotCell;
  final double digitGap;
  final double captionFontSize;
  final double captionLetterSpacing;
  final double captionGap;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Caption "SCORE"
    final captionPainter = TextPainter(
      text: TextSpan(
        text: 'SCORE',
        style: TextStyle(
          color: GameConfig.textMuted,
          fontSize: captionFontSize,
          fontWeight: FontWeight.w800,
          letterSpacing: captionLetterSpacing,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    captionPainter.paint(
      canvas,
      Offset((size.width - captionPainter.width) / 2, 0),
    );

    final scoreStr = '$score';
    final digitW = 5 * dotCell;
    final totalW =
        scoreStr.length * digitW + (scoreStr.length - 1) * digitGap;
    var x = (size.width - totalW) / 2;
    final yBase = captionFontSize + captionGap + 2;

    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, dotSize * 0.9);
    final dotPaint = Paint()..color = color;

    for (var d = 0; d < scoreStr.length; d++) {
      final digit = int.parse(scoreStr[d]);
      final pattern = _digitPatterns[digit];
      for (var row = 0; row < 7; row++) {
        for (var col = 0; col < 5; col++) {
          if (pattern[row][col] == 0) continue;
          final localPhase = phase + (col + row * 1.5) * 0.4;
          final pulse = sin(localPhase) * 0.18 + 0.82;
          final cx = x + col * dotCell + dotSize / 2;
          final cy = yBase + row * dotCell + dotSize / 2;
          final s = dotSize * pulse;
          canvas.drawRect(
            Rect.fromCenter(
              center: Offset(cx, cy),
              width: s + dotSize * 0.6,
              height: s + dotSize * 0.6,
            ),
            glowPaint,
          );
          canvas.drawRect(
            Rect.fromCenter(center: Offset(cx, cy), width: s, height: s),
            dotPaint,
          );
        }
      }
      x += digitW + digitGap;
    }
  }

  @override
  bool shouldRepaint(_ParticleScorePainter old) =>
      old.score != score || old.phase != phase;
}
