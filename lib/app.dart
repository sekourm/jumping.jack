import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'game/config.dart';
import 'ui/screens/home_screen.dart';

class JumpingJackApp extends StatelessWidget {
  const JumpingJackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Jumping Jack',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: GameConfig.bgColor,
        colorScheme: ColorScheme.fromSeed(
          seedColor: GameConfig.playerColor,
          brightness: Brightness.dark,
        ),
      ),
      builder: (context, child) {
        if (!kIsWeb || child == null) {
          return child ?? const SizedBox();
        }
        // On web, letterbox the app to a mobile portrait width with plain
        // black side bands. The cosmic progression happens inside the game.
        return ColoredBox(
          color: Colors.black,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: child,
            ),
          ),
        );
      },
      home: const HomeScreen(),
    );
  }
}
