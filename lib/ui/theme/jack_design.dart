import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Centralized design tokens for the Jumping JACK UI refresh.
/// Mirrors the CSS custom properties in the design handoff (`styles.css`).
class JackDesign {
  JackDesign._();

  // ---- Palette ----
  static const Color yellow = Color(0xFFFFC857);
  static const Color yellowHi = Color(0xFFFFE198);
  static const Color yellowDk = Color(0xFFC8861A);
  static const Color brown = Color(0xFF7A4A00);
  static const Color brownDk = Color(0xFF4A2C00);
  static const Color brownInk = Color(0xFF2A1700);

  static const Color purple = Color(0xFFB14BFF);
  static const Color purpleHi = Color(0xFFD896FF);
  static const Color purpleDk = Color(0xFF5C1A8A);
  static const Color purpleInk = Color(0xFF2A0640);

  static const Color cyan = Color(0xFF7CC0FF);
  static const Color cyanHi = Color(0xFFB7DEFF);
  static const Color cyanDk = Color(0xFF2E78C8);
  static const Color cyanInk = Color(0xFF082040);

  static const Color red = Color(0xFFFF5E5B);
  static const Color green = Color(0xFF7AE091);
  static const Color greenHi = Color(0xFFB5F0C4);
  static const Color greenDk = Color(0xFF2E8A48);
  static const Color greenInk = Color(0xFF0A2814);
  static const Color mars = Color(0xFFFF8A5C);

  static const Color bg = Color(0xFF101820);
  static const Color bg2 = Color(0xFF1A2533);

  // ---- Gradients ----
  static const LinearGradient logoGold = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFF1C2), yellow, yellowDk],
    stops: [0.0, 0.45, 0.95],
  );

  static const LinearGradient logoPurple = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFF1D2FF), purple, purpleDk],
    stops: [0.0, 0.50, 1.0],
  );

  static const LinearGradient logoBr = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFF1D2FF), purple, purpleDk],
    stops: [0.0, 0.50, 1.0],
  );

  static const LinearGradient btnPrimary = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [yellowHi, yellow, yellowDk],
    stops: [0.0, 0.5, 1.0],
  );

  static const LinearGradient btnEpic = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [purpleHi, purple, purpleDk],
    stops: [0.0, 0.5, 1.0],
  );

  static const LinearGradient btnCyan = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [cyanHi, cyan, cyanDk],
    stops: [0.0, 0.5, 1.0],
  );

  static const LinearGradient btnDanger = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFAFAD), red, Color(0xFFB22320)],
    stops: [0.0, 0.5, 1.0],
  );

  static const LinearGradient btnGreen = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [greenHi, green, greenDk],
    stops: [0.0, 0.5, 1.0],
  );

  // ---- Fonts (Google Fonts: Bungee + Manrope) ----
  /// Display + numbers — used for logos, big scores, button labels.
  static TextStyle bungee({
    double fontSize = 16,
    Color color = Colors.white,
    double letterSpacing = 0,
    double height = 1,
    List<Shadow>? shadows,
    Paint? foreground,
    FontFeature? feature,
  }) {
    return GoogleFonts.bungee(
      fontSize: fontSize,
      color: foreground == null ? color : null,
      letterSpacing: letterSpacing,
      height: height,
      shadows: shadows,
      foreground: foreground,
      fontFeatures: feature == null ? null : [feature],
    );
  }

  /// UI body — Manrope. Default weight 800 for the cap-letterspaced labels.
  static TextStyle manrope({
    double fontSize = 13,
    FontWeight weight = FontWeight.w800,
    Color color = Colors.white,
    double letterSpacing = 0,
    double height = 1.2,
    List<Shadow>? shadows,
    FontStyle? style,
  }) {
    return GoogleFonts.manrope(
      fontSize: fontSize,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
      shadows: shadows,
      fontStyle: style,
    );
  }

  /// Caps + spaced label, used everywhere (e.g. AUDIO / SCORE / VIVANTS).
  static TextStyle label({
    double fontSize = 11,
    Color color = Colors.white,
    double letterSpacing = 2.5,
  }) =>
      manrope(
        fontSize: fontSize,
        weight: FontWeight.w800,
        color: color,
        letterSpacing: letterSpacing,
      );
}

/// Cosmic stage palette. Mirrors `.cosmic.{stage}` in styles.css.
enum JackStage {
  earth,
  moon,
  mars,
  jupiter,
  saturn,
  nebula,
  battle,
  dark;

  /// Stages used for the random home background (excludes battle/dark).
  static const List<JackStage> worlds = [
    earth,
    moon,
    mars,
    jupiter,
    saturn,
    nebula,
  ];

  StageGradient get gradient {
    switch (this) {
      case JackStage.earth:
        return const StageGradient(
          Color(0xFF0D2548),
          Color(0xFF0E1A2E),
          Color(0xFF060A14),
          [
            NebulaBlob(Color(0xFF7CC0FF), 0.80, 0.20, 0.55),
            NebulaBlob(Color(0xFF5028B4), -0.10, 0.70, 0.70),
          ],
        );
      case JackStage.moon:
        return const StageGradient(
          Color(0xFF2B3140),
          Color(0xFF14171F),
          Color(0xFF08090D),
          [
            NebulaBlob(Color(0xFFDCDCF0), 0.70, 0.30, 0.50),
          ],
        );
      case JackStage.mars:
        return const StageGradient(
          Color(0xFF5A1A14),
          Color(0xFF2E0D0A),
          Color(0xFF100604),
          [
            NebulaBlob(JackDesign.mars, 0.80, 0.25, 0.60),
            NebulaBlob(Color(0xFFB43C1E), -0.10, 0.75, 0.65),
          ],
        );
      case JackStage.jupiter:
        return const StageGradient(
          Color(0xFF6B4A25),
          Color(0xFF2A1D10),
          Color(0xFF100A05),
          [
            NebulaBlob(Color(0xFFFFC88C), 0.70, 0.30, 0.55),
            NebulaBlob(Color(0xFFB47828), 0.10, 0.75, 0.60),
          ],
        );
      case JackStage.saturn:
        return const StageGradient(
          Color(0xFF7A5524),
          Color(0xFF3A280F),
          Color(0xFF130D04),
          [
            NebulaBlob(Color(0xFFFFC864), 0.75, 0.25, 0.55),
            NebulaBlob(Color(0xFFA05A14), 0.0, 0.75, 0.60),
          ],
        );
      case JackStage.nebula:
        return const StageGradient(
          Color(0xFF2C1252),
          Color(0xFF170729),
          Color(0xFF08030F),
          [
            NebulaBlob(JackDesign.purple, 0.75, 0.25, 0.60),
            NebulaBlob(Color(0xFFFF64C8), 0.0, 0.70, 0.65),
          ],
        );
      case JackStage.battle:
        return const StageGradient(
          Color(0xFF2A0E4A),
          Color(0xFF160628),
          Color(0xFF07020E),
          [
            NebulaBlob(JackDesign.purple, 0.50, 0.20, 0.70),
            NebulaBlob(Color(0xFF7828C8), 0.10, 0.80, 0.60),
          ],
        );
      case JackStage.dark:
        return const StageGradient(
          Color(0xFF0B0D12),
          Color(0xFF090B0F),
          Color(0xFF06080C),
          [],
        );
    }
  }
}

class StageGradient {
  const StageGradient(this.top, this.mid, this.bottom, this.blobs);
  final Color top;
  final Color mid;
  final Color bottom;
  final List<NebulaBlob> blobs;
}

class NebulaBlob {
  const NebulaBlob(this.color, this.x, this.y, this.size);
  final Color color;
  final double x; // 0..1 (can be negative or >1 for off-canvas glow)
  final double y;
  final double size; // fraction of min(w,h)
}

/// Per-slot accent colour shared across the BR HUD, the in-game cubes and
/// the BR result screen so a player's colour stays consistent everywhere.
const List<Color> kSlotColors = <Color>[
  JackDesign.yellow,        // slot 0 (local player)
  JackDesign.cyan,          // slot 1
  Color(0xFFFF6E94),        // slot 2 (rose)
  JackDesign.green,         // slot 3 (vert)
  Color(0xFFFFA64C),        // slot 4 (orange)
];

Color slotColor(int slot) =>
    kSlotColors[slot.clamp(0, kSlotColors.length - 1)];
