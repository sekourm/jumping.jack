import 'package:flutter/material.dart';

import '../theme/jack_design.dart';

/// Big gold "JUMPING JACK" wordmark — Bungee, italic skewX(-6deg),
/// drop-shadow stack mimicking `.logo-jj` in the design CSS.
class JackLogo extends StatelessWidget {
  const JackLogo({
    super.key,
    this.text = 'JUMPING\nJACK',
    this.fontSize = 56,
    this.skew = -0.10,
  });

  final String text;
  final double fontSize;
  final double skew;

  @override
  Widget build(BuildContext context) {
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.skewX(skew),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Hard "0 8px 0 #4a2c00" deep shadow.
          Transform.translate(
            offset: const Offset(0, 8),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: JackDesign.bungee(
                fontSize: fontSize,
                color: JackDesign.brownDk,
                height: 0.95,
                letterSpacing: 1,
              ),
            ),
          ),
          // Mid "0 4px 0 #brown" shadow.
          Transform.translate(
            offset: const Offset(0, 4),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: JackDesign.bungee(
                fontSize: fontSize,
                color: JackDesign.brown,
                height: 0.95,
                letterSpacing: 1,
              ),
            ),
          ),
          // Front face — gold gradient with soft glow.
          ShaderMask(
            shaderCallback: (rect) => JackDesign.logoGold.createShader(rect),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: JackDesign.bungee(
                fontSize: fontSize,
                color: Colors.white,
                height: 0.95,
                letterSpacing: 1,
                shadows: [
                  Shadow(
                    color: JackDesign.yellow.withValues(alpha: 0.45),
                    blurRadius: 22,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "BATTLE ROYALE" purple wordmark — `.logo-br`.
class JackBrLogo extends StatelessWidget {
  const JackBrLogo({super.key, this.text = 'BATTLE ROYALE', this.fontSize = 36});
  final String text;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Transform.translate(
          offset: const Offset(0, 6),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: JackDesign.bungee(
              fontSize: fontSize,
              color: const Color(0xFF160226),
              height: 1,
              letterSpacing: 2,
            ),
          ),
        ),
        Transform.translate(
          offset: const Offset(0, 3),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: JackDesign.bungee(
              fontSize: fontSize,
              color: JackDesign.purpleInk,
              height: 1,
              letterSpacing: 2,
            ),
          ),
        ),
        ShaderMask(
          shaderCallback: (rect) => JackDesign.logoPurple.createShader(rect),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: JackDesign.bungee(
              fontSize: fontSize,
              color: Colors.white,
              height: 1,
              letterSpacing: 2,
              shadows: [
                Shadow(
                  color: JackDesign.purple.withValues(alpha: 0.40),
                  blurRadius: 24,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// End-game wordmark (TERMINÉ / VICTOIRE !) — `.logo-end.gold` or `.purple`.
class JackEndLogo extends StatelessWidget {
  const JackEndLogo({
    super.key,
    required this.text,
    this.gold = true,
    this.fontSize = 56,
  });
  final String text;
  final bool gold;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final accent = gold ? JackDesign.brown : JackDesign.purpleInk;
    final accentDk = gold ? JackDesign.brownDk : const Color(0xFF160226);
    final glow = gold
        ? JackDesign.yellow.withValues(alpha: 0.40)
        : JackDesign.purple.withValues(alpha: 0.40);
    final gradient = gold ? JackDesign.logoGold : JackDesign.logoPurple;
    return Stack(
      alignment: Alignment.center,
      children: [
        Transform.translate(
          offset: const Offset(0, 6),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: JackDesign.bungee(
              fontSize: fontSize,
              color: accentDk,
              height: 1,
              letterSpacing: 2,
            ),
          ),
        ),
        Transform.translate(
          offset: const Offset(0, 3),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: JackDesign.bungee(
              fontSize: fontSize,
              color: accent,
              height: 1,
              letterSpacing: 2,
            ),
          ),
        ),
        ShaderMask(
          shaderCallback: (rect) => gradient.createShader(rect),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: JackDesign.bungee(
              fontSize: fontSize,
              color: Colors.white,
              height: 1,
              letterSpacing: 2,
              shadows: [
                Shadow(color: glow, blurRadius: 22),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
