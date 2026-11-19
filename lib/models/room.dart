/// Read-only views of /rooms/{code} as written by the Cloud Functions.
library;

Map<String, dynamic> asMap(Object? v) {
  if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val));
  return <String, dynamic>{};
}

int asInt(Object? v, [int d = 0]) => v is num ? v.toInt() : d;
int? asIntOrNull(Object? v) => v is num ? v.toInt() : null;
String asStr(Object? v, [String d = '']) => v == null ? d : v.toString();

/// RTDB returns arrays as List (possibly with nulls) or as Map with numeric keys.
List<String> asStringList(Object? v) {
  if (v is List) return v.where((e) => e != null).map((e) => e.toString()).toList();
  if (v is Map) {
    final entries = v.entries.where((e) => e.value != null).toList()
      ..sort((a, b) =>
          (int.tryParse(a.key.toString()) ?? 0).compareTo(int.tryParse(b.key.toString()) ?? 0));
    return entries.map((e) => e.value.toString()).toList();
  }
  return <String>[];
}

Set<String> trueKeys(Object? v) =>
    asMap(v).entries.where((e) => e.value == true).map((e) => e.key).toSet();

class RoomPlayer {
  final String uid;
  final String name;
  final bool ready;
  final bool connected;
  final bool left;
  final int joinedAt;

  RoomPlayer(this.uid, Map<String, dynamic> m)
      : name = asStr(m['name'], 'Player'),
        ready = m['ready'] == true,
        connected = m['connected'] != false,
        left = m['left'] == true,
        joinedAt = asInt(m['joinedAt']);
}

class InningsSummary {
  final String batterUid;
  final String bowlerUid;
  final int score;
  final int wickets;
  final int legalBalls;
  final int noBalls;
  final List<String> balls;

  InningsSummary(Map<String, dynamic> m)
      : batterUid = asStr(m['batterUid']),
        bowlerUid = asStr(m['bowlerUid']),
        score = asInt(m['score']),
        wickets = asInt(m['wickets']),
        legalBalls = asInt(m['legalBalls']),
        noBalls = asInt(m['noBalls']),
        balls = asStringList(m['balls']);
}

class LastResult {
  final String roundKey;
  final String batterUid;
  final String bowlerUid;
  final int? batterMove;
  final int? bowlerMove;
  final String type;
  final int batterRuns;

  LastResult(Map<String, dynamic> m)
      : roundKey = asStr(m['roundKey']),
        batterUid = asStr(m['batterUid']),
        bowlerUid = asStr(m['bowlerUid']),
        batterMove = asIntOrNull(m['batterMove']),
        bowlerMove = asIntOrNull(m['bowlerMove']),
        type = asStr(m['type'], 'retry'),
        batterRuns = asInt(m['batterRuns']);
}

class MatchView extends InningsSummary {
  final int innings;
  final String roundKey;
  final int startAt;
  final int deadlineAt;
  final int? target;
  final InningsSummary? first;
  final LastResult? lastResult;
  final int startedAt;

  MatchView(Map<String, dynamic> m)
      : innings = asInt(m['innings'], 1),
        roundKey = asStr(m['roundKey']),
        startAt = asInt(m['startAt']),
        deadlineAt = asInt(m['deadlineAt']),
        target = asIntOrNull(m['target']),
        first = m['first'] == null ? null : InningsSummary(asMap(m['first'])),
        lastResult = m['lastResult'] == null ? null : LastResult(asMap(m['lastResult'])),
        startedAt = asInt(m['startedAt']),
        super(m);
}

class MatchResultView {
  final String? winnerUid;
  final bool tie;
  final String reason;
  final String text;
  final int endedAt;

  MatchResultView(Map<String, dynamic> m)
      : winnerUid = m['winnerUid']?.toString(),
        tie = m['tie'] == true,
        reason = asStr(m['reason'], 'normal'),
        text = asStr(m['text']),
        endedAt = asInt(m['endedAt']);
}

class RoomView {
  final String code;
  final String hostUid;
  final String status;
  final int overs;
  final int maxWickets;
  final int selectionMs;
  final List<RoomPlayer> players;
  final String? tossWinnerUid;
  final MatchView? match;
  final MatchResultView? result;
  final Set<String> breakReady;
  final Set<String> rematch;
  final Map<String, Set<String>> locks;

  RoomView._({
    required this.code,
    required this.hostUid,
    required this.status,
    required this.overs,
    required this.maxWickets,
    required this.selectionMs,
    required this.players,
    required this.tossWinnerUid,
    required this.match,
    required this.result,
    required this.breakReady,
    required this.rematch,
    required this.locks,
  });

  factory RoomView.fromRaw(String code, Object? raw) {
    final m = asMap(raw);
    final settings = asMap(m['settings']);
    final players = asMap(m['players'])
        .entries
        .where((e) => e.value is Map)
        .map((e) => RoomPlayer(e.key, asMap(e.value)))
        .toList()
      ..sort((a, b) => a.joinedAt.compareTo(b.joinedAt));
    final locks = <String, Set<String>>{};
    asMap(m['locks']).forEach((k, v) => locks[k] = trueKeys(v));
    return RoomView._(
      code: code,
      hostUid: asStr(m['hostUid']),
      status: asStr(m['status'], 'waiting'),
      overs: asInt(settings['overs'], 2),
      maxWickets: asInt(settings['wickets'], 1),
      selectionMs: asInt(settings['selectionMs'], 3000),
      players: players,
      tossWinnerUid: asMap(m['toss'])['winnerUid']?.toString(),
      match: m['match'] == null ? null : MatchView(asMap(m['match'])),
      result: m['result'] == null ? null : MatchResultView(asMap(m['result'])),
      breakReady: trueKeys(m['breakReady']),
      rematch: trueKeys(m['rematch']),
      locks: locks,
    );
  }

  int get maxBalls => overs * 6;

  RoomPlayer? player(String uid) {
    for (final p in players) {
      if (p.uid == uid) return p;
    }
    return null;
  }

  String nameOf(String? uid) => uid == null ? 'Player' : (player(uid)?.name ?? 'Player');

  String? opponentOf(String uid) {
    for (final p in players) {
      if (p.uid != uid) return p.uid;
    }
    return null;
  }
}
