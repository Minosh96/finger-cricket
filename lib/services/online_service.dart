import 'dart:async';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import '../firebase_options.dart';
import '../game/online_engine.dart';
import '../models/room.dart';

class OnlineException implements Exception {
  final String message;
  OnlineException(this.message);
  @override
  String toString() => message;
}

/// Firebase Realtime Database + Anonymous Auth backend (100% Spark free plan).
/// Security rules enforce write-once moves, server deadlines, and anti-peek reads;
/// RTDB transactions ensure each ball is resolved atomically and never scored twice.
class OnlineService {
  OnlineService._();
  static final OnlineService instance = OnlineService._();

  final Random _rng = Random.secure();

  bool firebaseReady = false;
  String? initError;
  int serverOffsetMs = 0;
  StreamSubscription<DatabaseEvent>? _offsetSub;
  Completer<void>? _offsetReady;
  StreamSubscription<DatabaseEvent>? _connSub;
  DatabaseReference? _presenceRef;

  FirebaseDatabase get _db => FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: DefaultFirebaseOptions.currentPlatform.databaseURL,
      );

  Future<void> init() async {
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      firebaseReady = true;
    } catch (e) {
      firebaseReady = false;
      initError = e.toString();
    }
  }

  String? get uid => firebaseReady ? FirebaseAuth.instance.currentUser?.uid : null;

  /// Server time estimated from RTDB's clock offset – used for every countdown.
  int get serverNow => DateTime.now().millisecondsSinceEpoch + serverOffsetMs;

  Future<String> ensureSignedIn() async {
    if (!firebaseReady) {
      throw OnlineException('Online play is not set up in this build yet. '
          'Use Pass & Play, or follow the README to connect Firebase.');
    }
    final auth = FirebaseAuth.instance;
    var user = auth.currentUser;
    user ??= (await auth.signInAnonymously()).user;
    if (user == null) {
      throw OnlineException('Could not sign in. Check your internet connection.');
    }
    if (_offsetSub == null) {
      _offsetReady = Completer<void>();
      _offsetSub = _db.ref('.info/serverTimeOffset').onValue.listen((e) {
        final v = e.snapshot.value;
        if (v is num) serverOffsetMs = v.toInt();
        if (_offsetReady != null && !_offsetReady!.isCompleted) {
          _offsetReady!.complete();
        }
      });
    }
    if (_offsetReady != null && !_offsetReady!.isCompleted) {
      try {
        await _offsetReady!.future.timeout(const Duration(milliseconds: 1500));
      } catch (_) {
        // Continue with local clock if offset hasn't arrived yet.
      }
    }
    return user.uid;
  }

  String _requireCode(Object? v) {
    if (v is! String || !RegExp(r'^\d{6}$').hasMatch(v)) {
      throw OnlineException('Room code must be 6 digits.');
    }
    return v;
  }

  void _requireMember(OnlineRoom room, String uid) {
    if (!room.players.containsKey(uid)) {
      throw OnlineException('You are not in this room.');
    }
  }

  /// Atomically read-modify-write `/rooms/{code}`.
  /// `fn` returns true to commit changes, false to abort without writing,
  /// or throws `OnlineException` to reject.
  Future<OnlineRoom> _mutateRoom(
    String code,
    bool Function(OnlineRoom room) fn,
  ) async {
    Object? failure;
    var missing = false;
    try {
      final res = await _db.ref('rooms/$code').runTransaction(
        (Object? cur) {
          failure = null;
          missing = false;
          if (cur == null) {
            missing = true;
            return Transaction.success(null); // RTDB re-runs with server data if it exists
          }
          try {
            final room = OnlineRoom.fromRaw(cur);
            if (!fn(room)) return Transaction.abort();
            return Transaction.success(room.toDb());
          } catch (e) {
            failure = e;
            return Transaction.abort();
          }
        },
        applyLocally: false,
      );
      final err = failure;
      if (err != null) {
        if (err is OnlineException) throw err;
        throw OnlineException(err.toString());
      }
      if (missing || !res.snapshot.exists) {
        throw OnlineException('Room not found.');
      }
      return OnlineRoom.fromRaw(res.snapshot.value);
    } on OnlineException {
      rethrow;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw OnlineException('Permission denied for this room.');
      }
      throw OnlineException(e.message ?? e.code);
    }
  }

  /// Executes an online action directly against Firebase Realtime Database.
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> data = const {},
  ]) async {
    final uid = await ensureSignedIn();
    switch (action) {
      case 'ping':
        return <String, dynamic>{'now': serverNow};
      case 'createRoom':
        return _createRoom(uid, data);
      case 'joinRoom':
        return _joinRoom(uid, data);
      case 'setOvers':
        return _setOvers(uid, data);
      case 'ready':
        return _ready(uid, data);
      case 'chooseBatBowl':
        return _chooseBatBowl(uid, data);
      case 'tick':
        return _tick(uid, data);
      case 'requestRematch':
        return _requestRematch(uid, data);
      case 'leaveRoom':
        return _leaveRoom(uid, data);
      default:
        throw OnlineException('Unknown action: $action');
    }
  }

  Future<Map<String, dynamic>> _createRoom(String uid, Map<String, dynamic> data) async {
    final name = sanitizeName(data['name']);
    if (name == null) {
      throw OnlineException('Enter a nickname (1–16 characters).');
    }
    for (var attempt = 0; attempt < 15; attempt++) {
      final code = (100000 + _rng.nextInt(900000)).toString();
      final now = serverNow;
      try {
        final res = await _db.ref('rooms/$code').runTransaction(
          (Object? cur) {
            if (cur == null) {
              return Transaction.success(
                createNewRoom(code: code, hostUid: uid, hostName: name, now: now).toDb(),
              );
            }
            final createdAt = asInt(asMap(cur)['createdAt']);
            if (createdAt > 0 && now - createdAt > kRoomTtlMs) {
              return Transaction.success(
                createNewRoom(code: code, hostUid: uid, hostName: name, now: now).toDb(),
              );
            }
            return Transaction.abort(); // code already in use
          },
          applyLocally: false,
        );
        if (res.committed) {
          return <String, dynamic>{'code': code};
        }
      } on FirebaseException {
        // Active room owned by other players denies read/write – try another code.
        continue;
      }
    }
    throw OnlineException('Could not create a room. Please try again.');
  }

  Future<Map<String, dynamic>> _joinRoom(String uid, Map<String, dynamic> data) async {
    final code = _requireCode(data['code']);
    final name = sanitizeName(data['name']);
    if (name == null) {
      throw OnlineException('Enter a nickname (1–16 characters).');
    }
    try {
      final snap = await _db.ref('rooms/$code').get();
      if (!snap.exists) throw OnlineException('Room not found.');
    } on OnlineException {
      rethrow;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw OnlineException('This room is full or already in progress.');
      }
      throw OnlineException(e.message ?? e.code);
    }

    final now = serverNow;
    await _mutateRoom(code, (room) {
      if (room.players.containsKey(uid)) return false; // already in – rejoin is fine
      if (now - room.createdAt > kJoinTtlMs) {
        throw OnlineException('This room has expired.');
      }
      if (room.status != 'waiting' || room.players.length >= 2) {
        throw OnlineException('This room is full.');
      }
      room.players[uid] = OnlinePlayer(
        name: name,
        ready: false,
        connected: true,
        joinedAt: now,
      );
      room.status = 'lobby';
      return true;
    });
    return <String, dynamic>{'code': code};
  }

  Future<Map<String, dynamic>> _setOvers(String uid, Map<String, dynamic> data) async {
    final code = _requireCode(data['code']);
    final rawOvers = data['overs'];
    if (rawOvers is! int || rawOvers < kMinOvers || rawOvers > kMaxOvers) {
      throw OnlineException('Overs must be $kMinOvers–$kMaxOvers.');
    }
    await _mutateRoom(code, (room) {
      _requireMember(room, uid);
      if (room.hostUid != uid) {
        throw OnlineException('Only the host can change overs.');
      }
      if (room.status != 'waiting' && room.status != 'lobby') return false;
      room.overs = rawOvers;
      for (final p in room.players.values) {
        p.ready = false;
      }
      return true;
    });
    return <String, dynamic>{};
  }

  Future<Map<String, dynamic>> _ready(String uid, Map<String, dynamic> data) async {
    final code = _requireCode(data['code']);
    await _mutateRoom(code, (room) {
      _requireMember(room, uid);
      final now = serverNow;
      if (room.status == 'lobby') {
        room.players[uid]!.ready = true;
        final uids = playerUids(room);
        if (uids.length == 2 && uids.every((u) => room.players[u]!.ready)) {
          doToss(room, _rng.nextDouble);
        }
        return true;
      }
      if (room.status == 'innings_break') {
        room.breakReady = <String, bool>{...(room.breakReady ?? <String, bool>{}), uid: true};
        if (playerUids(room).every((u) => room.breakReady![u] == true)) {
          startSecondInnings(room, now);
        }
        return true;
      }
      return false;
    });
    return <String, dynamic>{};
  }

  Future<Map<String, dynamic>> _chooseBatBowl(String uid, Map<String, dynamic> data) async {
    final code = _requireCode(data['code']);
    final choice = data['choice'];
    if (choice != 'bat' && choice != 'bowl') {
      throw OnlineException('Choose bat or bowl.');
    }
    await _mutateRoom(code, (room) {
      _requireMember(room, uid);
      if (room.status != 'toss') return false;
      if (room.tossWinnerUid != uid) {
        throw OnlineException('Your opponent won the toss.');
      }
      chooseBatBowl(room, uid, choice as String, serverNow);
      return true;
    });
    return <String, dynamic>{};
  }

  Future<Map<String, dynamic>> _tick(String uid, Map<String, dynamic> data) async {
    final code = _requireCode(data['code']);
    final roundKey = data['roundKey'] is String ? data['roundKey'] as String : '';
    if (roundKey.isEmpty) return <String, dynamic>{'outcome': 'stale'};

    Map<String, Object?> moves;
    try {
      final snap = await _db.ref('moves/$code/$roundKey').get();
      moves = asMap(snap.value);
    } on FirebaseException {
      // Rules deny reading moves until both locked or deadline + 400ms passed.
      return <String, dynamic>{'outcome': 'pending'};
    }

    var outcome = ResolveOutcome.stale;
    await _mutateRoom(code, (room) {
      _requireMember(room, uid);
      outcome = resolveRound(room, roundKey, moves, serverNow);
      return outcome == ResolveOutcome.resolved;
    });
    return <String, dynamic>{'outcome': outcome.name};
  }

  Future<Map<String, dynamic>> _requestRematch(String uid, Map<String, dynamic> data) async {
    final code = _requireCode(data['code']);
    await _mutateRoom(code, (room) {
      _requireMember(room, uid);
      if (room.status != 'completed') return false;
      final uids = playerUids(room);
      if (uids.length != 2 || uids.any((u) => room.players[u]!.left)) {
        throw OnlineException('Your opponent has left.');
      }
      room.rematch = <String, bool>{...(room.rematch ?? <String, bool>{}), uid: true};
      if (uids.every((u) => room.rematch![u] == true)) {
        resetForRematch(room, _rng.nextDouble);
      }
      return true;
    });
    return <String, dynamic>{};
  }

  Future<Map<String, dynamic>> _leaveRoom(String uid, Map<String, dynamic> data) async {
    final code = _requireCode(data['code']);
    try {
      await _db.ref('rooms/$code').runTransaction(
        (Object? cur) {
          if (cur == null) return Transaction.abort();
          final room = OnlineRoom.fromRaw(cur);
          if (!room.players.containsKey(uid)) return Transaction.abort();
          final now = serverNow;
          switch (room.status) {
            case 'waiting':
              // Delete room cleanly when host leaves before anyone joins.
              return Transaction.success(null);
            case 'lobby':
              room.players.remove(uid);
              final rest = playerUids(room);
              if (rest.isEmpty) return Transaction.success(null);
              room.hostUid = rest.first;
              for (final p in room.players.values) {
                p.ready = false;
              }
              room.status = 'waiting';
              return Transaction.success(room.toDb());
            case 'toss':
            case 'playing':
            case 'innings_break':
              room.players[uid]!.left = true;
              finishForfeit(room, uid, 'left', now);
              return Transaction.success(room.toDb());
            default:
              room.players[uid]!.left = true;
              room.rematch = null;
              return Transaction.success(room.toDb());
          }
        },
        applyLocally: false,
      );
    } catch (_) {
      // Best-effort cleanup on leave.
    }
    return <String, dynamic>{};
  }

  /// Fire-and-forget call (warm-up, tick). Errors are ignored.
  void callQuietly(String action, [Map<String, dynamic> data = const {}]) {
    call(action, data).then((_) {}, onError: (Object _) {});
  }

  Stream<Object?> roomStream(String code) =>
      _db.ref('rooms/$code').onValue.map((e) => e.snapshot.value);

  /// Secret move: written once, straight to the database. Security rules
  /// reject it after the server deadline, and nobody can read /moves until
  /// both players lock or the deadline passes.
  Future<void> submitMove(String code, String roundKey, String uid, int move) {
    return _db.ref().update(<String, Object?>{
      'moves/$code/$roundKey/$uid': move,
      'rooms/$code/locks/$roundKey/$uid': true,
    });
  }

  /// Keeps players/{uid}/connected up to date, including when the app dies.
  void startPresence(String code, String uid) {
    stopPresence();
    final ref = _db.ref('rooms/$code/players/$uid/connected');
    _presenceRef = ref;
    _connSub = _db.ref('.info/connected').onValue.listen((e) async {
      if (e.snapshot.value == true) {
        try {
          await ref.onDisconnect().set(false);
          await ref.set(true);
        } catch (_) {
          // Not a member any more – ignore.
        }
      }
    });
  }

  void stopPresence() {
    _connSub?.cancel();
    _connSub = null;
    final ref = _presenceRef;
    _presenceRef = null;
    if (ref != null) {
      ref.onDisconnect().cancel().then((_) {}, onError: (Object _) {});
    }
  }
}
