import 'package:flutter/material.dart';

import '../../game/config.dart';

/// Fortnite-style action button: vertical gradient body, bright top bevel,
/// dark outline, glossy inner border, drop shadow, and a 2px press-down
/// animation. The label is bold caps with a subtle shadow.
enum FortniteButtonStyle { primary, secondary, epic }

class FortniteButton extends StatefulWidget {
  const FortniteButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.style = FortniteButtonStyle.primary,
    this.icon,
    this.height = 58,
    this.fontSize = 18,
  });

  final String label;
  final VoidCallback onPressed;
  final FortniteButtonStyle style;
  final IconData? icon;
  final double height;
  final double fontSize;

  @override
  State<FortniteButton> createState() => _FortniteButtonState();
}

class _FortniteButtonState extends State<FortniteButton> {
  bool _pressed = false;

  Color get _accent {
    switch (widget.style) {
      case FortniteButtonStyle.primary:
        return GameConfig.playerColor;
      case FortniteButtonStyle.secondary:
        return const Color(0xFF3FA0E5);
      case FortniteButtonStyle.epic:
        return const Color(0xFFB14BFF);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accent;
    final lightTop = Color.lerp(accent, Colors.white, 0.42)!;
    final darkBottom = Color.lerp(accent, Colors.black, 0.55)!;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        transform: Matrix4.identity()
          ..translateByDouble(0.0, _pressed ? 3.0 : 0.0, 0.0, 1.0),
        height: widget.height,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [lightTop, accent, darkBottom],
            stops: const [0.0, 0.50, 1.0],
          ),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: _pressed ? 0.20 : 0.50),
              blurRadius: _pressed ? 12 : 24,
              offset: Offset(0, _pressed ? 2 : 6),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.40),
              blurRadius: 6,
              offset: Offset(0, _pressed ? 1 : 4),
            ),
          ],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Top glossy bevel.
            Align(
              alignment: Alignment.topCenter,
              child: Container(
                margin: const EdgeInsets.fromLTRB(2, 2, 2, 0),
                height: widget.height * 0.42,
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12),
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.50),
                      Colors.white.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
            // Outer dark stroke.
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.black.withValues(alpha: 0.45),
                  width: 1.6,
                ),
              ),
            ),
            // Inner light stroke.
            Padding(
              padding: const EdgeInsets.all(1.8),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.45),
                    width: 1.0,
                  ),
                ),
              ),
            ),
            // Content.
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.icon != null) ...[
                    Icon(
                      widget.icon,
                      color: Colors.white,
                      size: widget.fontSize + 10,
                      shadows: const [
                        Shadow(
                          color: Colors.black54,
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    widget.label,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: widget.fontSize,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 5,
                      shadows: const [
                        Shadow(
                          color: Colors.black87,
                          blurRadius: 5,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
