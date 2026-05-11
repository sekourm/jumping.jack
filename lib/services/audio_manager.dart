import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

/// Centralised audio engine for Jumping JACK.
///
/// Architecture
/// ------------
///   • **One-shot SFX** go through `FlameAudio.play` which manages a pool
///     of [AudioPlayer]s internally. The pool plus our voice-limiter
///     (max-N-per-sound-per-window) keeps the mix readable even on the
///     busiest frames (star pickups bursting, multi-kill, combo tick).
///   • **Music + ambient loops** are owned by dedicated long-lived
///     [AudioPlayer]s so we can crossfade between tracks, duck under
///     loud SFX, and modulate pitch/volume of charge / slow-time / danger
///     loops in real time without re-allocating players each frame.
///   • All SFX are preloaded into [FlameAudio.audioCache] and every long
///     player has its source set + muted at boot, so the very first user
///     gesture only has to call `setVolume + resume` — the synchronous
///     pair iOS Safari needs in a click handler to actually start audio.
///
/// Public API is organised by category (UI, actions, pickups, combo,
/// tension, death, BR, ambient). Each call is fire-and-forget; failures
/// log to debugPrint and don't throw.
class AudioManager {
  // ---------------------------------------------------------------------------
  // Asset list
  // ---------------------------------------------------------------------------

  // All MP3 files under assets/audio/ that the engine references. Loaded
  // at boot via FlameAudio.audioCache so first plays don't stutter.
  /// Long-form audio that stays on the audioplayers backend (music
  /// tracks + ambient loops). audioplayers handles seeking, crossfading
  /// and volume ramps cleanly — features we depend on for these tracks.
  static const _longFiles = <String>[
    // Music
    'menu_loop.mp3', 'loop.mp3',
    // Ambient loops driven by [_ambientLoops] below.
    'charge_loop.mp3', 'slow_time_active.mp3',
    'danger_low_heartbeat.mp3', 'wind_ambient.mp3',
  ];

  /// One-shot SFX loaded into SoLoud. Anything that goes through [_play]
  /// must appear here so the pool can resolve it at runtime.
  static const _sfxFiles = <String>[
    // Short victory sting used after a solo win — short enough that
    // SoLoud handles it like any other SFX.
    'win_fanfare.mp3',
    // UI
    'ui_click.mp3', 'ui_hover.mp3', 'ui_back.mp3', 'ui_confirm.mp3',
    'ui_toggle.mp3',
    // Player actions
    'charge_max.mp3', 'jump_release.mp3',
    'land_soft.mp3', 'land_hard.mp3', 'bouncy_boing.mp3',
    'wall_bounce.mp3', 'fall_swoosh.mp3',
    // Pickups
    'pickup_star.mp3', 'pickup_crystal.mp3',
    'slow_time_end.mp3', 'pickup_heart.mp3', 'pickup_vision.mp3',
    'pickup_warp.mp3', 'teleport_arrive.mp3',
    // Combo & rewards
    'combo_tick_a.mp3', 'combo_tick_b.mp3', 'combo_tick_c.mp3',
    'combo_tick_d.mp3', 'combo_x5_plus.mp3', 'combo_break.mp3',
    'bouncy_chain_a.mp3', 'bouncy_chain_b.mp3', 'bouncy_chain_c.mp3',
    'comeback_reward.mp3', 'wall_rebond_reward.mp3', 'score_milestone.mp3',
    'new_best_score.mp3',
    // Tension & danger
    'platform_crack.mp3', 'platform_explode.mp3',
    // Death & game over
    'death_fall.mp3', 'death_crushed.mp3', 'gameover_jingle.mp3',
    'revive_ready.mp3',
    // Battle Royale
    'lobby_player_join.mp3', 'lobby_player_leave.mp3',
    'lobby_countdown_tick.mp3', 'countdown_321.mp3', 'countdown_go.mp3',
    'kill_confirmed.mp3', 'kill_streak.mp3', 'got_crushed.mp3',
    'opponent_died.mp3', 'safe_zone_end.mp3',
    'leader_changed.mp3', 'victory_win.mp3', 'defeat_placement.mp3',
    // Ambient (one-shot variety — the looping ambient loops above are
    // separate).
    'cube_idle_blip.mp3', 'pickup_spawn_chime.mp3',
  ];

  // ---------------------------------------------------------------------------
  // User-facing settings
  // ---------------------------------------------------------------------------

  static double musicVolume = 0.5;
  static double sfxVolume = 0.5;
  static bool _muted = false;
  static bool get isMuted => _muted;

  /// Global attenuation applied to every SFX, every ambient loop, and
  /// the in-game music track — but NOT to the menu music. Lets the
  /// menu stay at its previous reference level while the rest of the
  /// mix sits 60 % quieter so SFX don't clip over the gameplay loop.
  static const double _nonMenuAttenuation = 0.4;

  // ---------------------------------------------------------------------------
  // Lifecycle / preload
  // ---------------------------------------------------------------------------

  static bool _preloaded = false;
  static final _rng = Random();

  /// Loads every SFX into the FlameAudio cache and pre-creates the music
  /// + ambient-loop players (source set + looping + muted). After this
  /// the engine can play any sound or start any loop synchronously from
  /// inside a user-gesture handler — required by browsers to actually
  /// produce audible output.
  static Future<void> preload() async {
    if (_preloaded) return;
    _preloaded = true;

    // Order matters per platform:
    //
    //   • iOS  — SoLoud first, then audioplayers. miniaudio (SoLoud's
    //     backend) sets the AVAudioSession category to `PlayAndRecord`
    //     during its init; PlayAndRecord adds input-routing latency
    //     that crackles over Bluetooth (AirPods). We override the
    //     session back to `ambient` via audioplayers right after so
    //     the recording mode is gone before any sound plays.
    //
    //   • Web / Android / desktop — audioplayers first. On web the
    //     SoLoud module is loaded asynchronously by a separate script
    //     tag and `_engine.isInitialized` reads a property that won't
    //     exist until the wasm has finished loading. Running the
    //     audioplayers setup + long-form preload first gives the
    //     module time to land before we touch SoLoud, otherwise we
    //     hit "Cannot read properties of undefined (reading
    //     '_isInited')" in the JS console.
    final iosFirst = !kIsWeb && Platform.isIOS;
    if (iosFirst) {
      await _SfxPool.initialize();
      await _configureAudioSession();
    } else {
      await _configureAudioSession();
    }

    // Music + ambient loops stay on audioplayers (they need crossfade /
    // volume ramps), so we keep them warm in the FlameAudio cache.
    try {
      await FlameAudio.audioCache.loadAll(_longFiles);
    } catch (e) {
      debugPrint('[Audio] long-form preload failed: $e');
    }

    if (!iosFirst) {
      await _SfxPool.initialize();
    }

    // Music tracks — one player per track (crossfading needs them alive
    // in parallel).
    for (final entry in _musicTracks.entries) {
      await _prepareLongPlayer(entry.value, 'audio/${entry.key}.mp3',
          loop: true);
    }
    // Ambient loops.
    for (final entry in _ambientLoops.entries) {
      await _prepareLongPlayer(entry.value, 'audio/${entry.key}.mp3',
          loop: true);
    }
  }

  /// Forces the iOS AVAudioSession into `ambient` mode, overriding the
  /// `PlayAndRecord` default that SoLoud's miniaudio backend installs
  /// during init. PlayAndRecord adds input-routing latency that crackles
  /// over Bluetooth (AirPods specifically); `ambient` is the lowest-
  /// latency, mix-with-others category appropriate for a casual game.
  ///
  /// Android keeps the regular game-audio config; web is a no-op for
  /// audioplayers' iOS section but the Android block still applies as
  /// a fallback on hybrid web wrappers.
  static Future<void> _configureAudioSession() async {
    try {
      await AudioPlayer.global.setAudioContext(AudioContext(
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.ambient,
        ),
        android: AudioContextAndroid(
          isSpeakerphoneOn: false,
          stayAwake: false,
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.game,
          audioFocus: AndroidAudioFocus.gainTransientMayDuck,
        ),
      ));
    } catch (e) {
      debugPrint('[Audio] AudioContext setup failed: $e');
    }
  }

  static Future<void> _prepareLongPlayer(AudioPlayer p, String asset,
      {required bool loop}) async {
    try {
      if (loop) await p.setReleaseMode(ReleaseMode.loop);
      await p.setSource(AssetSource(asset));
      await p.setVolume(0);
    } catch (e) {
      debugPrint('[Audio] long-player preload $asset failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Music — three tracks, crossfaded
  // ---------------------------------------------------------------------------

  static final AudioPlayer _menuMusic = AudioPlayer();
  static final AudioPlayer _gameMusic = AudioPlayer();

  static final Map<String, AudioPlayer> _musicTracks = {
    'menu_loop': _menuMusic,
    // `loop` is the in-game track for both solo and BR — see
    // `playSoloMusic` / `playBrMusic`, both target this key.
    'loop': _gameMusic,
  };

  // Per-track base volume so the mix stays consistent — music_volume
  // applies on top of these.
  // Menu base stays at the previous reference level (0.45). The
  // in-game `loop` is pre-attenuated by [_nonMenuAttenuation] so its
  // effective volume is 0.42 × 0.4 = 0.168.
  static const Map<String, double> _trackBaseVolume = {
    'menu_loop': 0.45,
    'loop': 0.42 * _nonMenuAttenuation,
  };

  static String? _currentTrack;
  static String? _targetTrack;
  static Timer? _crossfadeTimer;

  /// Duck state: -1.0..0.0 multiplier on top of the music's normal
  /// volume. Set to <1 by [_duckMusic] when a loud SFX fires.
  static double _duck = 1.0;
  static Timer? _duckTimer;

  /// Smooth-fade to the menu track.
  ///
  /// Forces any in-flight ducking back to 1.0 first — otherwise a quick
  /// "menu" tap mid-duck (e.g. straight after the gameover jingle on
  /// solo death, while music is still at 15 %) would cross-fade the
  /// menu in at the ducked volume and read as "menu is too quiet".
  static void playMenuMusic() {
    _duckTimer?.cancel();
    _duckTimer = null;
    _duck = 1.0;
    _switchTo('menu_loop');
  }

  /// Smooth-fade to the in-game gameplay track. Solo and BR share one
  /// `loop` source so the energy stays consistent between modes. The
  /// track is always seeked back to its start so each new run begins
  /// at the intro of the loop rather than wherever the previous run
  /// left off.
  static void playSoloMusic() => _switchTo('loop', restart: true);

  /// Smooth-fade to the Battle Royale track (same `loop` source as
  /// solo). Restarts from the top — see [playSoloMusic].
  static void playBrMusic() => _switchTo('loop', restart: true);

  /// Pauses the current music (keeps source loaded so the next switch
  /// resumes instantly).
  static Future<void> pauseMusic() async {
    final cur = _currentTrack;
    _targetTrack = null;
    _crossfadeTimer?.cancel();
    _crossfadeTimer = null;
    if (cur != null) {
      try {
        await _musicTracks[cur]!.pause();
      } catch (_) {}
    }
    _currentTrack = null;
  }

  /// Back-compat alias used by callers that "stopped" music in the old
  /// API. We just pause to keep the source resident.
  static Future<void> stopMusic() => pauseMusic();

  static void _switchTo(String track, {bool restart = false}) {
    // Same-track call: a normal no-op unless [restart] is asked, in
    // which case seek the player back to position 0 and re-prime its
    // volume (no crossfade needed since from == to). Used by
    // `playSoloMusic`/`playBrMusic` so every new run starts on the
    // first beat of the loop rather than mid-track.
    if (_currentTrack == track && _targetTrack == null) {
      if (!restart) return;
      final p = _musicTracks[track]!;
      try {
        p.seek(Duration.zero);
        if (!_muted) {
          p.setVolume(_trackBaseVolume[track]! * musicVolume * _duck);
          p.resume();
        }
      } catch (_) {}
      return;
    }
    _targetTrack = track;
    _crossfadeTimer?.cancel();

    final from = _currentTrack;
    final to = _musicTracks[track]!;
    final toBase = _trackBaseVolume[track] ?? 0.4;

    // Rewind the incoming track when caller asked for a fresh restart
    // (e.g. entering solo or BR from any context). seek() on a paused
    // or stopped player is safe; on a currently-playing player it just
    // jumps to position 0.
    if (restart) {
      try {
        to.seek(Duration.zero);
      } catch (_) {}
    }

    // Start the new track muted; the crossfade ramps it in. Done from
    // the click handler that ultimately triggered this call (e.g. the
    // user tapping "Jouer"), so the resume() lands inside the gesture
    // and iOS Safari allows it.
    if (!_muted) {
      try {
        to.setVolume(0);
        to.resume();
      } catch (_) {}
    }

    const totalMs = 600;
    const stepMs = 30;
    var step = 0;
    final steps = (totalMs / stepMs).round();
    _crossfadeTimer =
        Timer.periodic(const Duration(milliseconds: stepMs), (t) {
      step++;
      final p = (step / steps).clamp(0.0, 1.0);
      // Out: linear fade; In: ease-in quadratic so the new track feels
      // confident rather than sneaking in.
      final outV = (1 - p);
      final inV = p * p;
      try {
        if (from != null && _musicTracks[from] != null) {
          _musicTracks[from]!.setVolume(
              _trackBaseVolume[from]! * musicVolume * outV * _duck);
        }
        if (!_muted) {
          to.setVolume(toBase * musicVolume * inV * _duck);
        }
      } catch (_) {}
      if (step >= steps) {
        t.cancel();
        _crossfadeTimer = null;
        // Finalise: pause the old one, lock in the new one.
        if (from != null && from != track) {
          try {
            _musicTracks[from]!.pause();
          } catch (_) {}
        }
        _currentTrack = track;
        _targetTrack = null;
      }
    });
  }

  static Future<void> setMusicVolume(double v) async {
    musicVolume = v.clamp(0.0, 1.0);
    _applyMusicVolume();
  }

  static void setSfxVolume(double v) {
    sfxVolume = v.clamp(0.0, 1.0);
    // Ambient loops use sfxVolume — re-apply so the change is audible
    // immediately without waiting for the next gameplay event.
    for (final loop in _ambientLoops.values) {
      _AmbientHandle? h;
      for (final candidate in _ambientHandles.values) {
        if (candidate.player == loop) {
          h = candidate;
          break;
        }
      }
      if (h != null) {
        try {
          loop.setVolume(
            h.intensity * h.maxVolume * sfxVolume * _nonMenuAttenuation,
          );
        } catch (_) {}
      }
    }
  }

  static void _applyMusicVolume() {
    final cur = _currentTrack;
    if (cur == null) return;
    try {
      _musicTracks[cur]!
          .setVolume(_trackBaseVolume[cur]! * musicVolume * _duck);
    } catch (_) {}
  }

  /// Briefly drop music volume to let a loud SFX (victory, gameover,
  /// new best score) cut through. The previous level is restored over
  /// [holdMs] + a short fade.
  static void _duckMusic({double to = 0.4, int holdMs = 400}) {
    if (_currentTrack == null) return;
    _duck = to;
    _applyMusicVolume();
    _duckTimer?.cancel();
    _duckTimer = Timer(Duration(milliseconds: holdMs), () {
      // Ease back over 300ms.
      const fadeMs = 300;
      const stepMs = 30;
      var step = 0;
      final steps = (fadeMs / stepMs).round();
      _duckTimer = Timer.periodic(const Duration(milliseconds: stepMs), (t) {
        step++;
        _duck = to + (1.0 - to) * (step / steps);
        if (_duck > 1) _duck = 1;
        _applyMusicVolume();
        if (step >= steps) {
          _duck = 1.0;
          _applyMusicVolume();
          t.cancel();
          _duckTimer = null;
        }
      });
    });
  }

  // ---------------------------------------------------------------------------
  // Mute toggle
  // ---------------------------------------------------------------------------

  static Future<void> setMuted(bool muted) async {
    _muted = muted;
    if (muted) {
      // Pause every long player; one-shot SFX will be skipped by the
      // gate in [_play].
      try {
        await _menuMusic.pause();
        await _gameMusic.pause();
        for (final p in _ambientLoops.values) {
          await p.pause();
        }
      } catch (_) {}
    } else {
      // Resume the previously-current music track at its target volume.
      final cur = _currentTrack;
      if (cur != null) {
        try {
          _musicTracks[cur]!.resume();
          _musicTracks[cur]!
              .setVolume(_trackBaseVolume[cur]! * musicVolume * _duck);
        } catch (_) {}
      }
      // Resume ambient loops that were active.
      for (final h in _ambientHandles.values) {
        if (h.active) {
          try {
            h.player.resume();
            h.player.setVolume(
              h.intensity * h.maxVolume * sfxVolume * _nonMenuAttenuation,
            );
          } catch (_) {}
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Ambient loops (charge, slow-time, danger, wind, final-two, camera-rise)
  // ---------------------------------------------------------------------------

  static final AudioPlayer _chargeLoop = AudioPlayer();
  static final AudioPlayer _slowTimeLoop = AudioPlayer();
  static final AudioPlayer _dangerLoop = AudioPlayer();
  static final AudioPlayer _windLoop = AudioPlayer();

  static final Map<String, AudioPlayer> _ambientLoops = {
    'charge_loop': _chargeLoop,
    'slow_time_active': _slowTimeLoop,
    'danger_low_heartbeat': _dangerLoop,
    'wind_ambient': _windLoop,
  };

  static final Map<String, _AmbientHandle> _ambientHandles = {
    // Charge loop: gentle hum, lower max volume so it sits beneath the
    // music + cube SFX rather than dominating them. The synth recipe
    // was also softened (sine + triangle + sub, no saw, no clip).
    'charge_loop':
        _AmbientHandle(_chargeLoop, maxVolume: 0.28, supportsRate: true),
    'slow_time_active':
        _AmbientHandle(_slowTimeLoop, maxVolume: 0.30),
    'danger_low_heartbeat':
        _AmbientHandle(_dangerLoop, maxVolume: 0.55),
    'wind_ambient':
        _AmbientHandle(_windLoop, maxVolume: 0.22),
  };

  /// Starts (or updates) the charge wind-up loop. Call every frame the
  /// player is charging with [level] = 0..1; the loop fades in once
  /// active and the playback rate scales 1.0 → 1.5 for a rising-pitch
  /// "build up" feel. Cheap when already running.
  static void chargeLoop(double level) =>
      // Narrower pitch ramp (1.0 → 1.20) than the v1 design (1.0 → 1.5):
      // the build-up stays musical instead of turning shrill at max
      // charge.
      _setAmbient('charge_loop', level,
          rate: 1.0 + level.clamp(0.0, 1.0) * 0.20);

  static void stopChargeLoop() => _setAmbient('charge_loop', 0);

  static void slowTimeLoop(bool active) =>
      _setAmbient('slow_time_active', active ? 1.0 : 0.0);

  static void dangerLoop(double intensity) =>
      _setAmbient('danger_low_heartbeat', intensity);

  static void windLoop(double intensity) =>
      _setAmbient('wind_ambient', intensity);

  static void _setAmbient(String key, double intensity, {double? rate}) {
    final h = _ambientHandles[key];
    final p = _ambientLoops[key];
    if (h == null || p == null) return;
    intensity = intensity.clamp(0.0, 1.0);
    h.intensity = intensity;
    final shouldBeActive = intensity > 0.001 && !_muted;
    final targetVol =
        intensity * h.maxVolume * sfxVolume * _nonMenuAttenuation;

    try {
      if (shouldBeActive && !h.active) {
        h.active = true;
        p.setVolume(targetVol);
        p.resume();
      } else if (!shouldBeActive && h.active) {
        h.active = false;
        p.pause();
      } else if (shouldBeActive) {
        p.setVolume(targetVol);
      }
      if (rate != null && h.supportsRate) {
        // setPlaybackRate is supported on all current platforms; the
        // try/catch keeps us safe if a platform-specific failure ever
        // pops up.
        p.setPlaybackRate(rate);
      }
    } catch (e) {
      debugPrint('[Audio] _setAmbient $key failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Game-over sting
  // ---------------------------------------------------------------------------
  //
  // Two iterations have failed in this slot:
  //   v1 — dedicated AudioPlayer with stop()/seek()/resume(). On web,
  //        after `stop()`, audioplayers detaches the source on some
  //        platforms and a bare `resume()` becomes a silent no-op,
  //        so the jingle sometimes never played.
  //   v2 — routed through FlameAudio.play but `await pauseMusic()`
  //        was called first. The await introduced a window during
  //        which a subsequent state change (e.g. AudioManager.setMuted,
  //        the death overlay starting its own music switch) could
  //        intercept and drop the play.
  //
  // v3 (current) — play **first**, then duck the music underneath. No
  // pause, no await before play, no state churn between the call and
  // the actual playback start. FlameAudio's pool gives us a fresh
  // instance every time so back-to-back deaths don't share state.

  static void playGameOverJingle() {
    _play('gameover_jingle.mp3', volume: 0.85);
    // Drop music to barely audible for ~2.5 s — the jingle is ~2.5 s
    // long. Music ramps back smoothly via _duckMusic's fade-out.
    _duckMusic(to: 0.15, holdMs: 2200);
  }

  /// No-op retained for back-compat. The pool-based playback doesn't
  /// give us a handle to interrupt, but the jingle is short enough
  /// that a retry overlap is inaudible.
  static Future<void> stopGameOverJingle() async {}

  // ---------------------------------------------------------------------------
  // Voice limiter — caps how often the same file can fire per second.
  // ---------------------------------------------------------------------------

  static final Map<String, List<DateTime>> _voiceLog = {};

  static bool _allow(String file, {int maxPerSecond = 6}) {
    if (_muted) return false;
    final now = DateTime.now();
    final log = _voiceLog.putIfAbsent(file, () => []);
    final cutoff = now.subtract(const Duration(seconds: 1));
    log.removeWhere((t) => t.isBefore(cutoff));
    if (log.length >= maxPerSecond) return false;
    log.add(now);
    return true;
  }

  // ---------------------------------------------------------------------------
  // Generic one-shot helpers
  // ---------------------------------------------------------------------------

  static void _play(
    String file, {
    double volume = 1.0,
    double pitchVariation = 0.0,
    int maxPerSecond = 6,
  }) {
    if (!_allow(file, maxPerSecond: maxPerSecond)) return;
    final rate = pitchVariation > 0
        ? 1.0 + (_rng.nextDouble() * 2 - 1) * pitchVariation
        : 1.0;
    // Go through the bounded round-robin pool instead of
    // FlameAudio.play (which allocated a fresh AudioPlayer per call —
    // each becoming an <audio> element on web, hitting the ~25 element
    // browser limit during dense gameplay → "missing sounds"). The
    // global 0.8 attenuation lowers SFX so they sit cleanly beneath
    // the menu music reference level.
    _SfxPool.play(file, volume * sfxVolume * _nonMenuAttenuation,
        rate: rate);
  }

  // ---------------------------------------------------------------------------
  // SFX — UI
  // ---------------------------------------------------------------------------

  static void uiClick()    => _play('ui_click.mp3', volume: 0.55, pitchVariation: 0.02);
  static void uiHover()    => _play('ui_hover.mp3', volume: 0.40, maxPerSecond: 4);
  static void uiBack()     => _play('ui_back.mp3', volume: 0.60);
  static void uiConfirm()  => _play('ui_confirm.mp3', volume: 0.65);
  static void uiToggle()   => _play('ui_toggle.mp3', volume: 0.55);

  // Back-compat: old call site used `click()`. Map to the new ui_click.
  static void click() => uiClick();

  // ---------------------------------------------------------------------------
  // SFX — Player actions
  // ---------------------------------------------------------------------------

  static void chargeMax()    => _play('charge_max.mp3', volume: 0.55);
  static void jumpRelease()  => _play('jump_release.mp3', volume: 0.65, pitchVariation: 0.03);
  static void landSoft()     => _play('land_soft.mp3', volume: 0.55, pitchVariation: 0.04);
  static void landHard()     => _play('land_hard.mp3', volume: 0.70, pitchVariation: 0.04);
  static void bouncyBoing()  => _play('bouncy_boing.mp3', volume: 0.70, pitchVariation: 0.05);
  static void wallBounce()   => _play('wall_bounce.mp3', volume: 0.50, pitchVariation: 0.06, maxPerSecond: 8);

  // Old call sites used these names — keep them mapped so wiring can be
  // upgraded incrementally.
  static void jump() => jumpRelease();
  static void land() => landSoft();
  static void bounce() => wallBounce();
  static void bouncy() => bouncyBoing();

  // ---------------------------------------------------------------------------
  // SFX — Pickups
  // ---------------------------------------------------------------------------

  static void pickupStar()      => _play('pickup_star.mp3', volume: 0.55, pitchVariation: 0.06, maxPerSecond: 10);
  static void pickupCrystal()   => _play('pickup_crystal.mp3', volume: 0.60);
  static void pickupHeart()     => _play('pickup_heart.mp3', volume: 0.55);
  static void pickupVision()    => _play('pickup_vision.mp3', volume: 0.55);
  static void pickupWarp()      => _play('pickup_warp.mp3', volume: 0.65);
  static void teleportArrive()  => _play('teleport_arrive.mp3', volume: 0.65);
  static void slowTimeEnd()     => _play('slow_time_end.mp3', volume: 0.55);

  // Old call site name kept.
  static void pickupStarLegacy() => pickupStar();

  // ---------------------------------------------------------------------------
  // SFX — Combo & rewards
  // ---------------------------------------------------------------------------

  /// Picks a tick variant from C/E/G/B based on the current combo step so
  /// chained landings climb an arpeggio (×2 = C, ×3 = E, ×4 = G, ×5+ = B).
  static void comboTick(int step) {
    const variants = [
      'combo_tick_a.mp3',
      'combo_tick_b.mp3',
      'combo_tick_c.mp3',
      'combo_tick_d.mp3',
    ];
    final idx = (step - 2).clamp(0, variants.length - 1);
    _play(variants[idx], volume: 0.50);
  }

  static void comboX5Plus() => _play('combo_x5_plus.mp3', volume: 0.55);
  static void comboBreak()  => _play('combo_break.mp3', volume: 0.45);

  /// Bouncy chain SFX, escalating by step (root, +5 semitones, +10).
  static void bouncyChain(int step) {
    const variants = [
      'bouncy_chain_a.mp3',
      'bouncy_chain_b.mp3',
      'bouncy_chain_c.mp3',
    ];
    final idx = (step - 2).clamp(0, variants.length - 1);
    _play(variants[idx], volume: 0.55);
  }

  static void comebackReward()    => _play('comeback_reward.mp3', volume: 0.60);
  static void wallRebondReward()  => _play('wall_rebond_reward.mp3', volume: 0.55);
  static void scoreMilestone()    => _play('score_milestone.mp3', volume: 0.55);

  /// Big "new best" stinger — also ducks the music so it really lands.
  static void newBestScore() {
    _play('new_best_score.mp3', volume: 0.75);
    _duckMusic(to: 0.35, holdMs: 800);
  }

  // ---------------------------------------------------------------------------
  // SFX — Tension & death
  // ---------------------------------------------------------------------------

  static void platformCrack()    => _play('platform_crack.mp3', volume: 0.45, maxPerSecond: 4);
  static void platformExplode()  => _play('platform_explode.mp3', volume: 0.55);
  // Death sounds are critical UX feedback — bypass the voice limiter
  // entirely so a rapid replay loop never silently drops them.
  static void deathFall()        => _play('death_fall.mp3', volume: 0.85, maxPerSecond: 99);
  static void deathCrushed()     => _play('death_crushed.mp3', volume: 0.85, maxPerSecond: 99);
  static void reviveReady()      => _play('revive_ready.mp3', volume: 0.55);

  // ---------------------------------------------------------------------------
  // SFX — Battle Royale
  // ---------------------------------------------------------------------------

  static void lobbyPlayerJoin()    => _play('lobby_player_join.mp3', volume: 0.55);
  static void lobbyPlayerLeave()   => _play('lobby_player_leave.mp3', volume: 0.50);
  static void lobbyCountdownTick() => _play('lobby_countdown_tick.mp3', volume: 0.55, maxPerSecond: 4);

  static void countdown321() {
    _play('countdown_321.mp3', volume: 0.70);
    _duckMusic(to: 0.55, holdMs: 250);
  }

  static void countdownGo() {
    _play('countdown_go.mp3', volume: 0.85);
    _duckMusic(to: 0.45, holdMs: 400);
  }

  static void killConfirmed()   => _play('kill_confirmed.mp3', volume: 0.75);
  static void killStreak()      => _play('kill_streak.mp3', volume: 0.70);
  static void gotCrushed()      => _play('got_crushed.mp3', volume: 0.85);
  static void opponentDied()    => _play('opponent_died.mp3', volume: 0.55);
  static void safeZoneEnd()     => _play('safe_zone_end.mp3', volume: 0.65);
  static void leaderChanged()   => _play('leader_changed.mp3', volume: 0.55);

  static void victoryWin() {
    _play('victory_win.mp3', volume: 0.85);
    _duckMusic(to: 0.20, holdMs: 1500);
  }

  static void defeatPlacement() {
    _play('defeat_placement.mp3', volume: 0.65);
    _duckMusic(to: 0.50, holdMs: 800);
  }

  /// Back-compat: any non-local death used to play this generic thud.
  /// Routed to the BR opponent-died bell now.
  static void brDeath() => opponentDied();

  // ---------------------------------------------------------------------------
  // SFX — Ambient one-shots
  // ---------------------------------------------------------------------------

  static void cubeIdleBlip()       => _play('cube_idle_blip.mp3', volume: 0.30, maxPerSecond: 1);
  static void pickupSpawnChime()   => _play('pickup_spawn_chime.mp3', volume: 0.35, maxPerSecond: 3);

  /// Win fanfare for solo (mini, between gameplay and result screen).
  /// Distinct from BR `victoryWin` which is louder and longer.
  static void winFanfare() {
    _play('win_fanfare.mp3', volume: 0.70);
    _duckMusic(to: 0.30, holdMs: 1000);
  }

  // ---------------------------------------------------------------------------
  // Back-compat aliases for the old API. These wire the old method names
  // used across the codebase to the new sounds, so the migration of
  // every call site can happen incrementally without breaking the build.
  // ---------------------------------------------------------------------------

  static void startMenuMusic() => playMenuMusic();
  static void startGameMusic() => playSoloMusic();
}

/// Internal state for a long-lived ambient loop. Tracks whether it's
/// currently audible and the user-facing intensity so volume changes can
/// be applied without re-issuing `resume`/`pause` every frame.
class _AmbientHandle {
  _AmbientHandle(
    this.player, {
    required this.maxVolume,
    this.supportsRate = false,
  });

  final AudioPlayer player;
  final double maxVolume;
  final bool supportsRate;
  double intensity = 0;
  bool active = false;
}

/// Bounded round-robin pool of [AudioPlayer]s for one-shot SFX.
///
/// `FlameAudio.play()` creates a new [AudioPlayer] per call. On Flutter
/// web every player is a separate `<audio>` element, and most browsers
/// throttle at ~25 concurrent elements. In dense gameplay (jump, land,
/// combo tick, pickup, wall bounce all firing in a second on top of
/// the ambient loops) we hit that cap and new plays silently fail —
/// exactly the "sons qui disparaissent" symptom.
///
/// This pool keeps a fixed set of 12 players and rotates through them.
/// When the round-robin wraps, the oldest sound gets cut off by the
/// next play — which is the right LRU behaviour for game SFX (newer
/// events are always more relevant to the player).
///
/// Players use [ReleaseMode.stop] so they stay alive after a sound
/// finishes; otherwise they'd be released and the slot would shrink.
/// SoLoud-backed SFX pool.
///
/// Why not the previous audioplayers round-robin pool: audioplayers uses
/// `AVPlayer` on iOS (built for video) and re-creates an `AVPlayerItem`
/// on every play, costing 100-200 ms per SFX. In dense gameplay (a jump,
/// a combo tick and a land firing within ~100 ms) the delay piles up and
/// SFX visibly trail the action.
///
/// SoLoud wraps MiniAudio: assets are decoded once into an `AudioSource`,
/// then `play()` queues the playback on the mixer with sub-frame latency.
/// We preload every entry of [AudioManager._sfxFiles] at boot, then just
/// dispatch to the cached source.
class _SfxPool {
  static final SoLoud _engine = SoLoud.instance;
  static final Map<String, AudioSource> _sources = {};
  static bool _ready = false;

  static Future<void> initialize() async {
    if (_ready) return;
    try {
      if (!_engine.isInitialized) {
        // iOS-only override: the hardware is natively 48 kHz, so SoLoud's
        // 44.1 kHz default forces a sample-rate conversion every frame
        // and produces audible crackling on the iPhone speaker. An 8192-
        // sample buffer (~170 ms) was tuned for AirPods / Bluetooth: at
        // 4096 (~85 ms) the buffer occasionally underran when BT
        // congestion stretched the round-trip past the buffer window,
        // producing intermittent crackling in earbuds. The added latency
        // is barely perceptible for a casual game.
        //
        // Web + Android + macOS keep the defaults, which were already
        // working cleanly — the conversion logic differs per backend
        // (Web Audio API, AAudio, CoreAudio) and forcing iOS values on
        // them reintroduces conversion overhead where there was none.
        if (!kIsWeb && Platform.isIOS) {
          await _engine.init(sampleRate: 48000, bufferSize: 8192);
        } else {
          await _engine.init();
        }
      }
      // 16 concurrent voices is plenty for our densest scenes (a combo
      // chain, a landing and a pickup can all fire in the same frame).
      // SoLoud evicts the oldest voice past the limit, so a tighter cap
      // never produces silence — only voice stealing.
      _engine.setMaxActiveVoiceCount(16);
    } catch (e) {
      debugPrint('[Audio] SoLoud init failed: $e');
      return;
    }

    for (final file in AudioManager._sfxFiles) {
      try {
        _sources[file] =
            await _engine.loadAsset('assets/audio/$file');
      } catch (e) {
        debugPrint('[Audio] SoLoud load $file failed: $e');
      }
    }
    _ready = true;
  }

  /// Plays [asset] through the SoLoud mixer. [volume] is applied on the
  /// new voice; [rate] adjusts playback speed (and therefore pitch —
  /// matches the previous audioplayers semantics so the call sites keep
  /// working unchanged). Failures are swallowed: a missing SFX must not
  /// break gameplay.
  static void play(String asset, double volume, {double rate = 1.0}) {
    if (!_ready) return;
    final source = _sources[asset];
    if (source == null) return;
    unawaited(_playAsync(source, asset, volume, rate));
  }

  static Future<void> _playAsync(
    AudioSource source,
    String asset,
    double volume,
    double rate,
  ) async {
    try {
      final handle = await _engine.play(source, volume: volume);
      if (rate != 1.0) {
        _engine.setRelativePlaySpeed(handle, rate);
      }
    } catch (e) {
      debugPrint('[Audio] SoLoud play $asset failed: $e');
    }
  }
}
