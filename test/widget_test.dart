// Rules tests – run with `flutter test` (also run by the GitHub build).
import 'package:finger_cricket/game/game_rules.dart';
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
}
