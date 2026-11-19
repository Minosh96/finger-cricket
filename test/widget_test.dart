// Rules tests – run with `flutter test` (also run by the GitHub build).
import 'package:finger_cricket/game/game_rules.dart';
import 'package:finger_cricket/game/online_engine.dart';
import 'package:flutter_test/flutter_test.dart';

InningsScore play(List<List<int?>> balls) {
  final s = InningsScore();
  for (final b in balls) {
    s.apply(evaluateDelivery(batterMove: b[0], bowlerMove: b[1]));
  }
  return s;
}

void main() {
  test('different gestures score batter runs, 6 and 7 included', () {
    expect(evaluateDelivery(batterMove: 4, bowlerMove: 2).batterRuns, 4);
    expect(evaluateDelivery(batterMove: 6, bowlerMove: 3).batterRuns, 6);
    expect(evaluateDelivery(batterMove: 7, bowlerMove: 1).batterRuns, 7);
  });

  test('matching gestures are OUT', () {
    for (var n = 1; n <= 7; n++) {
      expect(evaluateDelivery(batterMove: n, bowlerMove: n).type, DeliveryType.wicket);
    }
  });

  test('timeouts: no-ball, dot ball, retry', () {
    final nb = evaluateDelivery(batterMove: 3, bowlerMove: null);
    expect(nb.type, DeliveryType.noBall);
    expect(nb.totalRuns, 1);
    expect(nb.legalBall, false);
    final dot = evaluateDelivery(batterMove: null, bowlerMove: 3);
    expect(dot.type, DeliveryType.dotBall);
    expect(dot.legalBall, true);
    expect(evaluateDelivery(batterMove: null, bowlerMove: null).type, DeliveryType.retry);
  });

  test('spec example 2,4,NB,1,W = 8/1 in 0.4 overs', () {
    final s = play([
      [2, 5],
      [4, 1],
      [3, null],
      [1, 6],
      [5, 5],
    ]);
    expect(s.score, 8);
    expect(s.wickets, 1);
    expect(formatOvers(s.legalBalls), '0.4');
    expect(s.noBalls, 1);
    expect(s.balls, ['2', '4', 'NB', '1', 'W']);
    expect(inningsStatus(innings: s, maxBalls: 12, maxWickets: 1), InningsStatus.inningsOver);
  });

  test('overs format', () {
    expect([0, 5, 6, 8, 12].map(formatOvers).toList(), ['0.0', '0.5', '1.0', '1.2', '2.0']);
  });

  test('chase result text', () {
    final first = play([
      [6, 1],
      [6, 6],
    ]);
    final second = play([
      [4, 1],
      [3, 1],
    ]);
    expect(inningsStatus(innings: second, maxBalls: 12, maxWickets: 1, target: first.score + 1),
        InningsStatus.targetReached);
    expect(
      matchResultText(
          firstBatter: 'Ann', secondBatter: 'Ben', first: first, second: second, maxBalls: 12, maxWickets: 1),
      'Ben won by 1 wicket with 10 balls remaining',
    );
  });

  test('online engine: full match, serialization, idempotency, and rematch', () {
    const t0 = 1700000000000;
    final room = createNewRoom(code: '123456', hostUid: 'u1', hostName: 'Ann', now: t0);
    room.players['u2'] = OnlinePlayer(name: 'Ben', ready: true, connected: true, joinedAt: t0 + 10);
    room.players['u1']!.ready = true;
    room.status = 'lobby';

    // Round-trip through RTDB map format.
    final hydrated = OnlineRoom.fromRaw(room.toDb());
    expect(hydrated.code, '123456');
    expect(hydrated.players.length, 2);

    doToss(hydrated, () => 0.1); // u1 wins toss
    expect(hydrated.status, 'toss');
    expect(hydrated.tossWinnerUid, 'u1');

    chooseBatBowl(hydrated, 'u1', 'bat', t0 + 100);
    expect(hydrated.status, 'playing');
    final r1 = hydrated.match!.roundKey;
    expect(r1.startsWith('r${t0}_'), true);

    // Pending before deadline + settle when only one move is present.
    expect(
      resolveRound(hydrated, r1, <String, Object?>{'u1': 2}, hydrated.match!.deadlineAt),
      ResolveOutcome.pending,
    );

    // 2, 4, NB, 1, W => 8/1 in 0.4 overs -> innings_break
    expect(
      resolveRound(hydrated, hydrated.match!.roundKey, <String, Object?>{'u1': 2, 'u2': 5}, t0 + 2000),
      ResolveOutcome.resolved,
    );
    // Duplicate call on old roundKey is stale (idempotent).
    expect(
      resolveRound(hydrated, r1, <String, Object?>{'u1': 2, 'u2': 5}, t0 + 2000),
      ResolveOutcome.stale,
    );
    expect(
      resolveRound(hydrated, hydrated.match!.roundKey, <String, Object?>{'u1': 4, 'u2': 1}, t0 + 5000),
      ResolveOutcome.resolved,
    );
    expect(
      resolveRound(
        hydrated,
        hydrated.match!.roundKey,
        <String, Object?>{'u1': 3},
        hydrated.match!.deadlineAt + kSettleMs + 1,
      ),
      ResolveOutcome.resolved,
    );
    expect(
      resolveRound(hydrated, hydrated.match!.roundKey, <String, Object?>{'u1': 1, 'u2': 6}, t0 + 12000),
      ResolveOutcome.resolved,
    );
    expect(
      resolveRound(hydrated, hydrated.match!.roundKey, <String, Object?>{'u1': 5, 'u2': 5}, t0 + 15000),
      ResolveOutcome.resolved,
    );

    expect(hydrated.status, 'innings_break');
    expect(hydrated.match!.score, 8);
    expect(hydrated.match!.wickets, 1);
    expect(hydrated.match!.legalBalls, 4);
    expect(hydrated.match!.noBalls, 1);
    expect(hydrated.match!.balls, ['2', '4', 'NB', '1', 'W']);

    // Second innings chase: Ben scores 6 + 3 = 9 (target 9).
    startSecondInnings(hydrated, t0 + 20000);
    expect(hydrated.status, 'playing');
    expect(hydrated.match!.batterUid, 'u2');
    expect(hydrated.match!.target, 9);

    resolveRound(hydrated, hydrated.match!.roundKey, <String, Object?>{'u2': 6, 'u1': 1}, t0 + 23000);
    resolveRound(hydrated, hydrated.match!.roundKey, <String, Object?>{'u2': 3, 'u1': 2}, t0 + 26000);

    expect(hydrated.status, 'completed');
    expect(hydrated.result!.winnerUid, 'u2');
    expect(hydrated.result!.text, 'Ben won by 1 wicket with 10 balls remaining');

    // Rematch resets cleanly.
    resetForRematch(hydrated, () => 0.9);
    expect(hydrated.status, 'toss');
    expect(hydrated.matchNo, 2);
    expect(hydrated.tossWinnerUid, 'u2');
  });

  test('online engine: 4 consecutive misses causes forfeit', () {
    const t0 = 1700000000000;
    final room = createNewRoom(code: '654321', hostUid: 'u1', hostName: 'Ann', now: t0);
    room.players['u2'] = OnlinePlayer(name: 'Ben', ready: true, connected: true, joinedAt: t0 + 1);
    doToss(room, () => 0.1);
    chooseBatBowl(room, 'u1', 'bat', t0 + 10);

    for (var i = 0; i < kMaxMisses; i++) {
      final res = resolveRound(
        room,
        room.match!.roundKey,
        <String, Object?>{'u1': 2}, // bowler u2 misses every ball
        room.match!.deadlineAt + kSettleMs + 1,
      );
      expect(res, ResolveOutcome.resolved);
    }
    expect(room.status, 'completed');
    expect(room.result!.winnerUid, 'u1');
    expect(room.result!.reason, 'forfeit');
  });
}
