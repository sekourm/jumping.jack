import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../game/config.dart';
import '../../game/jumping_jack_game.dart';
import '../../state/game_state.dart';
import '../overlays/br_hud_overlay.dart';
import '../overlays/br_result_overlay.dart';
import '../overlays/death_overlay.dart';
import '../overlays/hud_overlay.dart';
import '../overlays/tutorial_overlay.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, this.isBattleRoyale = false});

  /// True when the game runs inside a Battle Royale match. Disables the
  /// tutorial overlay, swaps in the BR HUD + result screens, and lets the
  /// game itself broadcast score / death events to the BR service.
  final bool isBattleRoyale;

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
    _game = JumpingJackGame(
      gameState: _gameState,
      isBattleRoyale: widget.isBattleRoyale,
    );
  }

  @override
  void dispose() {
    // Music is owned by the navigation layer: home_screen's `.then`
    // callbacks switch to menu_loop after a pop, lobby_screen restarts
    // it on entry, and JumpingJackGame.onLoad fades to the in-game
    // track on re-entry. Calling stopMusic() here used to race with
    // those crossfades and leave menu_loop stuck at a mid-fade volume
    // (the "musique réduite" bug after a solo death).
    _gameState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isBr = widget.isBattleRoyale;
    return Scaffold(
      backgroundColor: GameConfig.bgColor,
      body: GameWidget<JumpingJackGame>(
        game: _game,
        overlayBuilderMap: {
          'hud': (_, game) => HudOverlay(game: game),
          'tutorial': (_, game) => TutorialOverlay(game: game),
          'death': (_, game) => DeathOverlay(game: game),
          if (isBr) 'br_hud': (_, game) => BrHudOverlay(game: game),
          if (isBr) 'br_result': (_, game) => BrResultOverlay(game: game),
        },
        initialActiveOverlays: [
          'hud',
          if (!isBr) 'tutorial',
          if (!isBr) 'death',
          if (isBr) 'br_hud',
          if (isBr) 'br_result',
        ],
      ),
    );
  }
}
