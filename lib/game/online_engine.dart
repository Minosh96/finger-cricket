/// Pure Dart online game engine for Finger Cricket (Firebase Realtime Database / Spark plan).
/// Mirrors functions/src/engine.ts so all rules and state transitions are unit-testable.
library;

import '../models/room.dart';
import 'game_rules.dart';

const int kSelectMs = 3000;
const int kPrepMs = 1800;
const int kRevealMs = 2200;
const int kLockGraceMs = 400; // must match "+ 400" in database.rules.json
const int kSettleMs = 1000; // waits past grace window before resolving timeouts
const int kMaxMisses = 4; // consecutive missed balls before forfeit
const int kRoomTtlMs = 3 * 60 * 60 * 1000; // room code reusable after 3 h
const int kJoinTtlMs = 60 * 60 * 1000; // waiting room joinable for 1 h
const int kMinOvers = 1;
const int kMaxOvers = 10;

int? parseValidMove(Object? v) {
  if (v is num) {
    final i = v.toInt();
    if (v == i && i >= 1 && i <= 7) return i;
  }
  return null;
}

String? sanitizeName(Object? v) {
  if (v is! String) return null;
  final cleaned = v
      .replaceAll(RegExp(r'[\u0000-\u001f\u007f]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (cleaned.isEmpty) return null;
  return cleaned.length > 16 ? cleaned.substring(0, 16) : cleaned;
}

String deliveryTypeToServer(DeliveryType t) {
  switch (t) {
    case DeliveryType.runs:
      return 'runs';
    case DeliveryType.wicket:
      return 'wicket';
    case DeliveryType.dotBall:
      return 'dot';
    case DeliveryType.noBall:
      return 'noBall';
    case DeliveryType.retry:
      return 'retry';
  }
}

class OnlinePlayer {
  String name;
  bool ready;
  bool connected;
  int joinedAt;
  bool left;

  OnlinePlayer({
    required this.name,
    required this.ready,
    required this.connected,
    required this.joinedAt,
    this.left = false,
  });

  factory OnlinePlayer.fromMap(Map<String, dynamic> m) => OnlinePlayer(
        name: asStr(m['name'], 'Player'),
        ready: m['ready'] == true,
        connected: m['connected'] != false,
        joinedAt: asInt(m['joinedAt']),
        left: m['left'] == true,
      );

  Map<String, Object?> toDb() => <String, Object?>{
        'name': name,
        'ready': ready,
        'connected': connected,
        'joinedAt': joinedAt,
        if (left) 'left': true,
      };
}

class OnlineInnings {
  String batterUid;
  String bowlerUid;
  int score;
  int wickets;
  int legalBalls;
  int noBalls;
  List<String> balls;

  OnlineInnings({
    required this.batterUid,
    required this.bowlerUid,
    required this.score,
    required this.wickets,
    required this.legalBalls,
    required this.noBalls,
    required this.balls,
  });

  factory OnlineInnings.fromMap(Map<String, dynamic> m) => OnlineInnings(
        batterUid: asStr(m['batterUid']),
        bowlerUid: asStr(m['bowlerUid']),
        score: asInt(m['score']),
        wickets: asInt(m['wickets']),
        legalBalls: asInt(m['legalBalls']),
        noBalls: asInt(m['noBalls']),
        balls: asStringList(m['balls']),
      );

  Map<String, Object?> toDb() => <String, Object?>{
        'batterUid': batterUid,
        'bowlerUid': bowlerUid,
        'score': score,
        'wickets': wickets,
        'legalBalls': legalBalls,
        'noBalls': noBalls,
        'balls': balls,
      };
}

class OnlineLastResult {
  String roundKey;
  String batterUid;
  String bowlerUid;
  int? batterMove;
  int? bowlerMove;
  String type;
  int batterRuns;
  int extras;

  OnlineLastResult({
    required this.roundKey,
    required this.batterUid,
    required this.bowlerUid,
    required this.batterMove,
    required this.bowlerMove,
    required this.type,
    required this.batterRuns,
    required this.extras,
  });

  factory OnlineLastResult.fromMap(Map<String, dynamic> m) => OnlineLastResult(
        roundKey: asStr(m['roundKey']),
        batterUid: asStr(m['batterUid']),
        bowlerUid: asStr(m['bowlerUid']),
        batterMove: parseValidMove(m['batterMove']),
        bowlerMove: parseValidMove(m['bowlerMove']),
        type: asStr(m['type'], 'retry'),
        batterRuns: asInt(m['batterRuns']),
        extras: asInt(m['extras']),
      );

  Map<String, Object?> toDb() => <String, Object?>{
        'roundKey': roundKey,
        'batterUid': batterUid,
        'bowlerUid': bowlerUid,
        if (batterMove != null) 'batterMove': batterMove,
        if (bowlerMove != null) 'bowlerMove': bowlerMove,
        'type': type,
        'batterRuns': batterRuns,
        'extras': extras,
      };
}

class OnlineMatch extends OnlineInnings {
  int innings;
  String roundKey;
  int startAt;
  int deadlineAt;
  int? target;
  OnlineInnings? first;
  OnlineLastResult? lastResult;
  Map<String, int> misses;
  int startedAt;

  OnlineMatch({
    required this.innings,
    required super.batterUid,
    required super.bowlerUid,
    required this.roundKey,
    required this.startAt,
    required this.deadlineAt,
    required super.score,
    required super.wickets,
    required super.legalBalls,
    required super.noBalls,
    required super.balls,
    required this.target,
    required this.first,
    required this.lastResult,
    required this.misses,
    required this.startedAt,
  });

  factory OnlineMatch.fromMap(Map<String, dynamic> m) {
    final rawMisses = asMap(m['misses']);
    final misses = <String, int>{};
    rawMisses.forEach((k, v) => misses[k] = asInt(v));
    return OnlineMatch(
      innings: asInt(m['innings'], 1) == 2 ? 2 : 1,
      batterUid: asStr(m['batterUid']),
      bowlerUid: asStr(m['bowlerUid']),
      roundKey: asStr(m['roundKey']),
      startAt: asInt(m['startAt']),
      deadlineAt: asInt(m['deadlineAt']),
      score: asInt(m['score']),
      wickets: asInt(m['wickets']),
      legalBalls: asInt(m['legalBalls']),
      noBalls: asInt(m['noBalls']),
      balls: asStringList(m['balls']),
      target: asIntOrNull(m['target']),
      first: m['first'] == null ? null : OnlineInnings.fromMap(asMap(m['first'])),
      lastResult: m['lastResult'] == null ? null : OnlineLastResult.fromMap(asMap(m['lastResult'])),
      misses: misses,
      startedAt: asInt(m['startedAt']),
    );
  }

  @override
  Map<String, Object?> toDb() => <String, Object?>{
        ...super.toDb(),
        'innings': innings,
        'roundKey': roundKey,
        'startAt': startAt,
        'deadlineAt': deadlineAt,
        if (target != null) 'target': target,
        if (first != null) 'first': first!.toDb(),
        if (lastResult != null) 'lastResult': lastResult!.toDb(),
        if (misses.isNotEmpty) 'misses': misses,
        'startedAt': startedAt,
      };
}

class OnlineMatchResult {
  String? winnerUid;
  bool tie;
  String reason;
  String text;
  int endedAt;

  OnlineMatchResult({
    required this.winnerUid,
    required this.tie,
    required this.reason,
    required this.text,
    required this.endedAt,
  });

  factory OnlineMatchResult.fromMap(Map<String, dynamic> m) => OnlineMatchResult(
        winnerUid: m['winnerUid']?.toString(),
        tie: m['tie'] == true,
        reason: asStr(m['reason'], 'normal'),
        text: asStr(m['text']),
        endedAt: asInt(m['endedAt']),
      );

  Map<String, Object?> toDb() => <String, Object?>{
        if (winnerUid != null) 'winnerUid': winnerUid,
        'tie': tie,
        'reason': reason,
        'text': text,
        'endedAt': endedAt,
      };
}

class OnlineRoom {
  String code;
  String hostUid;
  int createdAt;
  String status;
  int overs;
  int wickets;
  int selectionMs;
  Map<String, OnlinePlayer> players;
  int roundSeq;
  int matchNo;
  String? tossWinnerUid;
  OnlineMatch? match;
  OnlineMatchResult? result;
  Map<String, bool>? breakReady;
  Map<String, bool>? rematch;
  Map<String, Map<String, bool>>? locks;

  OnlineRoom({
    required this.code,
    required this.hostUid,
    required this.createdAt,
    required this.status,
    required this.overs,
    required this.wickets,
    required this.selectionMs,
    required this.players,
    required this.roundSeq,
    required this.matchNo,
    required this.tossWinnerUid,
    required this.match,
    required this.result,
    required this.breakReady,
    required this.rematch,
    required this.locks,
  });

  factory OnlineRoom.fromRaw(Object? raw) {
    final m = asMap(raw);
    final settings = asMap(m['settings']);
    final players = <String, OnlinePlayer>{};
    asMap(m['players']).forEach((uid, v) {
      if (v is Map) {
        final pm = asMap(v);
        if (pm['name'] is String) {
          players[uid] = OnlinePlayer.fromMap(pm);
        }
      }
    });
    Map<String, bool>? boolMap(Object? v) {
      if (v is! Map) return null;
      final out = <String, bool>{};
      asMap(v).forEach((k, val) {
        if (val == true) out[k] = true;
      });
      return out;
    }

    Map<String, Map<String, bool>>? locks;
    if (m['locks'] is Map) {
      locks = <String, Map<String, bool>>{};
      asMap(m['locks']).forEach((rk, rv) {
        final inner = boolMap(rv);
        if (inner != null && inner.isNotEmpty) locks![rk] = inner;
      });
    }

    return OnlineRoom(
      code: asStr(m['code']),
      hostUid: asStr(m['hostUid']),
      createdAt: asInt(m['createdAt']),
      status: asStr(m['status'], 'waiting'),
      overs: asInt(settings['overs'], 2),
      wickets: asInt(settings['wickets'], 1),
      selectionMs: asInt(settings['selectionMs'], kSelectMs),
      players: players,
      roundSeq: asInt(m['roundSeq']),
      matchNo: asInt(m['matchNo'], 1),
      tossWinnerUid: asMap(m['toss'])['winnerUid']?.toString(),
      match: m['match'] == null ? null : OnlineMatch.fromMap(asMap(m['match'])),
      result: m['result'] == null ? null : OnlineMatchResult.fromMap(asMap(m['result'])),
      breakReady: boolMap(m['breakReady']),
      rematch: boolMap(m['rematch']),
      locks: locks,
    );
  }

  Map<String, Object?> toDb() {
    final pMap = <String, Object?>{};
    players.forEach((uid, p) => pMap[uid] = p.toDb());
    return <String, Object?>{
      'code': code,
      'hostUid': hostUid,
      'createdAt': createdAt,
      'status': status,
      'settings': <String, Object?>{
        'overs': overs,
        'wickets': wickets,
        'selectionMs': selectionMs,
      },
      'players': pMap,
      'roundSeq': roundSeq,
      'matchNo': matchNo,
      if (tossWinnerUid != null) 'toss': <String, Object?>{'winnerUid': tossWinnerUid},
      if (match != null) 'match': match!.toDb(),
      if (result != null) 'result': result!.toDb(),
      if (breakReady != null && breakReady!.isNotEmpty) 'breakReady': breakReady,
      if (rematch != null && rematch!.isNotEmpty) 'rematch': rematch,
      if (locks != null && locks!.isNotEmpty) 'locks': locks,
    };
  }
}

List<String> playerUids(OnlineRoom room) {
  final uids = room.players.keys.toList();
  uids.sort((a, b) {
    final cmp = room.players[a]!.joinedAt.compareTo(room.players[b]!.joinedAt);
    return cmp != 0 ? cmp : a.compareTo(b);
  });
  return uids;
}

String? opponentOf(OnlineRoom room, String uid) {
  for (final u in playerUids(room)) {
    if (u != uid) return u;
  }
  return null;
}

String nameOf(OnlineRoom room, String? uid) {
  if (uid == null) return 'Player';
  return room.players[uid]?.name ?? 'Player';
}

OnlineRoom createNewRoom({
  required String code,
  required String hostUid,
  required String hostName,
  required int now,
  int overs = 2,
}) {
  return OnlineRoom(
    code: code,
    hostUid: hostUid,
    createdAt: now,
    status: 'waiting',
    overs: overs,
    wickets: 1,
    selectionMs: kSelectMs,
    players: <String, OnlinePlayer>{
      hostUid: OnlinePlayer(name: hostName, ready: false, connected: true, joinedAt: now),
    },
    roundSeq: 0,
    matchNo: 1,
    tossWinnerUid: null,
    match: null,
    result: null,
    breakReady: null,
    rematch: null,
    locks: null,
  );
}

void doToss(OnlineRoom room, double Function() rand) {
  final uids = playerUids(room);
  room.tossWinnerUid = uids[rand() < 0.5 ? 0 : 1];
  room.status = 'toss';
  room.match = null;
  room.result = null;
}

void startRound(OnlineRoom room, int now, int delayMs) {
  final m = room.match!;
  room.roundSeq += 1;
  // Include createdAt so reused room codes never collide with old /moves entries.
  m.roundKey = 'r${room.createdAt}_${room.roundSeq}';
  m.startAt = now + delayMs;
  m.deadlineAt = m.startAt + room.selectionMs;
  room.locks = null;
}

void beginInnings(
  OnlineRoom room, {
  required int innings,
  required String batterUid,
  required int now,
  OnlineInnings? first,
}) {
  final bowlerUid = opponentOf(room, batterUid);
  if (bowlerUid == null) throw StateError('Opponent missing');
  final prevMisses = room.match?.misses ?? <String, int>{};
  final prevStarted = room.match?.startedAt ?? 0;
  room.match = OnlineMatch(
    innings: innings,
    batterUid: batterUid,
    bowlerUid: bowlerUid,
    roundKey: '',
    startAt: 0,
    deadlineAt: 0,
    score: 0,
    wickets: 0,
    legalBalls: 0,
    noBalls: 0,
    balls: <String>[],
    target: first != null ? first.score + 1 : null,
    first: first,
    lastResult: null,
    misses: Map<String, int>.from(prevMisses),
    startedAt: prevStarted > 0 ? prevStarted : now,
  );
  room.status = 'playing';
  room.breakReady = null;
  startRound(room, now, kPrepMs);
}

void chooseBatBowl(OnlineRoom room, String uid, String choice, int now) {
  if (room.status != 'toss' || room.tossWinnerUid != uid) {
    throw StateError('Not your choice');
  }
  final batter = choice == 'bat' ? uid : opponentOf(room, uid)!;
  room.match = null;
  beginInnings(room, innings: 1, batterUid: batter, now: now, first: null);
}

void startSecondInnings(OnlineRoom room, int now) {
  final m = room.match!;
  final first = OnlineInnings(
    batterUid: m.batterUid,
    bowlerUid: m.bowlerUid,
    score: m.score,
    wickets: m.wickets,
    legalBalls: m.legalBalls,
    noBalls: m.noBalls,
    balls: List<String>.from(m.balls),
  );
  beginInnings(room, innings: 2, batterUid: m.bowlerUid, now: now, first: first);
}

void finishForfeit(OnlineRoom room, String loserUid, String reason, int now) {
  final winner = opponentOf(room, loserUid);
  room.status = 'completed';
  room.locks = null;
  if (room.match != null) room.match!.roundKey = '';
  room.result = OnlineMatchResult(
    winnerUid: winner,
    tie: false,
    reason: reason,
    text: reason == 'left'
        ? '${nameOf(room, winner)} wins – ${nameOf(room, loserUid)} left the match'
        : '${nameOf(room, winner)} wins by forfeit – ${nameOf(room, loserUid)} missed $kMaxMisses balls in a row',
    endedAt: now,
  );
}

void finishMatch(OnlineRoom room, int now) {
  final m = room.match!;
  final first = m.first!;
  final maxBalls = room.overs * 6;
  String plural(int n, String w) => '$n $w${n == 1 ? '' : 's'}';
  room.status = 'completed';
  room.locks = null;
  m.roundKey = '';
  if (m.target != null && m.score >= m.target!) {
    room.result = OnlineMatchResult(
      winnerUid: m.batterUid,
      tie: false,
      reason: 'normal',
      text: '${nameOf(room, m.batterUid)} won by ${plural(room.wickets - m.wickets, 'wicket')} '
          'with ${plural(maxBalls - m.legalBalls, 'ball')} remaining',
      endedAt: now,
    );
  } else if (m.score == first.score) {
    room.result = OnlineMatchResult(
      winnerUid: null,
      tie: true,
      reason: 'normal',
      text: 'Match tied!',
      endedAt: now,
    );
  } else {
    room.result = OnlineMatchResult(
      winnerUid: first.batterUid,
      tie: false,
      reason: 'normal',
      text: '${nameOf(room, first.batterUid)} won by ${plural(first.score - m.score, 'run')}',
      endedAt: now,
    );
  }
}

enum ResolveOutcome { stale, pending, resolved }

/// Resolves the current delivery idempotently (only when `roundKey` is still active).
ResolveOutcome resolveRound(
  OnlineRoom room,
  String roundKey,
  Map<String, Object?> moves,
  int now,
) {
  final m = room.match;
  if (room.status != 'playing' || m == null || roundKey.isEmpty || m.roundKey != roundKey) {
    return ResolveOutcome.stale;
  }

  final batterMove = parseValidMove(moves[m.batterUid]);
  final bowlerMove = parseValidMove(moves[m.bowlerUid]);
  final bothIn = batterMove != null && bowlerMove != null;
  if (!bothIn && now <= m.deadlineAt + kSettleMs) return ResolveOutcome.pending;

  final r = evaluateDelivery(batterMove: batterMove, bowlerMove: bowlerMove);
  m.lastResult = OnlineLastResult(
    roundKey: roundKey,
    batterUid: m.batterUid,
    bowlerUid: m.bowlerUid,
    batterMove: batterMove,
    bowlerMove: bowlerMove,
    type: deliveryTypeToServer(r.type),
    batterRuns: r.batterRuns,
    extras: r.extras,
  );

  m.misses[m.batterUid] = batterMove == null ? (m.misses[m.batterUid] ?? 0) + 1 : 0;
  m.misses[m.bowlerUid] = bowlerMove == null ? (m.misses[m.bowlerUid] ?? 0) + 1 : 0;
  final batterOut = (m.misses[m.batterUid] ?? 0) >= kMaxMisses;
  final bowlerOut = (m.misses[m.bowlerUid] ?? 0) >= kMaxMisses;

  if (batterOut && bowlerOut) {
    room.status = 'abandoned';
    room.locks = null;
    m.roundKey = '';
    room.result = OnlineMatchResult(
      winnerUid: null,
      tie: false,
      reason: 'inactive',
      text: 'Match abandoned – both players inactive',
      endedAt: now,
    );
    return ResolveOutcome.resolved;
  }
  if (batterOut || bowlerOut) {
    finishForfeit(room, batterOut ? m.batterUid : m.bowlerUid, 'forfeit', now);
    return ResolveOutcome.resolved;
  }

  if (r.type == DeliveryType.retry) {
    startRound(room, now, kRevealMs);
    return ResolveOutcome.resolved;
  }

  m.score += r.totalRuns;
  if (r.type == DeliveryType.noBall) m.noBalls += 1;
  if (r.legalBall) m.legalBalls += 1;
  if (r.wicket) m.wickets += 1;
  m.balls.add(ballCode(r));

  final maxBalls = room.overs * 6;
  if (m.innings == 2 && m.target != null && m.score >= m.target!) {
    finishMatch(room, now);
  } else if (m.wickets >= room.wickets || m.legalBalls >= maxBalls) {
    if (m.innings == 1) {
      room.status = 'innings_break';
      room.breakReady = <String, bool>{};
      room.locks = null;
      m.roundKey = '';
    } else {
      finishMatch(room, now);
    }
  } else {
    startRound(room, now, kRevealMs);
  }
  return ResolveOutcome.resolved;
}

void resetForRematch(OnlineRoom room, double Function() rand) {
  room.matchNo += 1;
  room.rematch = null;
  room.breakReady = null;
  room.locks = null;
  for (final p in room.players.values) {
    p.ready = false;
  }
  doToss(room, rand);
}
