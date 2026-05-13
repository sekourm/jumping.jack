import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../i18n/i18n.dart';

/// Outcome of [Preferences.setPlayerNameRemote]. The values map one-to-one
/// to the `P0001` exception messages raised by the `set_player_name`
/// RPC in migration 0010 so each failure surfaces a specific localised
/// inline error in the pseudo edit dialog.
enum NameChangeResult {
  ok,
  taken,
  forbidden,
  tooShort,
  tooLong,
  invalidChars,
  empty,
  error,
}

/// User preferences. Persisted across launches via [SharedPreferences]:
/// high score, tutorial toggle, and the auto-generated Battle Royale
/// nickname.
///
/// **Identity model.** Each device is identified by a salted-SHA256 hash
/// of its IDFV (iOS) / Android ID. That id is stable across reinstalls,
/// so the same physical phone always re-hydrates the same cloud profile
/// — no recovery code, no manual restore step. A future Google sign-in
/// layer will replace this with a proper cross-device identity; for now
/// the device id is identity enough (it's not trivially guessable from
/// outside the device).
class Preferences {
  // Write-through cache: best_score / br_wins / player_name are mirrored
  // to SharedPreferences so the game survives offline reloads, but the
  // cloud (`br_profiles`) is the source of truth. At each launch
  // [_hydrateFromCloud] overwrites the local copy with the cloud value
  // (or resets it to defaults when the DB has no row, e.g. after a wipe),
  // and every setter writes to both local + cloud.
  static const _kBestScore = 'best_score';
  static const _kBrWins = 'br_wins';
  static const _kPlayerName = 'player_name';
  static const _kTutorialCompleted = 'tutorial_completed';
  static const _kPlayerId = 'player_id';
  static const _kLocale = 'locale';
  static const _kMuted = 'muted';
  // Legacy key from the recovery-code era (≤ 0010). Cleaned up on the
  // first launch of the device-id-only build so the orphan entry
  // doesn't linger in prefs forever.
  static const _kLegacyRecoveryCode = 'recovery_code';

  static SharedPreferences? _prefs;

  /// Secure storage — used exclusively for the `player_id` so the
  /// identity survives an app uninstall. On iOS this maps to the
  /// Keychain, which is preserved across reinstalls by default
  /// (NSUserDefaults / SharedPreferences are wiped with the app
  /// sandbox). On Android it falls back to EncryptedSharedPreferences
  /// — also in the app sandbox, so reinstalls still produce a fresh
  /// identity there until Google sign-in lands.
  static const _secureStorage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _secureKeyPlayerId = 'jj_player_id';
  static int _bestScore = 0;
  static int _brWins = 0;
  // Onboarding gate: the interactive tutorial overlay watches the
  // solo game state and flips this to true once the player has landed
  // two jumps. Until then the home screen keeps the Battle Royale
  // entry dimmed and re-shows the coaching halo on every solo run.
  static bool _tutorialCompleted = false;
  static String _playerId = '';
  static String _playerName = '';
  static AppLocale _locale = AppLocale.fr;
  static bool _muted = false;

  /// Loads persisted values into memory. Must be awaited before any reads.
  ///
  /// Two-stage profile boot:
  ///   1. Read the local mirror (SharedPreferences) so an offline reload
  ///      still shows last-known stats instead of zeros.
  ///   2. Try to fetch the cloud row via `get_my_profile(player_id)`. If
  ///      the RPC returns a row, the local cache is overwritten (DB wins
  ///      on conflict). If there's no row yet, the local mirror keeps
  ///      its defaults and the next `syncProfileToCloud` will create the
  ///      row. Network failures are swallowed — the local mirror keeps
  ///      the app usable offline.
  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _tutorialCompleted = _prefs?.getBool(_kTutorialCompleted) ?? false;

    // Player_id resolution, in priority order:
    //   1. Secure storage (Keychain on iOS) — survives uninstall.
    //   2. SharedPreferences — for users that pre-date the Keychain
    //      migration, so they keep the same id when they update the
    //      app without uninstalling.
    //   3. Newly derived from IDFV / Android ID (salted-hashed) — or
    //      a random uuid as a last resort.
    // Whichever wins is mirrored back into BOTH stores so the next
    // boot resolves it from the highest priority source.
    final secureId = await _readSecurePlayerId();
    if (secureId != null && secureId.isNotEmpty) {
      _playerId = secureId;
      // Keep the SharedPreferences mirror up to date so older code
      // paths that read from prefs still see the right value.
      _prefs?.setString(_kPlayerId, _playerId);
    } else {
      final prefsId = _prefs?.getString(_kPlayerId);
      if (prefsId != null && prefsId.isNotEmpty) {
        _playerId = prefsId;
      } else {
        _playerId = await _deriveDeviceId() ?? _generatePlayerId();
        _prefs?.setString(_kPlayerId, _playerId);
      }
      // Promote the value into the Keychain so the next uninstall
      // doesn't drop us back to a fresh identity.
      await _writeSecurePlayerId(_playerId);
    }

    // Stage 1: local mirror. Survives offline reloads — the user keeps
    // seeing their last-known stats while we wait for the cloud round
    // trip. Stage 2 (below) overwrites these once the RPC responds.
    _bestScore = _prefs?.getInt(_kBestScore) ?? 0;
    _brWins = _prefs?.getInt(_kBrWins) ?? 0;
    _playerName =
        _prefs?.getString(_kPlayerName) ?? _generatePlayerName();
    _prefs?.setString(_kPlayerName, _playerName);

    final localeName = _prefs?.getString(_kLocale);
    _locale = AppLocale.values.firstWhere(
      (l) => l.name == localeName,
      orElse: () => AppLocale.fr,
    );
    _muted = _prefs?.getBool(_kMuted) ?? false;

    // One-time housekeeping: drop the legacy recovery_code prefs
    // entry from the previous identity model. Harmless if absent.
    if (_prefs?.containsKey(_kLegacyRecoveryCode) ?? false) {
      _prefs?.remove(_kLegacyRecoveryCode);
    }

    // Stage 2: cloud is the source of truth. Overwrites the mirror
    // when a row exists, otherwise leaves the mirror as-is.
    await _hydrateFromCloud();
  }

  /// Pulls `name`, `best_score`, `br_wins` for our identity from the
  /// `br_profiles` table via `get_my_profile`, then overwrites both
  /// the in-memory values AND the local SharedPreferences mirror so
  /// the next offline reload sees the freshest known state.
  ///
  /// Three outcomes:
  ///   • Row returned    → DB wins, local mirror updated.
  ///   • No row returned → fresh device → kick off a [syncProfileToCloud]
  ///                       so the row gets created from the local
  ///                       defaults. Local mirror is not touched.
  ///   • RPC error       → swallowed; local mirror values from stage 1
  ///                       keep the app usable offline.
  static Future<void> _hydrateFromCloud() async {
    try {
      final client = Supabase.instance.client;
      final result = await client.rpc(
        'get_my_profile',
        params: {'p_player_id': _playerId},
      );
      if (result is List && result.isNotEmpty) {
        final row = (result.first as Map).cast<String, dynamic>();
        _playerName = row['name'] as String? ?? _playerName;
        _bestScore = (row['best_score'] as int?) ?? 0;
        _brWins = (row['br_wins'] as int?) ?? 0;
        _prefs
          ?..setString(_kPlayerName, _playerName)
          ..setInt(_kBestScore, _bestScore)
          ..setInt(_kBrWins, _brWins);
      } else {
        // No cloud row yet — first launch on this device. Seed one
        // from the local defaults so the matchmaking lobby / leaderboard
        // can find us on the very next interaction. Awaited (was
        // fire-and-forget) so a transient RPC failure surfaces inside
        // the same try/catch instead of vanishing into the void.
        await syncProfileToCloud();
      }
    } catch (e) {
      // Offline / RPC error: keep the local mirror (already loaded in
      // stage 1 of init). Stats survive the session until we're back
      // online and the next hydrate or sync runs.
      debugPrint('[Preferences] _hydrateFromCloud failed: $e');
    }
  }

  /// Reads `player_id` from the Keychain (iOS) / EncryptedSharedPreferences
  /// (Android). Returns null on any platform error or when the entry is
  /// missing — the caller falls back to the legacy SharedPreferences mirror
  /// then to a freshly derived id.
  static Future<String?> _readSecurePlayerId() async {
    try {
      return await _secureStorage.read(key: _secureKeyPlayerId);
    } catch (e) {
      debugPrint('[Preferences] secure read failed: $e');
      return null;
    }
  }

  /// Persists `player_id` to the Keychain so a future uninstall +
  /// reinstall on the same device picks the same identity back up.
  /// Swallows platform errors — losing the Keychain copy just means
  /// the next install gets a fresh id (the legacy behaviour).
  static Future<void> _writeSecurePlayerId(String value) async {
    try {
      await _secureStorage.write(key: _secureKeyPlayerId, value: value);
    } catch (e) {
      debugPrint('[Preferences] secure write failed: $e');
    }
  }

  static String _generatePlayerId() {
    final rng = Random.secure();
    final hex = StringBuffer();
    for (var i = 0; i < 16; i++) {
      hex.write(rng.nextInt(16).toRadixString(16));
    }
    return hex.toString();
  }

  /// On Android/iOS, derives a stable per-device id from the OS-provided
  /// vendor identifier (Android ID / IDFV). Hashed + salted so we never
  /// expose the raw OS id on the wire or in storage. Returns null on web
  /// (no device-stable id exists by design) and on any platform error,
  /// in which case the caller falls back to a random uuid.
  ///
  /// Stability across reinstalls is the whole point: the IDFV survives
  /// app deletion as long as at least one app from the same vendor is
  /// installed, so a user who removes and re-adds the game reloads the
  /// same cloud profile automatically.
  static Future<String?> _deriveDeviceId() async {
    if (kIsWeb) return null;
    try {
      final info = DeviceInfoPlugin();
      String? raw;
      if (Platform.isAndroid) {
        final a = await info.androidInfo;
        raw = a.id;
      } else if (Platform.isIOS) {
        final i = await info.iosInfo;
        raw = i.identifierForVendor;
      }
      if (raw == null || raw.isEmpty) return null;
      const salt = 'jumping_jack.v1';
      final bytes = utf8.encode('$salt::$raw');
      return sha256.convert(bytes).toString().substring(0, 32);
    } catch (e) {
      debugPrint('[Preferences] _deriveDeviceId failed: $e');
      return null;
    }
  }

  static String _generatePlayerName() {
    final rng = Random.secure();
    return 'JACK_${1000 + rng.nextInt(9000)}';
  }

  // ---- High score ----

  static int get bestScore => _bestScore;

  /// Updates the best score in memory, writes it to the local mirror so
  /// an offline reload preserves the progress, and pushes it to the
  /// cloud (where the next online launch will re-confirm it).
  /// Returns true if [score] beats the previous best.
  static bool updateBestScore(int score) {
    if (score <= _bestScore) return false;
    _bestScore = score;
    _prefs?.setInt(_kBestScore, score);
    unawaited(syncProfileToCloud());
    return true;
  }

  // ---- Battle Royale wins ----

  static int get brWins => _brWins;

  /// Bumps the BR victory counter by 1, mirrors it to the local cache
  /// (so offline reloads keep the count) and syncs to the cloud. The
  /// authoritative increment happens server-side inside `br_end_match`
  /// — this local bump just keeps the UI snappy until the next hydrate.
  static void incrementBrWins() {
    _brWins += 1;
    _prefs?.setInt(_kBrWins, _brWins);
    unawaited(syncProfileToCloud());
  }

  // ---- Tutorial ----

  /// Whether to show the onboarding tutorial when a new game starts.
  /// Reading hits the in-memory cache. Writing updates the cache and
  /// fire-and-forgets a write to disk so the choice survives reloads.
  /// True once the player has landed two jumps in solo with the coaching
  /// layer active. Gates the Battle Royale entry — see [_openBattleRoyale]
  /// in [HomeScreen].
  static bool get tutorialCompleted => _tutorialCompleted;
  static set tutorialCompleted(bool value) {
    _tutorialCompleted = value;
    _prefs?.setBool(_kTutorialCompleted, value);
  }

  // ---- Battle Royale identity ----

  /// Stable device-derived id used as the player's primary key in the
  /// BR matchmaking flow and `br_profiles`. Never displayed.
  static String get playerId => _playerId;

  /// Display name shown to other players (e.g. JACK_4271). Generated once
  /// at first launch; can be changed later from settings.
  ///
  /// The setter is local-only — used during hydration. Explicit user
  /// renames go through [setPlayerNameRemote] which calls the validated
  /// `set_player_name` RPC (blacklist + uniqueness).
  static String get playerName => _playerName;
  static set playerName(String value) {
    final cleaned = value.trim();
    if (cleaned.isEmpty) return;
    _playerName = cleaned;
    _prefs?.setString(_kPlayerName, cleaned);
  }

  /// Validated rename. Calls the `set_player_name` RPC (migration 0010
  /// + 0011) which:
  ///   • trims + length-checks the candidate,
  ///   • rejects any substring on the server's blacklist,
  ///   • rejects names already taken by another player_id
  ///     (case-insensitive).
  ///
  /// On success the local mirror is updated. Failures map the server's
  /// `P0001` message to a specific enum value so the dialog can show a
  /// localised inline error.
  static Future<NameChangeResult> setPlayerNameRemote(String name) async {
    final cleaned = name.trim();
    if (cleaned.isEmpty) return NameChangeResult.empty;
    if (cleaned.length < 2) return NameChangeResult.tooShort;
    try {
      final client = Supabase.instance.client;
      final result = await client.rpc('set_player_name', params: {
        'p_player_id': _playerId,
        'p_name': cleaned,
      });
      final canon = (result is String && result.trim().isNotEmpty)
          ? result.trim()
          : cleaned;
      _playerName = canon;
      _prefs?.setString(_kPlayerName, canon);
      return NameChangeResult.ok;
    } on PostgrestException catch (e) {
      return _mapNameError(e.message);
    } catch (e) {
      debugPrint('[Preferences] setPlayerNameRemote failed: $e');
      return NameChangeResult.error;
    }
  }

  /// Translates the server's exception message (raised with USING
  /// ERRCODE='P0001' inside [set_player_name]) into the matching
  /// [NameChangeResult]. Anything we don't recognise falls back to
  /// [NameChangeResult.error] so the UI shows the generic message
  /// rather than a backend identifier.
  static NameChangeResult _mapNameError(String message) {
    if (message.contains('name_empty')) return NameChangeResult.empty;
    if (message.contains('name_too_short')) return NameChangeResult.tooShort;
    if (message.contains('name_too_long')) return NameChangeResult.tooLong;
    if (message.contains('name_invalid_chars')) {
      return NameChangeResult.invalidChars;
    }
    if (message.contains('name_forbidden')) return NameChangeResult.forbidden;
    if (message.contains('name_taken')) return NameChangeResult.taken;
    debugPrint('[Preferences] unrecognised name error: $message');
    return NameChangeResult.error;
  }

  // ---- Cloud profile sync (Supabase `br_profiles`) ----

  /// Pushes the current name + best_score + br_wins to the cloud
  /// profile row keyed by [playerId]. Server takes max() of the
  /// numeric fields so late writes never regress saved progress.
  ///
  /// `upsert_br_profile` returns the canonical name actually stored
  /// (it auto-suffixes `JACK_xxxx_2`, `_3`, … on the very first
  /// INSERT if another device happened to pick the same name — see
  /// migration 0011 / 0012). We apply that value to the local
  /// mirror so the BR lobby + leaderboard see the deduped identity
  /// from the start.
  ///
  /// Safe to call before Supabase is initialized — the call is
  /// silently skipped if the client isn't ready yet (e.g. very first
  /// boot).
  static Future<void> syncProfileToCloud() async {
    try {
      final client = Supabase.instance.client;
      final result = await client.rpc('upsert_br_profile', params: {
        'p_player_id': _playerId,
        'p_name': _playerName,
        'p_best_score': _bestScore,
        'p_br_wins': _brWins,
      });
      if (result is String) {
        final canon = result.trim();
        if (canon.isNotEmpty && canon != _playerName) {
          _playerName = canon;
          _prefs?.setString(_kPlayerName, canon);
        }
      }
    } catch (e) {
      // Cloud profile is best-effort — local SharedPreferences is the
      // source of truth for this device, so a failed sync is fine.
      debugPrint('[Preferences] syncProfileToCloud failed: $e');
    }
  }

  // ---- Language ----

  static AppLocale get locale => _locale;
  static set locale(AppLocale value) {
    _locale = value;
    _prefs?.setString(_kLocale, value.name);
  }

  // ---- Audio ----

  /// Master mute toggle. When true, music is paused and SFX volume is 0.
  /// Persisted across launches so the choice survives reloads.
  static bool get muted => _muted;
  static set muted(bool value) {
    _muted = value;
    _prefs?.setBool(_kMuted, value);
  }
}
