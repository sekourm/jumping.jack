import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';

/// Centralised audio entry-points. Music uses a single, persistent
/// [AudioPlayer] that is preloaded at boot (source set, looping, muted)
/// so the very first user gesture only has to call `setVolume` + `resume`
/// — both synchronous from the gesture's call stack — to satisfy iOS
/// Safari's strict autoplay policy. SFX go through FlameAudio's one-shot
/// pool which manages its own player lifecycle.
class AudioManager {
  static const _sfxFiles = <String>[
    'jump.mp3',
    'land.mp3',
    'bounce.mp3',
    'bouncy.mp3',
    'gameover.mp3',
    'click.mp3',
    'pickup_star.mp3',
    'pickup_crystal.mp3',
    'pickup_heart.mp3',
    'pickup_warp.mp3',
    'platform_explode.mp3',
  ];
  static const _musicFile = 'music.mp3';

  static bool _preloaded = false;
  static AudioPlayer? _musicPlayer;
  static bool _musicReady = false;
  static AudioPlayer? _gameOverPlayer;

  // User-configurable volume multipliers (0..1).
  static double musicVolume = 0.5;
  static double sfxVolume = 0.5;
  // Current base volume of the music track (independent of musicVolume).
  static double _currentBgmBaseVolume = 0.45;

  /// Loads SFX into FlameAudio's cache and pre-creates the music player
  /// with its source loaded + looping + muted. After this, [startMenuMusic]
  /// / [startGameMusic] only need to call setVolume + resume in the user's
  /// click handler — which is what iOS Safari requires.
  static Future<void> preload() async {
    if (_preloaded) return;
    _preloaded = true;

    try {
      await FlameAudio.audioCache.loadAll(_sfxFiles);
    } catch (e) {
      debugPrint('[Audio] sfx preload failed: $e');
    }

    try {
      final p = AudioPlayer();
      await p.setReleaseMode(ReleaseMode.loop);
      await p.setSource(AssetSource('audio/$_musicFile'));
      await p.setVolume(0); // muted; will be set on first resume
      _musicPlayer = p;
      _musicReady = true;
    } catch (e) {
      debugPrint('[Audio] music preload failed: $e');
    }
  }

  // ---------- Music ----------

  /// Resumes the preloaded music with [volume] as the base level. Called
  /// from a user-gesture handler (button onPressed) so the synchronous
  /// `setVolume` + `resume()` calls execute inside the click's call stack
  /// — the only state in which iOS Safari will actually start the audio.
  static void _resumeMusic({double volume = 0.45}) {
    _currentBgmBaseVolume = volume;
    if (_muted) return; // master mute → keep the track paused
    final p = _musicPlayer;
    if (p == null || !_musicReady) return;
    // Don't await — these calls schedule on the JS event loop synchronously
    // from the gesture, which is what we need.
    p.setVolume(volume * musicVolume);
    p.resume();
  }

  /// Updates the user music volume in real time (sliders).
  static Future<void> setMusicVolume(double v) async {
    musicVolume = v.clamp(0.0, 1.0);
    final target = _currentBgmBaseVolume * musicVolume;
    try {
      await _musicPlayer?.setVolume(target);
    } catch (e) {
      debugPrint('[Audio] setMusicVolume failed: $e');
    }
  }

  static void setSfxVolume(double v) {
    sfxVolume = v.clamp(0.0, 1.0);
  }

  /// Master-mute toggle. When [muted] is true the music track is paused
  /// and every SFX is silenced. When false the previous user-set volumes
  /// are restored automatically.
  static bool _muted = false;
  static bool get isMuted => _muted;
  static Future<void> setMuted(bool muted) async {
    _muted = muted;
    if (muted) {
      try {
        await _musicPlayer?.pause();
      } catch (_) {}
    } else {
      _resumeMusic(volume: _currentBgmBaseVolume);
    }
  }

  // Menu and in-game share the same track — calling either resumes it.
  static void startMenuMusic() => _resumeMusic(volume: 0.45);
  static void startGameMusic() => _resumeMusic(volume: 0.45);

  /// Pauses the music — used when the gameover sting takes over. Pausing
  /// (not stopping) keeps the source loaded so the next resume is instant.
  static Future<void> pauseMusic() async {
    try {
      await _musicPlayer?.pause();
    } catch (_) {}
  }

  /// Plays the game-over jingle once. Pauses music + cancels any previous
  /// gameover SFX first.
  static Future<void> playGameOverJingle() async {
    await pauseMusic();
    await stopGameOverJingle();
    if (_muted) return;
    try {
      _gameOverPlayer =
          await FlameAudio.play('gameover.mp3', volume: 0.65 * sfxVolume);
    } catch (e) {
      debugPrint('[Audio] gameover failed: $e');
    }
  }

  static Future<void> stopGameOverJingle() async {
    final p = _gameOverPlayer;
    _gameOverPlayer = null;
    if (p == null) return;
    try {
      await p.stop();
      await p.release();
    } catch (_) {}
  }

  // Backwards-compat alias used by older call sites that wanted to fully
  // stop music. With the new preload-and-resume model we just pause.
  static Future<void> stopMusic() => pauseMusic();

  // ---------- SFX ----------

  static void _play(String file, {double volume = 1.0}) {
    if (_muted) return;
    try {
      FlameAudio.play(file, volume: volume * sfxVolume);
    } catch (e) {
      debugPrint('[Audio] play $file failed: $e');
    }
  }

  static void jump() => _play('jump.mp3', volume: 0.55);
  static void land() => _play('land.mp3', volume: 0.55);
  static void bounce() => _play('bounce.mp3', volume: 0.55);
  static void bouncy() => _play('bouncy.mp3', volume: 0.7);
  static void click() => _play('click.mp3', volume: 0.7);
  static void pickupStar() => _play('pickup_star.mp3', volume: 0.5);
  static void pickupCrystal() => _play('pickup_crystal.mp3', volume: 0.6);
  static void pickupHeart() => _play('pickup_heart.mp3', volume: 0.6);
  static void pickupWarp() => _play('pickup_warp.mp3', volume: 0.7);
  static void platformExplode() =>
      _play('platform_explode.mp3', volume: 0.4);

  /// Generic BR "someone just died" SFX. Reuses the platform explosion
  /// thud which conveys impact without needing a new audio asset.
  static void brDeath() => _play('platform_explode.mp3', volume: 0.6);
}
