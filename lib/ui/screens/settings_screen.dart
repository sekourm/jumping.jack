import 'package:flutter/material.dart';

import '../../game/config.dart';
import '../../services/audio_manager.dart';
import '../../services/preferences.dart';
import '../widgets/cosmic_background.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late double _musicVolume;
  late double _sfxVolume;
  late bool _showTutorial;

  @override
  void initState() {
    super.initState();
    _musicVolume = AudioManager.musicVolume;
    _sfxVolume = AudioManager.sfxVolume;
    _showTutorial = Preferences.showTutorial;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GameConfig.bgColor,
      body: Stack(
        children: [
          Positioned.fill(child: CosmicBackground(platforms: 0)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Material(
                      color: Colors.white.withValues(alpha: 0.04),
                      shape: const CircleBorder(
                        side: BorderSide(color: Colors.white24),
                      ),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () {
                          AudioManager.click();
                          Navigator.of(context).pop();
                        },
                        child: const SizedBox(
                          width: 42,
                          height: 42,
                          child: Icon(
                            Icons.arrow_back_rounded,
                            color: Colors.white70,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _SectionLabel('AUDIO'),
                          const SizedBox(height: 8),
                          _SettingCard(
                            icon: Icons.music_note_rounded,
                            child: _VolumeSlider(
                              label: 'MUSIQUE',
                              value: _musicVolume,
                              onChanged: (v) {
                                setState(() => _musicVolume = v);
                                AudioManager.setMusicVolume(v);
                              },
                            ),
                          ),
                          const SizedBox(height: 12),
                          _SettingCard(
                            icon: Icons.graphic_eq_rounded,
                            child: _VolumeSlider(
                              label: 'EFFETS',
                              value: _sfxVolume,
                              onChanged: (v) {
                                setState(() => _sfxVolume = v);
                                AudioManager.setSfxVolume(v);
                              },
                              onChangeEnd: (_) => AudioManager.click(),
                            ),
                          ),
                          const SizedBox(height: 28),
                          const _SectionLabel('JEU'),
                          const SizedBox(height: 8),
                          _SettingCard(
                            icon: Icons.school_rounded,
                            child: _Toggle(
                              label: 'TUTORIEL',
                              description:
                                  'Afficher au début de chaque partie',
                              value: _showTutorial,
                              onChanged: (v) {
                                AudioManager.click();
                                setState(() => _showTutorial = v);
                                Preferences.showTutorial = v;
                              },
                            ),
                          ),
                        ],
                      ),
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
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: GameConfig.playerColor,
              borderRadius: BorderRadius.circular(2),
              boxShadow: [
                BoxShadow(
                  color: GameConfig.playerColor.withValues(alpha: 0.6),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 4,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingCard extends StatelessWidget {
  const _SettingCard({required this.icon, required this.child});
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.05),
            Colors.white.withValues(alpha: 0.015),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.10),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.30),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  GameConfig.playerColor.withValues(alpha: 0.30),
                  GameConfig.playerColor.withValues(alpha: 0.10),
                ],
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: GameConfig.playerColor.withValues(alpha: 0.55),
                width: 1.2,
              ),
            ),
            child: Icon(
              icon,
              color: GameConfig.playerColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 12,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: GameConfig.bgColor,
          activeTrackColor: GameConfig.playerColor,
          inactiveThumbColor: Colors.white60,
          inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
        ),
      ],
    );
  }
}

class _VolumeSlider extends StatelessWidget {
  const _VolumeSlider({
    required this.label,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w900,
                letterSpacing: 3,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: GameConfig.playerColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: GameConfig.playerColor.withValues(alpha: 0.45),
                  width: 1,
                ),
              ),
              child: Text(
                '${(value * 100).round()}%',
                style: const TextStyle(
                  color: GameConfig.playerColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 8,
            activeTrackColor: GameConfig.playerColor,
            inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
            thumbColor: GameConfig.playerColor,
            overlayColor: GameConfig.playerColor.withValues(alpha: 0.18),
            thumbShape: const RoundSliderThumbShape(
              enabledThumbRadius: 10,
              elevation: 4,
            ),
            trackShape: const RoundedRectSliderTrackShape(),
          ),
          child: Slider(
            value: value,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
            min: 0,
            max: 1,
          ),
        ),
      ],
    );
  }
}
