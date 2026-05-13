import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'game/config.dart';
import 'i18n/i18n.dart';
import 'services/audio_manager.dart';
import 'ui/screens/home_screen.dart';

class JumpingJackApp extends StatefulWidget {
  const JumpingJackApp({super.key});

  @override
  State<JumpingJackApp> createState() => _JumpingJackAppState();
}

class _JumpingJackAppState extends State<JumpingJackApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    I18n.instance.addListener(_onLocaleChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    I18n.instance.removeListener(_onLocaleChanged);
    super.dispose();
  }

  void _onLocaleChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Pause music + ambient loops whenever the app is no longer in the
    // foreground so audio doesn't keep playing after the user swipes
    // back to the launcher or locks the screen. `inactive` covers the
    // brief transition (e.g. system dialog) but on Android the
    // definitive backgrounded states are `paused` and `hidden`.
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        AudioManager.onAppBackground();
      case AppLifecycleState.resumed:
        AudioManager.onAppForeground();
      case AppLifecycleState.inactive:
        break;
    }
  }

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
