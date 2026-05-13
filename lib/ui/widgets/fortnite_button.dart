import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/jack_design.dart';
import 'jack_ico.dart';

/// Style of the [FortniteButton]. Mirrors the four `.fbtn.*` variants from
/// the design handoff CSS.
enum FortniteButtonStyle { primary, epic, cyan, danger, green, secondary }

/// Chunky 3D action button: vertical gradient body, glossy top bevel, dark
/// underside, multi-layer drop shadow with a hard "0 6px 0 #base" stair-step
/// that gives it a stacked / lifted feel. Ports `.fbtn` from styles.css.
class FortniteButton extends StatefulWidget {
  const FortniteButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.style = FortniteButtonStyle.primary,
    this.icon,
    this.icoName,
    this.height = 64,
    this.fontSize = 18,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onPressed;
  final FortniteButtonStyle style;
  // Either an old-style Material icon (legacy callers) OR a JackIco name.
  final IconData? icon;
  final IcoName? icoName;
  final double height;
  final double fontSize;
  /// When false, the button renders dimmed and ignores taps. Used when an
  /// action becomes unavailable (e.g. canceling matchmaking once the
  /// countdown crosses the point-of-no-return).
  final bool enabled;

  @override
  State<FortniteButton> createState() => _FortniteButtonState();
}

class _FortniteButtonState extends State<FortniteButton>
    with SingleTickerProviderStateMixin {
  bool _pressed = false;
  // On-tap sparkle burst — short-lived particles emitted from the tap
  // location. The Ticker only runs while particles are alive.
  final List<_BtnParticle> _sparkles = [];
  final Random _rng = Random();
  Ticker? _ticker;
  Duration _lastTick = Duration.zero;
  // Wall-clock anchor so we can detect long pauses (e.g. the route was
  // pushed offstage and the Ticker got muted). Without this, particles
  // freeze mid-animation and pop back when the user returns to the
  // screen, leaving a "trace" at the click position.
  DateTime _lastWall = DateTime.now();

  void _ensureTicker() {
    _ticker ??= createTicker(_onTick);
    if (!_ticker!.isActive) _ticker!.start();
  }

  void _onTick(Duration elapsed) {
    final now = DateTime.now();
    final wallDt = now.difference(_lastWall).inMicroseconds / 1e6;
    _lastWall = now;
    if (wallDt > 0.5) {
      // We were offstage / muted — flush stale particles instead of
      // continuing the animation where it left off.
      _sparkles.clear();
      _ticker?.stop();
      _lastTick = Duration.zero;
      if (mounted) setState(() {});
      return;
    }
    if (_lastTick == Duration.zero) {
      _lastTick = elapsed;
      return;
    }
    final dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (_sparkles.isEmpty) {
      _ticker?.stop();
      _lastTick = Duration.zero;
      return;
    }
    for (final p in _sparkles) {
      p.life -= dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.vy += 320 * dt;
      p.vx *= 0.96;
    }
    _sparkles.removeWhere((p) => p.life <= 0);
    if (mounted) setState(() {});
  }

  void _spawnBurstAt(Offset position) {
    const count = 12;
    for (var i = 0; i < count; i++) {
      final angle = (i / count) * 2 * pi + _rng.nextDouble() * 0.4;
      final speed = 120 + _rng.nextDouble() * 180;
      final isPurple = i.isEven;
      _sparkles.add(_BtnParticle(
        x: position.dx,
        y: position.dy,
        vx: cos(angle) * speed,
        vy: sin(angle) * speed - 60,
        radius: 2.4 + _rng.nextDouble() * 2.6,
        life: 0.45 + _rng.nextDouble() * 0.25,
        maxLife: 0.70,
        color: isPurple ? JackDesign.purpleHi : JackDesign.yellow,
      ));
    }
    _ensureTicker();
    _lastTick = Duration.zero;
    _lastWall = DateTime.now();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  _Variant get _variant {
    switch (widget.style) {
      case FortniteButtonStyle.primary:
        return _Variant(
          gradient: JackDesign.btnPrimary,
          base: JackDesign.brown,
          border: JackDesign.brown,
          textColor: JackDesign.brownInk,
          textShadowColor: Colors.white.withValues(alpha: 0.40),
          glow: JackDesign.yellow.withValues(alpha: 0.25),
        );
      case FortniteButtonStyle.epic:
        return _Variant(
          gradient: JackDesign.btnEpic,
          base: const Color(0xFF3A0A5A),
          border: JackDesign.purpleInk,
          textColor: Colors.white,
          textShadowColor: Colors.black.withValues(alpha: 0.45),
          glow: JackDesign.purple.withValues(alpha: 0.35),
        );
      case FortniteButtonStyle.cyan:
        return _Variant(
          gradient: JackDesign.btnCyan,
          base: const Color(0xFF1C4A8A),
          border: const Color(0xFF1C4A8A),
          textColor: JackDesign.cyanInk,
          textShadowColor: Colors.white.withValues(alpha: 0.30),
          glow: JackDesign.cyan.withValues(alpha: 0.25),
        );
      case FortniteButtonStyle.danger:
        return _Variant(
          gradient: JackDesign.btnDanger,
          base: const Color(0xFF7A1614),
          border: const Color(0xFF6E1212),
          textColor: Colors.white,
          textShadowColor: Colors.black.withValues(alpha: 0.45),
          glow: JackDesign.red.withValues(alpha: 0.25),
        );
      case FortniteButtonStyle.green:
        return _Variant(
          gradient: JackDesign.btnGreen,
          base: JackDesign.greenDk,
          border: JackDesign.greenDk,
          textColor: JackDesign.greenInk,
          textShadowColor: Colors.white.withValues(alpha: 0.40),
          glow: JackDesign.green.withValues(alpha: 0.30),
        );
      // Legacy alias — old code passes "secondary"; treat it as cyan.
      case FortniteButtonStyle.secondary:
        return _Variant(
          gradient: JackDesign.btnCyan,
          base: const Color(0xFF1C4A8A),
          border: const Color(0xFF1C4A8A),
          textColor: JackDesign.cyanInk,
          textShadowColor: Colors.white.withValues(alpha: 0.30),
          glow: JackDesign.cyan.withValues(alpha: 0.25),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = _variant;
    final pressOffset = _pressed ? 4.0 : 0.0;
    final baseOffset = _pressed ? 2.0 : 6.0;

    final enabled = widget.enabled;
    return MouseRegion(
      cursor:
          enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
      child: IgnorePointer(
        ignoring: !enabled,
        child: Opacity(
          opacity: enabled ? 1.0 : 0.45,
          child: GestureDetector(
        onTapDown: (details) {
          setState(() => _pressed = true);
          _spawnBurstAt(details.localPosition);
        },
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onPressed,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        transform: Matrix4.identity()..translateByDouble(0.0, pressOffset, 0.0, 1.0),
        height: widget.height,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: v.gradient,
          border: Border.all(color: v.border, width: 2),
          boxShadow: [
            // The hard "stair-step" base — `0 6px 0 #base` in CSS.
            BoxShadow(
              color: v.base,
              offset: Offset(0, baseOffset),
              blurRadius: 0,
            ),
            // Soft colored glow.
            BoxShadow(
              color: v.glow,
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Glossy top bevel (::before).
            Align(
              alignment: Alignment.topCenter,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
                child: Container(
                  margin: const EdgeInsets.fromLTRB(2, 2, 2, 0),
                  height: widget.height * 0.50,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: 0.35),
                        Colors.white.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Dark underside (::after).
            Align(
              alignment: Alignment.bottomCenter,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(16),
                ),
                child: Container(
                  margin: const EdgeInsets.fromLTRB(2, 0, 2, 2),
                  height: widget.height * 0.35,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.0),
                        Colors.black.withValues(alpha: 0.22),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Content row.
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.icoName != null) ...[
                    JackIco(
                      name: widget.icoName!,
                      size: widget.fontSize + 4,
                      color: v.textColor,
                    ),
                    const SizedBox(width: 12),
                  ] else if (widget.icon != null) ...[
                    Icon(
                      widget.icon,
                      color: v.textColor,
                      size: widget.fontSize + 6,
                      shadows: [
                        Shadow(
                          color: v.textShadowColor,
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    const SizedBox(width: 10),
                  ],
                  // FittedBox.scaleDown instead of an ellipsis: with the
                  // Bungee font + letterSpacing 2.0 a label like "BATTLE
                  // ROYALE" overflows the right Expanded column on the
                  // home screen at fontSize 14, and used to render as
                  // "BATTLE ROY…". Scaling down preserves the whole word
                  // — it just shrinks a touch when needed — which keeps
                  // the home CTA pair readable in every language and
                  // every screen width without us having to tune each
                  // label's font size by hand.
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.center,
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        softWrap: false,
                        style: JackDesign.bungee(
                          fontSize: widget.fontSize,
                          color: v.textColor,
                          letterSpacing: 2.0,
                          shadows: [
                            Shadow(
                              color: v.textShadowColor,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        ),
            // Click sparkle overlay — only paints while particles are alive.
            if (_sparkles.isNotEmpty)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _BtnSparklesPainter(_sparkles),
                  ),
                ),
              ),
          ],
        ),
      ),
        ),
      ),
    );
  }
}

class _BtnParticle {
  _BtnParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.radius,
    required this.life,
    required this.maxLife,
    required this.color,
  });
  double x, y, vx, vy, radius, life;
  final double maxLife;
  final Color color;
}

class _BtnSparklesPainter extends CustomPainter {
  _BtnSparklesPainter(this.particles);
  final List<_BtnParticle> particles;

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final t = (p.life / p.maxLife).clamp(0.0, 1.0);
      final r = p.radius * (0.6 + 0.4 * t);
      canvas.drawCircle(
        Offset(p.x, p.y),
        r * 2.0,
        Paint()
          ..color = p.color.withValues(alpha: 0.45 * t)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      canvas.drawCircle(
        Offset(p.x, p.y),
        r,
        Paint()..color = p.color.withValues(alpha: 0.95 * t),
      );
      canvas.drawCircle(
        Offset(p.x, p.y),
        r * 0.45,
        Paint()..color = Colors.white.withValues(alpha: t),
      );
    }
  }

  @override
  bool shouldRepaint(_BtnSparklesPainter old) => true;
}

class _Variant {
  const _Variant({
    required this.gradient,
    required this.base,
    required this.border,
    required this.textColor,
    required this.textShadowColor,
    required this.glow,
  });
  final LinearGradient gradient;
  final Color base;
  final Color border;
  final Color textColor;
  final Color textShadowColor;
  final Color glow;
}
