import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'audio_manager.dart';
import 'preferences.dart';

enum BrPhase {
  joining,
  waiting,
  starting,
  playing,
  finished,
  ended,
  error,
}

class _BotPos {
  const _BotPos({
    required this.x,
    required this.y,
    required this.settledY,
    required this.chargeLevel,
    required this.airborne,
    required this.aimX,
    required this.aimY,
  });
  final double x;
  final double y;
  // Authoritative "last grounded" Y from the source client. Drives the BR
  // camera on remote viewers — without it the camera can't tell how high a
  // bot/remote human has actually climbed (only their lerped live arc).
  final double settledY;
  /// 0..1 charge / wind-up level of the source cube. Drives the squash +
  /// glow animation on remote viewers so other players visibly "prepare"
  /// their jump instead of teleporting from idle straight into the arc.
  final double chargeLevel;
  /// True while the source cube is jumping or falling (i.e. not grounded).
  /// Remote viewers use the transition false→true to trigger the launch
  /// stretch, and true→false to trigger the landing squash.
  final bool airborne;
  /// Normalized aim direction set by the source cube while charging — drives
  /// the body tilt and pupil offset on remote viewers. (0, 0) means "no aim".
  final double aimX;
  final double aimY;
}

class BrPlayer {
  const BrPlayer({
    required this.playerId,
    required this.name,
    required this.slotIndex,
    required this.isBot,
    this.wins = 0,
  });
  final String playerId;
  final String name;
  final int slotIndex;
  final bool isBot;

  /// Lifetime BR victories. For humans this is the value persisted in
  /// `br_profiles` (loaded alongside the room players). For bots it's a
  /// deterministic faux number derived from the bot id so the lobby UI
  /// stays informative without inventing fake "achievements" that vary
  /// across sessions.
  final int wins;
}

class BrPlayerState {
  BrPlayerState({required this.score, required this.alive});
  int score;
  bool alive;
  /// Final placement set when the player dies (or wins). 1 = winner,
  /// `maxPlayers` = first to die. Null while still alive.
  int? placement;
  /// Number of opponents this player has crushed during the match.
  int kills = 0;
  /// How long this player survived after match start. `null` while still
  /// alive — read from the live clock in that case.
  Duration? survivalTime;
}

/// Discrete BR events shown in the kill / event feed (top-left of the BR
/// HUD). Replaces the score display so the player tracks the room story
/// instead of raw points.
enum BrEventType { started, died, killed, lead }

class BrEvent {
  BrEvent({
    required this.type,
    required this.at,
    this.victimName,
    this.victimColor,
    this.killerName,
    this.killerColor,
    this.leaderName,
    this.leaderColor,
  });
  final BrEventType type;
  final DateTime at;
  final String? victimName;
  final int? victimColor; // ARGB int (Flutter Color value)
  final String? killerName;
  final int? killerColor;
  final String? leaderName;
  final int? leaderColor;
}

/// Singleton-style service that owns the Battle Royale match for the
/// duration it lives — survives the lobby → game navigation.
///
/// Sync model: client-authoritative.
///   • Each client owns its own player. It broadcasts its score (10 Hz)
///     and a one-shot `death` event.
///   • The leader (lowest human slot) simulates bots locally and broadcasts
///     their score / death events as if they were normal players.
///
/// The Supabase channel mixes:
///   • Postgres Changes (lobby player list, room status)
///   • Broadcast (in-game score / death events — no DB write)
class BattleRoyaleService extends ChangeNotifier {
  BattleRoyaleService._();

  static BattleRoyaleService? _instance;
  static BattleRoyaleService get instance =>
      _instance ??= BattleRoyaleService._();
  static void resetInstance() {
    _instance?.dispose();
    _instance = null;
  }

  static const int maxPlayers = 5;
  static const Duration countdownDuration = Duration(seconds: 5);
  static const Duration scoreBroadcastInterval = Duration(milliseconds: 250);
  static const Duration heartbeatInterval = Duration(seconds: 5);
  // Stale-broadcast watchdog: when a player's source client stops sending
  // score/position broadcasts, mark them dead so a frozen cube can't block
  // the BR camera or prevent the end condition from triggering.
  static const Duration staleBroadcastTimeout = Duration(seconds: 3);
  static const Duration watchdogInterval = Duration(seconds: 1);
  // Pool of playful pseudonyms for bot opponents — avoids the "BOT_JAUNE"
  // sterile feel and makes solo-vs-bots matches read like a real lobby.
  // Picked at random (without repetition within a match) by the leader
  // when filling empty slots in `_startMatch`.
  static const _botPseudonyms = <String>[
    'Skyhopper', 'Bouncer', 'Pixel', 'Flash', 'Astro', 'Comet',
    'Phoenix', 'Neon', 'Glitch', 'Turbo', 'Vortex', 'Falcon',
    'Storm', 'Mochi', 'Rocket', 'Blaze', 'Chunky', 'Jumper',
    'Magma', 'Wasabi', 'Pretzel', 'Ninja', 'Yoshi92', 'ZipZag',
    'DropKick', 'Zoom', 'Voltz', 'Ruby', 'Echo', 'Shuriken',
    'Pogo', 'KoalaX', 'Bambou', 'Saturn', 'Dash', 'Onyx',
  ];

  final SupabaseClient _supabase = Supabase.instance.client;

  // ---- Lobby state ----
  BrPhase _phase = BrPhase.ended;
  String? _roomId;
  int? _mySlot;
  List<BrPlayer> _players = const [];
  Timer? _countdownTimer;
  Timer? _heartbeatTimer;
  Duration _countdownRemaining = countdownDuration;
  RealtimeChannel? _channel;
  String? _error;

  // ---- In-game state ----
  /// Per-player live state: score + alive flag. Keyed by playerId so we can
  /// merge events for humans + bots in one place.
  final Map<String, BrPlayerState> _playerStates = {};
  /// Latest broadcast position for each bot (filled by the leader).
  /// Non-leader clients render bots from this map.
  final Map<String, _BotPos> _botPositions = {};
  Timer? _scoreTimer;
  Timer? _watchdogTimer;
  /// Wall-clock time of the most recent broadcast (score/position/death)
  /// received for each playerId. Used by the stale-broadcast watchdog so a
  /// disconnected leader's frozen bots can be marked dead instead of
  /// blocking the BR camera and the end-of-match check.
  final Map<String, DateTime> _lastSeenBroadcast = {};
  int _myScore = 0;
  bool _myDead = false;
  bool _spectator = false;
  String? _winnerId;
  int? _myFinalRank;
  /// Guard against double-incrementing `Preferences.brWins`: the match end
  /// can be discovered both locally (via `_checkEndCondition`) and via the
  /// `br_rooms.status='ended'` realtime update. Whichever fires first
  /// records the win and flips this flag so the other path skips it.
  bool _myWinRecorded = false;

  bool _disposed = false;

  // ---- Public getters ----
  BrPhase get phase => _phase;
  String? get roomId => _roomId;
  int? get mySlot => _mySlot;
  List<BrPlayer> get players => List.unmodifiable(_players);
  Duration get countdownRemaining => _countdownRemaining;
  String? get error => _error;
  bool get spectator => _spectator;
  String? get winnerId => _winnerId;
  int? get myFinalRank => _myFinalRank;
  bool get myDead => _myDead;

  /// Number of players still alive.
  int get aliveCount =>
      _playerStates.values.where((s) => s.alive).length;

  /// Number of players currently watching from the bench — i.e. the local
  /// player (if dead) plus every dead bot/remote. Drives the "SPECTATEUR ·
  /// N" badge so the user feels the audience grow as bots fall.
  int get spectatorCount =>
      _playerStates.values.where((s) => !s.alive).length;

  /// Snapshot of every player's live state (score + alive).
  Map<String, BrPlayerState> get playerStates =>
      Map.unmodifiable(_playerStates);

  /// Latest broadcast position for [botId] (null if leader hasn't sent
  /// anything yet). [settledY] is the authoritative last-grounded Y used by
  /// the BR camera to track the room's highest player. [chargeLevel] (0..1)
  /// drives the wind-up squash/glow rendered on remote viewers. [airborne]
  /// flips the face/mouth state and triggers launch/landing pulses on
  /// transitions. [aimX, aimY] is the normalized aim direction (zero when
  /// no aim is active).
  ({
    double x,
    double y,
    double settledY,
    double chargeLevel,
    bool airborne,
    double aimX,
    double aimY,
  })? botPositionFor(String botId) {
    final p = _botPositions[botId];
    if (p == null) return null;
    return (
      x: p.x,
      y: p.y,
      settledY: p.settledY,
      chargeLevel: p.chargeLevel,
      airborne: p.airborne,
      aimX: p.aimX,
      aimY: p.aimY,
    );
  }

  /// True once any player (local human, bot or remote human) has grabbed
  /// the single BR pickup. Sticky for the rest of the match.
  bool get brPickupCollected => _brPickupCollected;
  bool _brPickupCollected = false;

  /// Recent BR events (kill feed) — capped to 5 entries with the newest
  /// last. Old entries roll off. The HUD reads this list and renders the
  /// most recent few with a fade.
  final List<BrEvent> _events = [];
  static const int _maxEvents = 5;
  List<BrEvent> get events => List.unmodifiable(_events);

  /// Tracks the current leader so we can announce changes once.
  String? _currentLeaderId;

  /// Wall-clock instant the playing phase started — used to compute the
  /// per-player survival time for the post-match leaderboard.
  DateTime? _matchStartedAt;
  DateTime? get matchStartedAt => _matchStartedAt;

  /// Live survival time for [pid]: takes the recorded value if the player
  /// has died, otherwise the elapsed time since match start.
  Duration? survivalDurationFor(String pid) {
    final st = _playerStates[pid];
    if (st == null) return null;
    if (st.survivalTime != null) return st.survivalTime;
    final start = _matchStartedAt;
    if (start == null) return null;
    return DateTime.now().difference(start);
  }

  void _pushEvent(BrEvent event) {
    _events.add(event);
    if (_events.length > _maxEvents) {
      _events.removeRange(0, _events.length - _maxEvents);
    }
  }

  /// Slot lookup helper used to colour-code events.
  static const _slotColorValues = <int>[
    0xFFFFC857, // yellow
    0xFF7CC0FF, // cyan
    0xFFFF6E94, // rose
    0xFF7AE091, // vert
    0xFFFFA64C, // orange
  ];
  int _colorForSlot(int slot) =>
      _slotColorValues[slot.clamp(0, _slotColorValues.length - 1)];

  BrPlayer? _playerById(String id) {
    for (final p in _players) {
      if (p.playerId == id) return p;
    }
    return null;
  }

  /// Re-evaluates who's currently leading the room. Emits a `lead` event
  /// if the leader changed (and the new leader is not the previous one).
  void _refreshLeader() {
    String? topId;
    int topScore = -1;
    for (final entry in _playerStates.entries) {
      final st = entry.value;
      if (!st.alive) continue;
      if (st.score > topScore) {
        topScore = st.score;
        topId = entry.key;
      }
    }
    if (topId == null || topId == _currentLeaderId || topScore <= 0) {
      _currentLeaderId = topId ?? _currentLeaderId;
      return;
    }
    _currentLeaderId = topId;
    final p = _playerById(topId);
    if (p == null) return;
    _pushEvent(BrEvent(
      type: BrEventType.lead,
      at: DateTime.now(),
      leaderName: p.name,
      leaderColor: _colorForSlot(p.slotIndex),
    ));
  }

  /// Broadcasts that the local client (or a bot it controls) collected
  /// the BR pickup. Idempotent.
  void notifyBrPickupCollected() {
    if (_brPickupCollected) return;
    _brPickupCollected = true;
    _broadcast('pickup', const <String, dynamic>{});
    _safeNotify();
  }

  /// Sorted snapshot for the post-match leaderboard. Ranked by elimination
  /// order — winner first (placement 1), first-to-die last. Ties (e.g.
  /// players still alive at display time mid-game) fall back to score.
  List<({
    BrPlayer player,
    int score,
    bool alive,
    int? placement,
    int kills,
    Duration? survivalTime,
  })> leaderboardSnapshot() {
    final list = <({
      BrPlayer player,
      int score,
      bool alive,
      int? placement,
      int kills,
      Duration? survivalTime,
    })>[];
    for (final p in _players) {
      final st = _playerStates[p.playerId];
      list.add((
        player: p,
        score: st?.score ?? 0,
        alive: st?.alive ?? true,
        placement: st?.placement,
        kills: st?.kills ?? 0,
        survivalTime: survivalDurationFor(p.playerId),
      ));
    }
    list.sort((a, b) {
      final pa = a.placement ?? 1 << 30;
      final pb = b.placement ?? 1 << 30;
      if (pa != pb) return pa.compareTo(pb);
      return b.score.compareTo(a.score);
    });
    return list;
  }

  /// True when I'm the room leader (lowest *human* slot still in the game).
  bool get isLeader {
    final slot = _mySlot;
    if (slot == null) return false;
    final humanSlots = _players
        .where((p) => !p.isBot)
        .map((p) => p.slotIndex)
        .toList()
      ..sort();
    return humanSlots.isNotEmpty && humanSlots.first == slot;
  }

  // ---- Lobby flow ----

  Future<void> joinMatch() async {
    _resetState();
    _phase = BrPhase.joining;
    _safeNotify();

    // Make sure this device's profile row exists with the current
    // nickname + stats before anyone (including this client) queries the
    // lobby for win counts. Fire-and-forget — a failed sync must not
    // block the join.
    unawaited(Preferences.syncProfileToCloud());

    try {
      final result = await _supabase.rpc('join_or_create_br_room', params: {
        'p_player_id': Preferences.playerId,
        'p_name': Preferences.playerName,
      });
      if (result is! List || result.isEmpty) {
        throw Exception('RPC join_or_create_br_room returned no rows');
      }
      final row = (result.first as Map).cast<String, dynamic>();
      _roomId = row['room_id'] as String;
      _mySlot = row['slot_index'] as int;

      await _subscribeToRoom();
      await _loadPlayers();
      await _initCountdownFromServer();

      _phase = BrPhase.waiting;
      _startCountdown();
      _startHeartbeat();
      _safeNotify();
    } catch (e) {
      _error = e.toString();
      _phase = BrPhase.error;
      _safeNotify();
    }
  }

  Future<void> leaveMatch() async {
    _stopAllTimers();

    // Quit during a live match → broadcast our death (with the same
    // placement logic as a normal death) so we stay in everyone's final
    // leaderboard instead of vanishing.
    if (_phase == BrPhase.playing && !_myDead) {
      // Snapshot leadership before we mark ourselves dead — once we're out
      // of the room, the bots we owned (if any) will freeze on every other
      // client, so we must ship their deaths now.
      final wasLeader = isLeader;
      final me = Preferences.playerId;
      final state = _playerStates[me];
      if (state != null && state.alive) {
        state.placement = aliveCount;
        state.alive = false;
        _broadcastDeath({'pid': me});
        _reportDeathToServer(victimId: me);
      }
      if (wasLeader) {
        for (final p in _players) {
          if (!p.isBot) continue;
          final st = _playerStates[p.playerId];
          if (st == null || !st.alive) continue;
          st.placement = aliveCount;
          st.alive = false;
          st.survivalTime = _matchStartedAt == null
              ? null
              : DateTime.now().difference(_matchStartedAt!);
          _broadcastDeath({'pid': p.playerId});
          _reportDeathToServer(victimId: p.playerId);
        }
      }
    }

    final ch = _channel;
    _channel = null;
    if (ch != null) {
      try {
        await _supabase.removeChannel(ch);
      } catch (_) {}
    }

    // Only free the slot when leaving from the waiting phase. Once the
    // match is playing or finished, keep the row so other clients still
    // see our name in the post-match leaderboard.
    final rid = _roomId;
    final slot = _mySlot;
    if (rid != null && slot != null && _phase == BrPhase.waiting) {
      try {
        // Drop our slot + clean up the empty waiting room atomically via
        // the SECURITY DEFINER RPC — direct DELETE on br_rooms is now
        // blocked by RLS (see migrations/0006_br_anticheat.sql).
        await _supabase.rpc('br_leave_room', params: {
          'p_room_id': rid,
          'p_player_id': Preferences.playerId,
          'p_slot_index': slot,
        });
      } catch (e) {
        debugPrint('[BR] leaveMatch cleanup failed: $e');
      }
    }

    _phase = BrPhase.ended;
    _resetState();
  }

  // ---- In-game public API ----

  /// Called from the game loop whenever the local score updates. The
  /// service throttles broadcasts to [scoreBroadcastInterval].
  void updateMyScore(int score) {
    _myScore = score;
    final me = Preferences.playerId;
    final state = _playerStates[me];
    if (state != null) {
      state.score = score;
      _safeNotify();
    }
  }

  /// Called from the game when the local player dies. Automatically flips
  /// the local UI into spectator mode so the player keeps watching the
  /// remaining survivors play. [killerId] is set when the death came from
  /// a Mario-style crush so the kill feed can render "X killed me".
  void reportMyDeath({String? killerId}) {
    if (_myDead) return;
    _myDead = true;
    _spectator = true;
    final me = Preferences.playerId;
    final state = _playerStates[me];
    if (state != null) {
      state.placement = aliveCount;
      state.alive = false;
      state.survivalTime = _matchStartedAt == null
          ? null
          : DateTime.now().difference(_matchStartedAt!);
    }
    if (killerId != null) {
      final killerState = _playerStates.putIfAbsent(
        killerId,
        () => BrPlayerState(score: 0, alive: true),
      );
      killerState.kills += 1;
    }
    _myFinalRank = state?.placement;
    final payload = <String, dynamic>{'pid': me};
    if (killerId != null) payload['by'] = killerId;
    _broadcastDeath(payload);
    _reportDeathToServer(victimId: me, killerId: killerId);
    // Local feed entry — when killed by a crusher, render "X killed me".
    final myPlayer = _playerById(me);
    final killer = killerId == null ? null : _playerById(killerId);
    if (myPlayer != null) {
      _pushEvent(BrEvent(
        type: killer == null ? BrEventType.died : BrEventType.killed,
        at: DateTime.now(),
        victimName: myPlayer.name,
        victimColor: _colorForSlot(myPlayer.slotIndex),
        killerName: killer?.name,
        killerColor:
            killer == null ? null : _colorForSlot(killer.slotIndex),
      ));
    }
    _refreshLeader();
    _checkEndCondition();
    _safeNotify();
  }

  /// User chose to stay as spectator after dying.
  void becomeSpectator() {
    _spectator = true;
    _safeNotify();
  }

  // ---- Internals: lobby ----

  Future<void> _subscribeToRoom() async {
    final rid = _roomId;
    if (rid == null) return;
    final channel = _supabase.channel('br_room:$rid');
    channel
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'br_room_players',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'room_id',
          value: rid,
        ),
        callback: (_) => _loadPlayers(),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'br_rooms',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: rid,
        ),
        callback: (payload) {
          final status = payload.newRecord['status'] as String?;
          if (status == 'playing' && _phase != BrPhase.playing) {
            _enterPlayingPhase();
          }
          if (status == 'ended' && _phase != BrPhase.finished) {
            _winnerId =
                payload.newRecord['winner_player_id'] as String?;
            _phase = BrPhase.finished;
            _recordLocalWinIfNeeded();
            _safeNotify();
          }
        },
      )
      ..onBroadcast(
        event: 'score',
        callback: (payload) => _onScoreBroadcast(payload),
      )
      ..onBroadcast(
        event: 'death',
        callback: (payload) => _onDeathBroadcast(payload),
      )
      ..onBroadcast(
        event: 'botpos',
        callback: (payload) => _onBotPosBroadcast(payload),
      )
      ..onBroadcast(
        event: 'pickup',
        callback: (_) {
          if (_brPickupCollected) return;
          _brPickupCollected = true;
          _safeNotify();
        },
      );
    channel.subscribe();
    _channel = channel;
  }

  void _onBotPosBroadcast(Map<String, dynamic> payload) {
    final pid = payload['pid'] as String?;
    final x = (payload['x'] as num?)?.toDouble();
    final y = (payload['y'] as num?)?.toDouble();
    if (pid == null || x == null || y == null) return;
    // Older clients (pre-fix) won't send `sy`; fall back to live Y so the
    // camera still tracks them — just less precisely.
    final settledY = (payload['sy'] as num?)?.toDouble() ?? y;
    final chargeLevel =
        ((payload['cl'] as num?)?.toDouble() ?? 0.0).clamp(0.0, 1.0);
    final airborne = (payload['air'] as num?) == 1 ||
        (payload['air'] as bool? ?? false);
    final aimX = (payload['ax'] as num?)?.toDouble() ?? 0.0;
    final aimY = (payload['ay'] as num?)?.toDouble() ?? 0.0;
    _botPositions[pid] = _BotPos(
      x: x,
      y: y,
      settledY: settledY,
      chargeLevel: chargeLevel,
      airborne: airborne,
      aimX: aimX,
      aimY: aimY,
    );
    _lastSeenBroadcast[pid] = DateTime.now();
    _safeNotify();
  }

  /// Called by the leader's local bot AI every animation tick (and by the
  /// local human's own position stream). Updates the authoritative position
  /// so other clients render the cube at the same world coords. [settledY]
  /// is the source-of-truth "last grounded Y" — needed by the BR camera on
  /// non-leader clients, which otherwise can't tell how high anyone has
  /// climbed beyond their lerped live position. [chargeLevel] (0..1) drives
  /// the wind-up squash/glow rendered on remote viewers; pass 0 when the
  /// cube is jumping, falling, or idly resting.
  void broadcastBotPosition(
    String botId,
    double x,
    double y,
    double settledY, {
    double chargeLevel = 0,
    bool airborne = false,
    double aimX = 0,
    double aimY = 0,
  }) {
    final cl = chargeLevel.clamp(0.0, 1.0);
    _botPositions[botId] = _BotPos(
      x: x,
      y: y,
      settledY: settledY,
      chargeLevel: cl,
      airborne: airborne,
      aimX: aimX,
      aimY: aimY,
    );
    _lastSeenBroadcast[botId] = DateTime.now();
    _broadcast('botpos', {
      'pid': botId,
      'x': x,
      'y': y,
      'sy': settledY,
      'cl': cl,
      'air': airborne ? 1 : 0,
      'ax': aimX,
      'ay': aimY,
    });
  }

  Future<void> _loadPlayers() async {
    final rid = _roomId;
    if (rid == null) return;
    try {
      final rows = await _supabase
          .from('br_room_players')
          .select()
          .eq('room_id', rid)
          .order('slot_index');
      final raw = (rows as List).cast<Map>();

      // Pull BR win counts for the human players in one extra query, so
      // the lobby shows "🏆 N" beside each remote player. Bots use a
      // deterministic faux number derived from their playerId to keep
      // the UI populated without lying about real stats.
      final humanIds = raw
          .where((r) => (r['is_bot'] as bool?) != true)
          .map((r) => r['player_id'] as String)
          .toSet()
          .toList(growable: false);
      final Map<String, int> winsByPlayer = {};
      if (humanIds.isNotEmpty) {
        try {
          // Direct SELECT on br_profiles is blocked by RLS (0008) so the
          // anon key can't dump the table. The legitimate lobby need —
          // showing "🏆 N" next to each room member — goes through the
          // SECURITY DEFINER RPC, which only returns (player_id, br_wins)
          // for ids the caller already supplied.
          final profRows = await _supabase.rpc(
            'get_br_wins_for_players',
            params: {'p_player_ids': humanIds},
          );
          if (profRows is List) {
            for (final pr in profRows.cast<Map>()) {
              winsByPlayer[pr['player_id'] as String] =
                  (pr['br_wins'] as int?) ?? 0;
            }
          }
        } catch (e) {
          // Profile table might not exist yet on older deploys — degrade
          // gracefully to 0 wins everywhere rather than failing the lobby.
          debugPrint('[BR] _loadPlayers profiles fetch failed: $e');
        }
      }

      _players = raw
          .map((r) {
            final pid = r['player_id'] as String;
            final isBot = (r['is_bot'] as bool?) ?? false;
            return BrPlayer(
              playerId: pid,
              name: r['name'] as String,
              slotIndex: r['slot_index'] as int,
              isBot: isBot,
              wins: isBot ? _fauxBotWins(pid) : (winsByPlayer[pid] ?? 0),
            );
          })
          .toList(growable: false);

      // Backfill alive state for any player that joined after we entered
      // the playing phase (typically the bots inserted by the leader after
      // the room status flipped). Without this, late arrivals stay absent
      // from `_playerStates` → aliveCount lies → match finishes early.
      if (_phase == BrPhase.playing || _phase == BrPhase.starting) {
        for (final p in _players) {
          _playerStates.putIfAbsent(
            p.playerId,
            () => BrPlayerState(score: 0, alive: true),
          );
        }
      }

      _safeNotify();
      if (_phase == BrPhase.waiting && _players.length >= maxPlayers) {
        _startMatch();
      }
    } catch (e) {
      debugPrint('[BR] _loadPlayers failed: $e');
    }
  }

  /// Deterministic faux BR win count for a bot, derived from its id so
  /// the lobby shows a stable number every time the same bot reappears.
  ///
  /// Uses an FNV-1a byte hash followed by the MurmurHash3 finalizer so
  /// adjacent bot ids (which only differ in their trailing slot digit
  /// 0-4) avalanche into very different buckets — otherwise all five
  /// bots in a room land on near-identical counts and the lobby reads
  /// as obviously synthetic.
  int _fauxBotWins(String botId) {
    var hash = 0x811C9DC5;
    for (final code in botId.codeUnits) {
      hash = ((hash ^ code) * 0x01000193) & 0xFFFFFFFF;
    }
    hash ^= hash >> 16;
    hash = (hash * 0x85EBCA6B) & 0xFFFFFFFF;
    hash ^= hash >> 13;
    hash = (hash * 0xC2B2AE35) & 0xFFFFFFFF;
    hash ^= hash >> 16;
    // 0-87 reads like plausible lifetime BR counts: most casuals sit
    // around 5-30, a handful flex into the 60-80s.
    return hash % 88;
  }

  /// Reads the room's `created_at` and aligns [_countdownRemaining] so a
  /// player joining in the middle of the lobby sees the same countdown as
  /// the player who created the room.
  Future<void> _initCountdownFromServer() async {
    final rid = _roomId;
    if (rid == null) {
      _countdownRemaining = countdownDuration;
      return;
    }
    try {
      final row = await _supabase
          .from('br_rooms')
          .select('created_at')
          .eq('id', rid)
          .single();
      final createdAt = DateTime.parse(row['created_at'] as String);
      final elapsed = DateTime.now().toUtc().difference(createdAt);
      final remaining = countdownDuration - elapsed;
      _countdownRemaining =
          remaining > Duration.zero ? remaining : Duration.zero;
    } catch (e) {
      debugPrint('[BR] _initCountdownFromServer failed: $e');
      _countdownRemaining = countdownDuration;
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    if (_countdownRemaining.inMilliseconds <= 0) {
      // Joined past the deadline — start the match immediately.
      _startMatch();
      return;
    }
    _countdownTimer = Timer.periodic(const Duration(milliseconds: 100), (t) {
      _countdownRemaining -= const Duration(milliseconds: 100);
      if (_countdownRemaining.inMilliseconds <= 0) {
        t.cancel();
        _startMatch();
      } else {
        _safeNotify();
      }
    });
  }

  Future<void> _startMatch() async {
    if (_phase != BrPhase.waiting) return;
    _countdownTimer?.cancel();
    _phase = BrPhase.starting;
    _safeNotify();

    final rid = _roomId;
    if (rid == null) return;

    // Compute the bot rows we want the RPC to seed. Direct
    // br_room_players writes are blocked by tightened RLS (0007), so the
    // bot slots are inserted inside br_start_match's SECURITY DEFINER
    // transaction — atomic with the status flip.
    final taken = _players.map((p) => p.slotIndex).toSet();
    final emptySlots = <int>[
      for (var i = 0; i < maxPlayers; i++)
        if (!taken.contains(i)) i,
    ];
    final pool = List<String>.from(_botPseudonyms)
      ..shuffle(Random(rid.hashCode));
    final botSlots = <int>[];
    final botPlayerIds = <String>[];
    final botNames = <String>[];
    for (var i = 0; i < emptySlots.length; i++) {
      final slot = emptySlots[i];
      botSlots.add(slot);
      botPlayerIds.add('bot_${rid.substring(0, 8)}_$slot');
      botNames.add(pool[i % pool.length]);
    }

    try {
      await _supabase.rpc('br_start_match', params: {
        'p_room_id': rid,
        'p_player_id': Preferences.playerId,
        'p_bot_slots': botSlots,
        'p_bot_player_ids': botPlayerIds,
        'p_bot_names': botNames,
      });
    } catch (e) {
      debugPrint('[BR] br_start_match (likely race, ok): $e');
    }

    // Enter playing phase locally even if the realtime UPDATE callback
    // doesn't fire fast enough (e.g. we were the writer).
    _enterPlayingPhase();
  }

  void _enterPlayingPhase() {
    if (_phase == BrPhase.playing) return;
    _countdownTimer?.cancel();
    _phase = BrPhase.playing;
    _matchStartedAt = DateTime.now();
    _events.clear();
    _currentLeaderId = null;

    // Initialise live state for every player (humans + bots) with score 0.
    _playerStates.clear();
    _lastSeenBroadcast.clear();
    final now = DateTime.now();
    for (final p in _players) {
      _playerStates[p.playerId] = BrPlayerState(score: 0, alive: true);
      // Seed liveness with match-start so the watchdog only fires once a
      // player has had time to send their first broadcast.
      _lastSeenBroadcast[p.playerId] = now;
    }

    _scoreTimer = Timer.periodic(scoreBroadcastInterval, (_) {
      if (_myDead) return;
      _broadcast('score', {
        'pid': Preferences.playerId,
        's': _myScore,
      });
    });

    _watchdogTimer = Timer.periodic(watchdogInterval, (_) {
      _runStaleWatchdog();
    });

    _safeNotify();
  }

  /// Watchdog: kill any opponent whose source client has stopped broadcasting
  /// for [staleBroadcastTimeout]. Without this, a leader who closes the app
  /// (or loses connection) freezes its bots in mid-air on every other client.
  /// The frozen cubes stay "alive", lock the BR camera onto them, and prevent
  /// `_checkEndCondition` from declaring a winner.
  void _runStaleWatchdog() {
    if (_phase != BrPhase.playing) return;
    final me = Preferences.playerId;
    final now = DateTime.now();
    final victims = <String>[];
    for (final p in _players) {
      if (p.playerId == me) continue;
      final state = _playerStates[p.playerId];
      if (state == null || !state.alive) continue;
      final lastSeen = _lastSeenBroadcast[p.playerId];
      if (lastSeen == null) continue;
      if (now.difference(lastSeen) <= staleBroadcastTimeout) continue;
      victims.add(p.playerId);
    }
    for (final pid in victims) {
      final state = _playerStates[pid];
      if (state == null || !state.alive) continue;
      state.placement = aliveCount;
      state.alive = false;
      state.survivalTime = _matchStartedAt == null
          ? null
          : DateTime.now().difference(_matchStartedAt!);
      _broadcastDeath({'pid': pid});
      // Server-side: accepted for bots (the typical case when a leader
      // disconnects), rejected for humans (the disconnected human's
      // stale heartbeat will eventually let `br_end_match` skip them).
      _reportDeathToServer(victimId: pid);
      final victim = _playerById(pid);
      if (victim != null) {
        _pushEvent(BrEvent(
          type: BrEventType.died,
          at: DateTime.now(),
          victimName: victim.name,
          victimColor: _colorForSlot(victim.slotIndex),
        ));
      }
    }
    if (victims.isNotEmpty) {
      _refreshLeader();
      _safeNotify();
      _checkEndCondition();
    }
  }

  // ---- Bot reporting (each client locally simulates its own bots) ----

  /// Called by the leader's local bot AI when a bot's score changes.
  /// Updates local state AND broadcasts so other clients (which only render
  /// the bot from broadcasts) stay in sync.
  void reportBotScore(String botId, int score) {
    final state = _playerStates.putIfAbsent(
      botId,
      () => BrPlayerState(score: 0, alive: true),
    );
    if (!state.alive) return;
    if (score > state.score) {
      state.score = score;
      _safeNotify();
      _broadcast('score', {'pid': botId, 's': score});
    }
  }

  /// Called by the leader's local bot AI when a bot dies. Only the leader
  /// broadcasts; other clients update their state from the broadcast.
  void reportBotDeath(String botId) {
    final state = _playerStates.putIfAbsent(
      botId,
      () => BrPlayerState(score: 0, alive: true),
    );
    if (!state.alive) return;
    state.placement = aliveCount;
    state.alive = false;
    state.survivalTime = _matchStartedAt == null
        ? null
        : DateTime.now().difference(_matchStartedAt!);
    if (isLeader) {
      _broadcastDeath({'pid': botId});
      _reportDeathToServer(victimId: botId);
    }
    // Push the BR feed event locally too — the leader is the one running
    // the death detection here, and its own echo of the broadcast hits
    // the alive-check early-return before any event is recorded.
    final victim = _playerById(botId);
    if (victim != null) {
      _pushEvent(BrEvent(
        type: BrEventType.died,
        at: DateTime.now(),
        victimName: victim.name,
        victimColor: _colorForSlot(victim.slotIndex),
      ));
    }
    _refreshLeader();
    _safeNotify();
    _checkEndCondition();
  }

  /// Any client can claim a Mario-style crush kill on a target cube (bot or
  /// remote human). [killerId] identifies the crusher so the feed can
  /// render "X killed Y". Defaults to the local player if omitted.
  ///
  /// IMPORTANT: the killer credit happens *before* the alive-check, because
  /// in the local-player crush path the bot's `killByCamera()` already
  /// flipped its state to dead by the time we get here. Without the early
  /// credit the kill would silently disappear.
  void broadcastCrushKill(String targetId, {String? killerId}) {
    final killer = killerId ?? Preferences.playerId;
    final killerState = _playerStates.putIfAbsent(
      killer,
      () => BrPlayerState(score: 0, alive: true),
    );
    killerState.kills += 1;

    final state = _playerStates.putIfAbsent(
      targetId,
      () => BrPlayerState(score: 0, alive: true),
    );
    state.placement = aliveCount;
    state.alive = false;
    state.survivalTime = _matchStartedAt == null
        ? null
        : DateTime.now().difference(_matchStartedAt!);
    // Always broadcast so other clients also score the kill correctly.
    _broadcastDeath({'pid': targetId, 'by': killer});
    // Record the death server-side too. The server enforces who's
    // allowed to flag who, so this is a no-op when the target is a
    // remote human (their own client will report); for bot victims it's
    // accepted from any room human, which is what we want for crushes.
    _reportDeathToServer(victimId: targetId, killerId: killer);
    final victim = _playerById(targetId);
    final crusher = _playerById(killer);
    if (victim != null) {
      _pushEvent(BrEvent(
        type: BrEventType.killed,
        at: DateTime.now(),
        victimName: victim.name,
        victimColor: _colorForSlot(victim.slotIndex),
        killerName: crusher?.name,
        killerColor:
            crusher == null ? null : _colorForSlot(crusher.slotIndex),
      ));
    }
    _refreshLeader();
    _safeNotify();
    _checkEndCondition();
  }

  // ---- Internals: broadcast handlers ----

  /// Sends a `death` event with idempotent retries to survive single
  /// realtime packet losses. Supabase Realtime broadcasts are at-most-once,
  /// so a single dropped death packet leaves the victim "alive" on remote
  /// clients — frozen in place (no more position broadcasts come) but still
  /// counted in `_refreshLeader()`, which then awards them phantom leads
  /// every time another player's score moves. Receivers early-return on
  /// already-dead state, so triple delivery is safe.
  void _broadcastDeath(Map<String, dynamic> payload) {
    _broadcast('death', payload);
    Future<void>.delayed(const Duration(milliseconds: 90), () {
      if (_disposed) return;
      _broadcast('death', payload);
    });
    Future<void>.delayed(const Duration(milliseconds: 280), () {
      if (_disposed) return;
      _broadcast('death', payload);
    });
  }

  /// Records a death in the server-side `br_player_deaths` table. The
  /// row is what gates the alive-count check inside the `br_end_match`
  /// SECURITY DEFINER RPC — without it, a cheater could call br_end_match
  /// against still-living opponents and forge a win.
  ///
  /// Fire-and-forget on purpose: the realtime `death` broadcast carries
  /// the gameplay reaction (UI, kill feed, audio); this call only needs
  /// to land before whoever ends up being the winner calls br_end_match.
  /// The RPC is idempotent and rejects spoof attempts (only the victim
  /// can flag a human dead — bots can be flagged by any room human).
  void _reportDeathToServer({
    required String victimId,
    String? killerId,
  }) {
    final rid = _roomId;
    if (rid == null) return;
    final params = <String, dynamic>{
      'p_room_id': rid,
      'p_dead_player_id': victimId,
      'p_reporter_player_id': Preferences.playerId,
    };
    if (killerId != null) params['p_killer_player_id'] = killerId;
    unawaited(_supabase.rpc('br_report_death', params: params).then(
      (_) {},
      onError: (e) => debugPrint('[BR] br_report_death failed: $e'),
    ));
  }

  void _broadcast(String event, Map<String, dynamic> payload) {
    final ch = _channel;
    if (ch == null) return;
    try {
      ch.sendBroadcastMessage(event: event, payload: payload);
    } catch (e) {
      debugPrint('[BR] broadcast $event failed: $e');
    }
  }

  void _onScoreBroadcast(Map<String, dynamic> payload) {
    final pid = payload['pid'] as String?;
    final score = payload['s'];
    if (pid == null || score is! int) return;
    if (pid == Preferences.playerId) return; // ignore my own echo
    final state = _playerStates.putIfAbsent(
      pid,
      () => BrPlayerState(score: 0, alive: true),
    );
    state.score = score;
    _lastSeenBroadcast[pid] = DateTime.now();
    _refreshLeader();
    _safeNotify();
  }

  void _onDeathBroadcast(Map<String, dynamic> payload) {
    final pid = payload['pid'] as String?;
    if (pid == null) return;
    if (pid == Preferences.playerId) return;
    final state = _playerStates.putIfAbsent(
      pid,
      () => BrPlayerState(score: 0, alive: true),
    );
    if (!state.alive) return;
    state.placement = aliveCount; // placement = alive at this moment
    state.alive = false;
    state.survivalTime = _matchStartedAt == null
        ? null
        : DateTime.now().difference(_matchStartedAt!);
    // Audio cue: a thud whenever any non-local player dies, so the action
    // stays readable even off-screen.
    AudioManager.brDeath();
    // Push the BR event for the kill feed.
    final victim = _playerById(pid);
    final killerId = payload['by'] as String?;
    final killer = killerId == null ? null : _playerById(killerId);
    // Credit the kill to the killer.
    if (killerId != null) {
      final killerState = _playerStates.putIfAbsent(
        killerId,
        () => BrPlayerState(score: 0, alive: true),
      );
      killerState.kills += 1;
    }
    if (victim != null) {
      _pushEvent(BrEvent(
        type: killer == null ? BrEventType.died : BrEventType.killed,
        at: DateTime.now(),
        victimName: victim.name,
        victimColor: _colorForSlot(victim.slotIndex),
        killerName: killer?.name,
        killerColor:
            killer == null ? null : _colorForSlot(killer.slotIndex),
      ));
    }
    // Re-evaluate leadership since dead players no longer count.
    _refreshLeader();
    _safeNotify();
    _checkEndCondition();
  }

  void _checkEndCondition() {
    if (_phase != BrPhase.playing) return;
    // Don't declare a winner until the full 5-slot roster is tracked —
    // otherwise a bot row that hasn't been loaded yet would let us finish
    // on aliveCount==0 the moment the local player dies.
    if (_playerStates.length < maxPlayers) return;
    final alive = _playerStates.entries.where((e) => e.value.alive).toList();
    if (alive.length <= 1) {
      // The lone survivor (if any) is the winner — placement = 1.
      // Freeze their survival time at the exact moment the match ends so
      // the leaderboard shows the same duration as the runner-up (instead
      // of "now - matchStart" which keeps growing while the user reads
      // the result screen).
      if (alive.length == 1) {
        alive.first.value.placement = 1;
        if (_matchStartedAt != null) {
          alive.first.value.survivalTime =
              DateTime.now().difference(_matchStartedAt!);
        }
      }
      _winnerId = alive.isEmpty ? null : alive.first.key;
      _phase = BrPhase.finished;
      _stopAllTimers();
      _recordLocalWinIfNeeded();
      _safeNotify();
      if (isLeader) _markRoomEnded();
    }
  }

  /// Bumps `Preferences.brWins` exactly once if the local player is the
  /// declared winner. Guarded by [_myWinRecorded] so both end-of-match
  /// code paths (local detection + realtime room update) can safely call
  /// it without double-counting.
  void _recordLocalWinIfNeeded() {
    if (_myWinRecorded) return;
    if (_winnerId != Preferences.playerId) return;
    _myWinRecorded = true;
    Preferences.incrementBrWins();
  }

  /// Public, idempotent commit used by the BR result overlay as a final
  /// safety net before the user navigates back to the home screen. The
  /// in-service paths already call [_recordLocalWinIfNeeded] from both
  /// the local end-condition check and the realtime `status='ended'`
  /// callback, but a race (e.g. the user dismisses the result before the
  /// realtime broadcast arrives) could leave the local increment pending.
  /// This method closes that window — `[_myWinRecorded]` makes the call
  /// a no-op if the increment already happened.
  void commitFinalWinIfNeeded() => _recordLocalWinIfNeeded();

  Future<void> _markRoomEnded() async {
    final rid = _roomId;
    if (rid == null) return;
    // br_end_match (see migrations/0006 + 0007) validates caller, winner,
    // min match duration, AND that every non-winner has either a death
    // record or a stale heartbeat. The last condition can briefly fail
    // when this client receives the last death broadcast before the
    // dying client's `br_report_death` lands in the DB (single network
    // hop race). Retry with backoff so the call doesn't permanently fail
    // on a sub-second timing gap.
    const delays = <int>[0, 250, 500, 750, 1000];
    for (var attempt = 0; attempt < delays.length; attempt++) {
      if (delays[attempt] > 0) {
        await Future<void>.delayed(Duration(milliseconds: delays[attempt]));
      }
      if (_disposed) return;
      try {
        await _supabase.rpc('br_end_match', params: {
          'p_room_id': rid,
          'p_player_id': Preferences.playerId,
          'p_winner_player_id': _winnerId,
        });
        return;
      } catch (e) {
        debugPrint(
          '[BR] br_end_match attempt ${attempt + 1}/${delays.length} '
          'failed: $e',
        );
      }
    }
  }

  // ---- House-keeping ----

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) async {
      final rid = _roomId;
      if (rid == null) return;
      try {
        await _supabase.rpc('br_heartbeat', params: {
          'p_room_id': rid,
          'p_player_id': Preferences.playerId,
        });
      } catch (e) {
        debugPrint('[BR] heartbeat failed: $e');
      }
    });
  }

  void _stopAllTimers() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _scoreTimer?.cancel();
    _scoreTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
  }

  void _resetState() {
    _stopAllTimers();
    _roomId = null;
    _mySlot = null;
    _players = const [];
    _countdownRemaining = countdownDuration;
    _error = null;
    _playerStates.clear();
    _myScore = 0;
    _myDead = false;
    _spectator = false;
    _winnerId = null;
    _myFinalRank = null;
    _myWinRecorded = false;
    _botPositions.clear();
    _lastSeenBroadcast.clear();
    _brPickupCollected = false;
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopAllTimers();
    super.dispose();
  }
}

