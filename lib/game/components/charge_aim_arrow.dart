import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../../state/game_state.dart';
import 'player.dart';

/// A small directional arrow rising from the top of the player while charging.
/// Length scales with charge progress, color brightens at full charge — gives
/// the player an instinctive read of where the jump will go without relying
/// on the trajectory dots.
class ChargeAimArrow extends Component {
  ChargeAimArrow({required this.player, required this.gameState})
      : super(priority: 23);

  final Player player;
  final GameState gameState;

  static const Color _color = Color(0xFFFFEB3B);
  static const Color _coreColor = Color(0xFFFFFDE0);

  @override
  void render(Canvas canvas) {
    if (!gameState.charging) return;
    final dir = player.aimDirection;
    if (dir == null) return;
    if (!dir.x.isFinite || !dir.y.isFinite) return;
    final mag = sqrt(dir.x * dir.x + dir.y * dir.y);
    if (mag < 1e-3) return;

    final progress = gameState.chargeProgress.clamp(0.0, 1.0);

    // Origin: just above the player's head.
    final originX = player.position.x;
    final originY = player.position.y - player.size.y - 6;

    // Length scales with charge.
    final length = player.size.x * (0.35 + progress * 1.4);

    final ndx = dir.x / mag;
    final ndy = dir.y / mag;
    final endX = originX + ndx * length;
    final endY = originY + ndy * length;

    final color = Color.lerp(_color, _coreColor, progress * 0.5)!;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(Offset(originX, originY), Offset(endX, endY), paint);

    // Arrowhead: a small triangle at the end pointing in the aim direction.
    final headLen = 7.0 + progress * 3;
    final perpX = -ndy;
    final perpY = ndx;
    final baseX = endX - ndx * headLen;
    final baseY = endY - ndy * headLen;
    final leftX = baseX + perpX * headLen * 0.55;
    final leftY = baseY + perpY * headLen * 0.55;
    final rightX = baseX - perpX * headLen * 0.55;
    final rightY = baseY - perpY * headLen * 0.55;

    final headPaint = Paint()..color = color;
    final path = Path()
      ..moveTo(endX, endY)
      ..lineTo(leftX, leftY)
      ..lineTo(rightX, rightY)
      ..close();
    canvas.drawPath(path, headPaint);
  }
}
