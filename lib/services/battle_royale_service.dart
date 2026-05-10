import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  const _BotPos({required this.x, required this.y});
  final double x;
  final double y;
}

class BrPlayer {
  const BrPlayer({
    required this.playerId,
    required this.name,
    required this.slotIndex,
    required this.isBot,
  });
  final String playerId;
  final String name;
  final int slotIndex;
  final bool isBot;
}

class BrPlayerState {
  BrPlayerState({required this.score, required this.alive});
  int score;
  bool alive;
  /// Final placement set when the player dies (or wins). 1 = winner,
  /// `maxPlayers` = first to die. Null while still alive.
  int? placement;
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
  static const Duration countdownDuration = Duration(seconds: 10);
  static const Duration scoreBroadcastInterval = Duration(milliseconds: 250);
  static const Duration heartbeatInterval = Duration(seconds: 5);
  static const _botColors = ['BLEU', 'ROUGE', 'VERT', 'ROSE', 'CYAN'];

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
  int _myScore = 0;
  bool _myDead = false;
  bool _spectator = false;
  String? _winnerId;
  int? _myFinalRank;

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

  /// Snapshot of every player's live state (score + alive).
  Map<String, BrPlayerState> get playerStates =>
      Map.unmodifiable(_playerStates);

  /// Latest broadcast position for [botId] (null if leader hasn't sent
  /// anything yet).
  ({double x, double y})? botPositionFor(String botId) {
    final p = _botPositions[botId];
    if (p == null) return null;
    return (x: p.x, y: p.y);
  }

  /// True once any player (local human, bot or remote human) has grabbed
  /// the single BR pickup. Sticky for the rest of the match.
  bool get brPickupCollected => _brPickupCollected;
  bool _brPickupCollected = false;

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
  List<({BrPlayer player, int score, bool alive, int? placement})>
      leaderboardSnapshot() {
    final list =
        <({BrPlayer player, int score, bool alive, int? placement})>[];
    for (final p in _players) {
      final st = _playerStates[p.playerId];
      list.add((
        player: p,
        score: st?.score ?? 0,
        alive: st?.alive ?? true,
        placement: st?.placement,
      ));
    }
    list.sort((a, b) {
      // Primary key: placement ascending (winner = 1).
      final pa = a.placement ?? 1 << 30;
      final pb = b.placement ?? 1 << 30;
      if (pa != pb) return pa.compareTo(pb);
      // Tiebreak (typically only matters mid-match for live leaderboard):
      // higher score ranks above.
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
      final me = Preferences.playerId;
      final state = _playerStates[me];
      if (state != null && state.alive) {
        state.placement = aliveCount;
        state.alive = false;
        _broadcast('death', {'pid': me});
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
        await _supabase
            .from('br_room_players')
            .delete()
            .eq('room_id', rid)
            .eq('slot_index', slot);
        // If I was the last player, delete the room itself so future
        // matchmaking doesn't waste time pairing into an empty lobby.
        final remaining = await _supabase
            .from('br_room_players')
            .select('player_id')
            .eq('room_id', rid);
        if ((remaining as List).isEmpty) {
          await _supabase.from('br_rooms').delete().eq('id', rid);
        }
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
  /// remaining survivors play.
  void reportMyDeath() {
    if (_myDead) return;
    _myDead = true;
    _spectator = true;
    final me = Preferences.playerId;
    final state = _playerStates[me];
    if (state != null) {
      // Placement = number of players still alive at this exact moment
      // (myself included before flipping). 1st to die → maxPlayers, last
      // alive → 1.
      state.placement = aliveCount;
      state.alive = false;
    }
    _myFinalRank = state?.placement;
    _broadcast('death', {'pid': me});
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
    _botPositions[pid] = _BotPos(x: x, y: y);
    _safeNotify();
  }

  /// Called by the leader's local bot AI every animation tick. Updates the
  /// authoritative position so other clients render the bot at the same
  /// world coords as the leader.
  void broadcastBotPosition(String botId, double x, double y) {
    _botPositions[botId] = _BotPos(x: x, y: y);
    _broadcast('botpos', {'pid': botId, 'x': x, 'y': y});
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
      _players = (rows as List)
          .map((r) => BrPlayer(
                playerId: r['player_id'] as String,
                name: r['name'] as String,
                slotIndex: r['slot_index'] as int,
                isBot: (r['is_bot'] as bool?) ?? false,
              ))
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

    final taken = _players.map((p) => p.slotIndex).toSet();
    final emptySlots = <int>[
      for (var i = 0; i < maxPlayers; i++)
        if (!taken.contains(i)) i,
    ];
    if (emptySlots.isNotEmpty) {
      final botRows = emptySlots
          .map((slot) => {
                'room_id': rid,
                'slot_index': slot,
                'player_id': 'bot_${rid.substring(0, 8)}_$slot',
                'name': 'BOT_${_botColors[slot % _botColors.length]}',
                'is_bot': true,
              })
          .toList();
      try {
        await _supabase
            .from('br_room_players')
            .upsert(botRows, onConflict: 'room_id,slot_index');
      } catch (e) {
        debugPrint('[BR] bot upsert (likely race, ok): $e');
      }
    }

    try {
      await _supabase
          .from('br_rooms')
          .update({
            'status': 'playing',
            'started_at': DateTime.now().toIso8601String(),
          })
          .eq('id', rid)
          .eq('status', 'waiting');
    } catch (e) {
      debugPrint('[BR] start update (likely race, ok): $e');
    }

    // Enter playing phase locally even if the realtime UPDATE callback
    // doesn't fire fast enough (e.g. we were the writer).
    _enterPlayingPhase();
  }

  void _enterPlayingPhase() {
    if (_phase == BrPhase.playing) return;
    _countdownTimer?.cancel();
    _phase = BrPhase.playing;

    // Initialise live state for every player (humans + bots) with score 0.
    _playerStates.clear();
    for (final p in _players) {
      _playerStates[p.playerId] = BrPlayerState(score: 0, alive: true);
    }

    _scoreTimer = Timer.periodic(scoreBroadcastInterval, (_) {
      if (_myDead) return;
      _broadcast('score', {
        'pid': Preferences.playerId,
        's': _myScore,
      });
    });

    _safeNotify();
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
    if (isLeader) {
      _broadcast('death', {'pid': botId});
    }
    _safeNotify();
    _checkEndCondition();
  }

  // ---- Internals: broadcast handlers ----

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
      if (alive.length == 1) {
        alive.first.value.placement = 1;
      }
      _winnerId = alive.isEmpty ? null : alive.first.key;
      _phase = BrPhase.finished;
      _stopAllTimers();
      if (_winnerId == Preferences.playerId) {
        Preferences.incrementBrWins();
      }
      _safeNotify();
      if (isLeader) _markRoomEnded();
    }
  }

  Future<void> _markRoomEnded() async {
    final rid = _roomId;
    if (rid == null) return;
    try {
      await _supabase
          .from('br_rooms')
          .update({
            'status': 'ended',
            'ended_at': DateTime.now().toIso8601String(),
            'winner_player_id': _winnerId,
          })
          .eq('id', rid)
          .neq('status', 'ended');
    } catch (_) {}
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
    _botPositions.clear();
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

