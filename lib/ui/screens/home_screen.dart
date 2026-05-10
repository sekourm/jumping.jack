import 'package:flutter/material.dart';

import '../../config/supabase_config.dart';
import '../../game/config.dart';
import '../../i18n/i18n.dart';
import '../../services/audio_manager.dart';
import '../../services/preferences.dart';
import '../widgets/cosmic_background.dart';
import '../widgets/fortnite_button.dart';
import 'game_screen.dart';
import 'lobby_screen.dart';
import 'settings_screen.dart';

/// Bumped manually before each push so we can verify the deploy is live.
const String kAppVersion = 'v1.0';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    I18n.instance.addListener(_onLocaleChanged);
    AudioManager.preload().then((_) => AudioManager.startMenuMusic());
  }

  @override
  void dispose() {
    I18n.instance.removeListener(_onLocaleChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onLocaleChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GameConfig.bgColor,
      body: Stack(
        children: [
          Positioned.fill(child: CosmicBackground(platforms: 0)),
          Positioned(
            right: 14,
            bottom: 10,
            child: SafeArea(
              child: Text(
                kAppVersion,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.40),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _BestScoreChip(score: Preferences.bestScore),
                          const SizedBox(width: 8),
                          _BrWinsChip(wins: Preferences.brWins),
                        ],
                      ),
                      _IconChip(
                        icon: Icons.settings_outlined,
                        onPressed: _openSettings,
                        tooltip: 'Paramètres',
                      ),
                    ],
                  ),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const _Logo(text: 'JUMPING JACK'),
                        const SizedBox(height: 56),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 280),
                          child: FortniteButton(
                            label: I18n.t.playSolo,
                            icon: Icons.play_arrow_rounded,
                            onPressed: _startGame,
                            height: 52,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 22),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 280),
                          child: FortniteButton(
                            label: I18n.t.battleRoyale,
                            icon: Icons.local_fire_department_rounded,
                            style: FortniteButtonStyle.epic,
                            onPressed: _openBattleRoyale,
                            height: 52,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _startGame() {
    AudioManager.click();
    AudioManager.startGameMusic();
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (_, a, b) => const GameScreen(),
        transitionDuration: const Duration(milliseconds: 180),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        transitionsBuilder: (_, animation, b, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    ).then((_) {
      if (mounted) {
        AudioManager.startMenuMusic();
        setState(() {});
      }
    });
  }

  void _openSettings() {
    AudioManager.click();
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
    );
  }

  void _openBattleRoyale() {
    AudioManager.click();
    if (!SupabaseConfig.isConfigured) {
      _showToast(I18n.t.backendNotConfigured);
      return;
    }
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (_, a, b) => const LobbyScreen(),
        transitionDuration: const Duration(milliseconds: 200),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        transitionsBuilder: (_, animation, b, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(20),
          backgroundColor: const Color(0xFF1F0F38),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFFB14BFF), width: 1.4),
          ),
          duration: const Duration(seconds: 2),
          content: Row(
            children: [
              const Icon(
                Icons.local_fire_department_rounded,
                color: Color(0xFFB14BFF),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
  }
}

class _Logo extends StatelessWidget {
  const _Logo({required this.text});
  final String text;

  static const double _fontSize = 46;
  static const double _letterSpacing = 5;
  // Italic-like skew gives the title forward momentum.
  static const double _skew = -0.10;
  // Number of layered shadow copies that fake a 3D extrusion.
  static const int _depthLayers = 4;

  TextStyle _base({Paint? foreground, Color? color, List<Shadow>? shadows}) =>
      TextStyle(
        fontSize: _fontSize,
        fontWeight: FontWeight.w900,
        letterSpacing: _letterSpacing,
        height: 1,
        foreground: foreground,
        color: foreground == null ? color : null,
        shadows: shadows,
      );

  @override
  Widget build(BuildContext context) {
    final accent = GameConfig.playerColor;

    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.skewX(_skew),
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // 3D extrusion: stacked offset copies, deep brown-black furthest
          // back, warm dark closest to the front face.
          for (var i = _depthLayers; i >= 1; i--)
            Transform.translate(
              offset: Offset(i * 0.7, i * 1.0),
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: _base(
                  color: Color.lerp(
                    const Color(0xFF7A3700),
                    const Color(0xFF110500),
                    (i - 1) / (_depthLayers - 1),
                  ),
                ),
              ),
            ),
          // Outline (stroke) — clean cell-shaded edge.
          Text(
            text,
            textAlign: TextAlign.center,
            style: _base(
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 6
                ..color = Colors.black.withValues(alpha: 0.95),
            ),
          ),
          // Diagonal yellow → orange gradient fill with warm glow.
          ShaderMask(
            shaderCallback: (rect) => const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFFFF1B8),
                Color(0xFFFFC857),
                Color(0xFFFF7E1A),
              ],
              stops: [0.0, 0.55, 1.0],
            ).createShader(rect),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: _base(
                color: Colors.white,
                shadows: [
                  Shadow(
                    color: accent.withValues(alpha: 0.70),
                    blurRadius: 26,
                  ),
                  Shadow(
                    color: accent.withValues(alpha: 0.35),
                    blurRadius: 50,
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

class _IconChip extends StatelessWidget {
  const _IconChip({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
  });
  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.04),
      shape: const CircleBorder(side: BorderSide(color: Colors.white24)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Tooltip(
          message: tooltip,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(
              icon,
              color: Colors.white70,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
    required this.active,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accent;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: accent.withValues(alpha: active ? 0.55 : 0.22),
          width: 1.2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: accent.withValues(alpha: active ? 1.0 : 0.5),
            size: 16,
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: accent.withValues(alpha: active ? 0.95 : 0.55),
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  height: 1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.4,
                  height: 1,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BrWinsChip extends StatelessWidget {
  const _BrWinsChip({required this.wins});
  final int wins;

  @override
  Widget build(BuildContext context) {
    return _StatChip(
      icon: Icons.local_fire_department_rounded,
      label: 'BR',
      value: '$wins',
      accent: const Color(0xFFB14BFF),
      active: wins > 0,
    );
  }
}

class _BestScoreChip extends StatelessWidget {
  const _BestScoreChip({required this.score});
  final int score;

  @override
  Widget build(BuildContext context) {
    return _StatChip(
      icon: Icons.emoji_events,
      label: 'SCORE',
      value: score > 0 ? '$score' : '—',
      accent: GameConfig.playerColor,
      active: score > 0,
    );
  }
}

