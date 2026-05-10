import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../i18n/i18n.dart';

/// User preferences. Persisted across launches via [SharedPreferences]:
/// high score, tutorial toggle, and the auto-generated Battle Royale
/// nickname (so other players see the same JACK_xxxx name session after
/// session).
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
  static const _kShowTutorial = 'show_tutorial';
  static const _kPlayerId = 'player_id';
  static const _kRecoveryCode = 'recovery_code';
  static const _kLocale = 'locale';
  static const _kMuted = 'muted';

  static SharedPreferences? _prefs;
  static int _bestScore = 0;
  static int _brWins = 0;
  // Tutorial shows on first solo run. Once dismissed via "Don't show
  // again", it stays dismissed forever (no re-enable UI in this app).
  static bool _showTutorial = true;
  static String _playerId = '';
  static String _playerName = '';
  static String _recoveryCode = '';
  static AppLocale _locale = AppLocale.fr;
  // Mute is ON by default so the app doesn't blast audio on first load.
  static bool _muted = true;

  /// Loads persisted values into memory. Must be awaited before any reads.
  ///
  /// Two-stage profile boot:
  ///   1. Read the local mirror (SharedPreferences) so an offline reload
  ///      still shows last-known stats instead of zeros.
  ///   2. Try to fetch the cloud row via `redeem_recovery_code`. If the
  ///      RPC succeeds it overwrites the local cache (DB wins on
  ///      conflict); if it returns no row (fresh DB, fresh device) we
  ///      reset the cache to defaults and upsert a fresh profile.
  ///      Network failures are swallowed — the local mirror keeps us
  ///      functional until the next online launch.
  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _showTutorial = _prefs?.getBool(_kShowTutorial) ?? true;

    final storedId = _prefs?.getString(_kPlayerId);
    if (storedId != null && storedId.isNotEmpty) {
      _playerId = storedId;
    } else {
      _playerId = await _deriveDeviceId() ?? _generatePlayerId();
      _prefs?.setString(_kPlayerId, _playerId);
    }

    final storedCode = _prefs?.getString(_kRecoveryCode);
    if (storedCode != null && storedCode.isNotEmpty) {
      _recoveryCode = storedCode;
    } else {
      _recoveryCode = _generateRecoveryCode();
      _prefs?.setString(_kRecoveryCode, _recoveryCode);
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
    _muted = _prefs?.getBool(_kMuted) ?? true;

    // Stage 2: cloud is the source of truth. Overwrites the mirror on
    // success, or resets it on "no row" so a DB wipe is reflected on
    // the very next launch.
    await _hydrateFromCloud();
  }

  /// Pulls `name`, `best_score`, `br_wins` for our identity from the
  /// `br_profiles` table via `redeem_recovery_code`, then overwrites
  /// both the in-memory values AND the local SharedPreferences mirror
  /// so the next offline reload sees the freshest known state.
  ///
  /// Three outcomes:
  ///   • Row returned    → DB wins, local mirror updated.
  ///   • No row returned → treated as "fresh start" (e.g. cloud wipe):
  ///                       in-memory values reset to defaults, mirror
  ///                       cleared, and an upsert creates a new row.
  ///   • RPC error       → swallowed; local mirror values from stage 1
  ///                       keep the app usable offline.
  static Future<void> _hydrateFromCloud() async {
    try {
      final client = Supabase.instance.client;
      final result = await client.rpc(
        'redeem_recovery_code',
        params: {'p_code': _recoveryCode},
      );
      if (result is List && result.isNotEmpty) {
        final row = (result.first as Map).cast<String, dynamic>();
        _playerId = row['player_id'] as String? ?? _playerId;
        _playerName = row['name'] as String? ?? _playerName;
        _bestScore = (row['best_score'] as int?) ?? 0;
        _brWins = (row['br_wins'] as int?) ?? 0;
        _prefs
          ?..setString(_kPlayerId, _playerId)
          ..setString(_kPlayerName, _playerName)
          ..setInt(_kBestScore, _bestScore)
          ..setInt(_kBrWins, _brWins);
      } else {
        // Cloud has no row for this code — most likely a DB wipe. Roll
        // the local mirror back to defaults so the user doesn't keep
        // seeing stale stats, then upsert to create a fresh row.
        _bestScore = 0;
        _brWins = 0;
        _playerName = _generatePlayerName();
        _prefs
          ?..setInt(_kBestScore, 0)
          ..setInt(_kBrWins, 0)
          ..setString(_kPlayerName, _playerName);
        unawaited(syncProfileToCloud());
      }
    } catch (e) {
      // Offline / RPC error: keep the local mirror (already loaded in
      // stage 1 of init). Stats survive the session until we're back
      // online and the next hydrate or sync runs.
      debugPrint('[Preferences] _hydrateFromCloud failed: $e');
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
  /// Salting with the app namespace means two different apps from the
  /// same vendor produce different ids — important if this game ever
  /// ships alongside another title from the same studio.
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

  /// Human-readable recovery code: `JJ-XXXX-XXXX` over a 32-char
  /// alphabet that excludes ambiguous glyphs (0/O, 1/I/L). ~40 bits
  /// of entropy per code — collision-resistant at any realistic
  /// player count without making the user type 30 chars.
  static String _generateRecoveryCode() {
    const alphabet = '23456789ABCDEFGHJKMNPQRSTUVWXYZ'; // no 0/1/I/L/O
    final rng = Random.secure();
    String block() {
      final sb = StringBuffer();
      for (var i = 0; i < 4; i++) {
        sb.write(alphabet[rng.nextInt(alphabet.length)]);
      }
      return sb.toString();
    }

    return 'JJ-${block()}-${block()}';
  }

  /// True when [code] matches the `JJ-XXXX-XXXX` shape and uses only
  /// alphabet characters. Hyphens are optional in the input — the
  /// caller usually canonicalizes first via [canonicalizeRecoveryCode].
  static bool isValidRecoveryCode(String code) {
    final canon = canonicalizeRecoveryCode(code);
    return RegExp(r'^JJ-[23456789ABCDEFGHJKMNPQRSTUVWXYZ]{4}'
            r'-[23456789ABCDEFGHJKMNPQRSTUVWXYZ]{4}$')
        .hasMatch(canon);
  }

  /// Normalises user-typed input: uppercases, strips whitespace, and
  /// re-inserts the standard hyphens so `jj7k2pa9xb`, `JJ 7K2P A9XB`
  /// and `JJ-7K2P-A9XB` all canonicalize to the same string.
  static String canonicalizeRecoveryCode(String input) {
    final cleaned = input.toUpperCase().replaceAll(RegExp(r'[^0-9A-Z]'), '');
    if (cleaned.length == 10 && cleaned.startsWith('JJ')) {
      return 'JJ-${cleaned.substring(2, 6)}-${cleaned.substring(6, 10)}';
    }
    return input.trim().toUpperCase();
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
  static bool get showTutorial => _showTutorial;
  static set showTutorial(bool value) {
    _showTutorial = value;
    _prefs?.setBool(_kShowTutorial, value);
  }

  // ---- Battle Royale identity ----

  /// Stable random ID for this device — used as the player's primary key
  /// in the BR matchmaking and presence flow. Never displayed.
  static String get playerId => _playerId;

  /// Display name shown to other players (e.g. JACK_4271). Generated once
  /// at first launch; can be changed later from settings.
  static String get playerName => _playerName;
  static set playerName(String value) {
    final cleaned = value.trim();
    if (cleaned.isEmpty) return;
    _playerName = cleaned;
    _prefs?.setString(_kPlayerName, cleaned);
    unawaited(syncProfileToCloud());
  }

  // ---- Recovery code ----

  /// `JJ-XXXX-XXXX` code that lets the user move their profile to
  /// another browser / new install. Read-only after the first launch.
  static String get recoveryCode => _recoveryCode;

  // ---- Cloud profile sync (Supabase `br_profiles`) ----

  /// Pushes the current name + best_score + br_wins + recovery_code to
  /// the cloud profile row keyed by [playerId]. Server takes max() of
  /// the numeric fields so late writes never regress saved progress,
  /// and the recovery code is sticky (never overwritten) once set.
  ///
  /// Safe to call before Supabase is initialized — the call is silently
  /// skipped if the client isn't ready yet (e.g. very first boot).
  static Future<void> syncProfileToCloud() async {
    try {
      final client = Supabase.instance.client;
      await client.rpc('upsert_br_profile', params: {
        'p_player_id': _playerId,
        'p_name': _playerName,
        'p_best_score': _bestScore,
        'p_br_wins': _brWins,
        'p_recovery_code': _recoveryCode,
      });
    } catch (e) {
      // Cloud profile is best-effort — local SharedPreferences is the
      // source of truth for this device, so a failed sync is fine.
      debugPrint('[Preferences] syncProfileToCloud failed: $e');
    }
  }

  /// Calls the `redeem_recovery_code` RPC and, if the code matches a
  /// profile, overwrites the local Preferences (playerId, name, scores)
  /// with the cloud-of-record values. Returns true on success so the UI
  /// can confirm; false otherwise.
  ///
  /// Local progress on the device before the restore is *not* merged —
  /// the recovered profile replaces it. The recovery code itself is
  /// updated to the recovered one so subsequent restores from this
  /// device keep pointing to the same cloud row.
  static Future<bool> restoreFromRecoveryCode(String code) async {
    final canon = canonicalizeRecoveryCode(code);
    if (!isValidRecoveryCode(canon)) return false;
    try {
      final client = Supabase.instance.client;
      final result = await client.rpc(
        'redeem_recovery_code',
        params: {'p_code': canon},
      );
      if (result is! List || result.isEmpty) return false;
      final row = (result.first as Map).cast<String, dynamic>();
      _playerId = row['player_id'] as String;
      _playerName = row['name'] as String;
      _bestScore = (row['best_score'] as int?) ?? 0;
      _brWins = (row['br_wins'] as int?) ?? 0;
      _recoveryCode = canon;
      // Mirror the recovered profile into the local cache so the next
      // (potentially offline) reload keeps the restored stats.
      _prefs
        ?..setString(_kPlayerId, _playerId)
        ..setString(_kPlayerName, _playerName)
        ..setInt(_kBestScore, _bestScore)
        ..setInt(_kBrWins, _brWins)
        ..setString(_kRecoveryCode, _recoveryCode);
      return true;
    } catch (e) {
      debugPrint('[Preferences] restoreFromRecoveryCode failed: $e');
      return false;
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
