import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../game/config.dart';
import '../../game/jumping_jack_game.dart';
import '../../services/audio_manager.dart';
import '../../state/game_state.dart';
import '../overlays/death_overlay.dart';
import '../overlays/hud_overlay.dart';
import '../overlays/tutorial_overlay.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final GameState _gameState;
  late final JumpingJackGame _game;

  @override
  void initState() {
    super.initState();
    _gameState = GameState();
    _game = JumpingJackGame(gameState: _gameState);
  }

  @override
  void dispose() {
    AudioManager.stopMusic();
    _gameState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GameConfig.bgColor,
      body: GameWidget<JumpingJackGame>(
        game: _game,
        overlayBuilderMap: {
          'hud': (_, game) => HudOverlay(game: game),
          'tutorial': (_, game) => TutorialOverlay(game: game),
          'death': (_, game) => DeathOverlay(game: game),
        },
        initialActiveOverlays: const ['hud', 'tutorial', 'death'],
      ),
    );
  }
}
