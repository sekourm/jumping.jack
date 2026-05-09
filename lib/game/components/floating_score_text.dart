import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../config.dart';

/// A label that pops up at a world position and floats upward while fading.
/// Used for "+N" score popups (yellow, default color) and for pickup-effect
/// labels like "SLOW MOTION" (cyan), "COMBO SAFE" (pink), "WARP" (purple).
class FloatingScoreText extends Component {
  FloatingScoreText({
    required Vector2 origin,
    int? value,
    String? label,
    Color color = GameConfig.playerColor,
    double fontSize = 22,
    double life = 1.1,
    double floatHeight = 60,
  })  : assert(value != null || label != null,
            'Either value or label must be provided'),
        _origin = origin.clone(),
        _label = label ?? '+${value!}',
        _color = color,
        _fontSize = fontSize,
        _life = life,
        _floatHeight = floatHeight,
        super(priority: 30);

  final Vector2 _origin;
  final String _label;
  final Color _color;
  final double _fontSize;
  final double _life;
  final double _floatHeight;

  double _elapsed = 0;

  @override
  void update(double dt) {
    _elapsed += dt;
    if (_elapsed >= _life) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final t = (_elapsed / _life).clamp(0.0, 1.0);

    // Pop scale: overshoot then settle.
    final double scale;
    if (t < 0.12) {
      scale = 1 + (0.45 * (t / 0.12));
    } else if (t < 0.25) {
      scale = 1.45 - 0.45 * ((t - 0.12) / 0.13);
    } else {
      scale = 1.0;
    }

    // Hold opacity until 65%, then fade.
    final alpha = t < 0.65 ? 1.0 : (1 - (t - 0.65) / 0.35).clamp(0.0, 1.0);

    // Float upward + ease-out.
    final ease = 1 - (1 - t) * (1 - t);
    final dy = -_floatHeight * ease;

    final tp = TextPainter(
      text: TextSpan(
        text: _label,
        style: TextStyle(
          color: _color.withValues(alpha: alpha),
          fontSize: _fontSize,
          fontWeight: FontWeight.w900,
          letterSpacing: 2,
          fontFeatures: const [FontFeature.tabularFigures()],
          shadows: [
            Shadow(
              color: Colors.black.withValues(alpha: 0.6 * alpha),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    canvas.save();
    canvas.translate(_origin.x, _origin.y + dy);
    canvas.scale(scale);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height));
    canvas.restore();
  }
}
