import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../../ui/theme/jack_design.dart';
import '../config.dart';

/// Trajectory preview rendered as a row of static "energy" dots evenly spaced
/// along the projected jump path. Each dot pulses slightly in sync to give
/// life to the line without the directional "stream" effect.
class TrajectoryPreview extends Component {
  TrajectoryPreview() : super(priority: 20);

  Vector2? startPos;
  Vector2 initialVelocity = Vector2.zero();
  bool active = false;
  /// 0 = invisible, 1 = full visible. Driven by score to enforce a skill ramp.
  double visibility = 1.0;

  // Sampling — number of dots and the time step between them. We skip the
  // first [_skipSteps] so dots don't pile on top of the player.
  static const int _dotCount = 14;
  static const int _stepsPerDot = 2;
  static const int _skipSteps = 1;
  static const double _stepDt = 0.035;

  // Palette aligned with the rest of the UI (JackDesign): warm yellow
  // gradient outer / brighter highlight inner — matches the buttons + the
  // tutorial slider dots so the trajectory reads like part of the same
  // family.
  static const Color _haloColor = JackDesign.yellow;       // soft glow
  static const Color _outerColor = JackDesign.yellow;      // dot edge
  static const Color _innerColor = JackDesign.yellowHi;    // dot face
  static const Color _coreColor = Color(0xFFFFF6D6);       // bright core
  static const Color _ringColor = JackDesign.brown;        // hard outline

  double _elapsed = 0;
  bool _wasActive = false;

  @override
  void update(double dt) {
    super.update(dt);
    if (active && !_wasActive) _elapsed = 0;
    _wasActive = active;
    if (active && dt.isFinite && dt > 0) _elapsed += dt;
  }

  @override
  void render(Canvas canvas) {
    if (!active || startPos == null) return;
    if (visibility <= 0) return;
    final start = startPos!;
    if (!start.x.isFinite ||
        !start.y.isFinite ||
        !initialVelocity.x.isFinite ||
        !initialVelocity.y.isFinite ||
        !_elapsed.isFinite) {
      return;
    }
    // Number of visible dots scales with visibility so the trail also
    // shrinks (head is preserved, tail disappears first).
    final visibleDotCount =
        (_dotCount * visibility).round().clamp(0, _dotCount);
    if (visibleDotCount == 0) return;

    final pos = start.clone();
    final vel = initialVelocity.clone();

    // Skip the first few sim steps so the first dot sits visibly off the
    // player's body.
    for (var i = 0; i < _skipSteps; i++) {
      vel.y += GameConfig.gravity * _stepDt;
      pos.x += vel.x * _stepDt;
      pos.y += vel.y * _stepDt;
    }

    for (var i = 0; i < visibleDotCount; i++) {
      for (var s = 0; s < _stepsPerDot; s++) {
        vel.y += GameConfig.gravity * _stepDt;
        pos.x += vel.x * _stepDt;
        pos.y += vel.y * _stepDt;
      }
      if (!pos.x.isFinite || !pos.y.isFinite) continue;

      final t = i / (_dotCount - 1); // 0 at start of trail, 1 at far end
      final pulse = sin(_elapsed * 6 + i * 0.45) * 0.18;
      final baseRadius = 2.7 - t * 1.6;
      final radius = baseRadius + pulse;
      final alpha =
          (((1 - t * 0.65) * 0.92) * visibility).clamp(0.0, 1.0);

      if (!radius.isFinite || !alpha.isFinite || radius <= 0 || alpha <= 0) {
        continue;
      }

      final p = Offset(pos.x, pos.y);
      // Soft yellow halo behind every dot — same vocabulary as the .fbtn
      // glow shadows, just shrunken to the dot's scale.
      canvas.drawCircle(
        p,
        radius * 2.0,
        Paint()
          ..color = _haloColor.withValues(alpha: alpha * 0.22)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
      // Outer dot — warm yellow.
      canvas.drawCircle(
        p,
        radius,
        Paint()..color = _outerColor.withValues(alpha: alpha),
      );
      // Inner highlight ring — brighter yellow, gives the dot its volume.
      canvas.drawCircle(
        p,
        radius * 0.72,
        Paint()..color = _innerColor.withValues(alpha: alpha),
      );
      // Bright core + brown outline only on the first few dots — they sit
      // closest to the player and act as the "head of energy" with the
      // same palette as the fortnite-style buttons.
      if (i < 3) {
        canvas.drawCircle(
          p,
          radius * 0.42,
          Paint()..color = _coreColor.withValues(alpha: alpha),
        );
        canvas.drawCircle(
          p,
          radius,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8
            ..color = _ringColor.withValues(alpha: alpha * 0.85),
        );
      }
    }
  }
}
