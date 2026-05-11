import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'config/supabase_config.dart';
import 'i18n/i18n.dart';
import 'services/audio_manager.dart';
import 'services/preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Full edge-to-edge: hide the status bar so the game (and overlays like the
  // BR safezone vignette / tutorial dim) draw all the way to the screen
  // edges, including the sliver around the iPhone notch.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  // Supabase must come BEFORE Preferences.init(): the latter calls
  // _hydrateFromCloud() which reads Supabase.instance.client. With the
  // reverse order the very first launch fired an "instance not initialized"
  // assertion in debug mode.
  if (SupabaseConfig.isConfigured) {
    try {
      await Supabase.initialize(
        url: SupabaseConfig.url,
        anonKey: SupabaseConfig.anonKey,
      );
    } catch (e) {
      debugPrint('[Supabase] init failed: $e');
    }
  }
  await Preferences.init();
  I18n.instance.load();
  // Sync the persisted mute state into the audio engine before any
  // music / SFX call.
  if (Preferences.muted) {
    await AudioManager.setMuted(true);
  }
  runApp(const JumpingJackApp());
}
