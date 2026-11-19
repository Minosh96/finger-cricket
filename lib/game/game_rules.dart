/// Core Finger Cricket rules. Mirrors functions/src/engine.ts (the server is
/// the authority online; this file drives the offline Pass & Play mode).
library;

enum DeliveryType { runs, wicket, dotBall, noBall, retry }

class DeliveryResult {
  final DeliveryType type;
  final int batterRuns;
  final int extras;
  final bool legalBall;
  final bool wicket;

  const DeliveryResult({
    required this.type,
    required this.batterRuns,
    required this.extras,
    required this.legalBall,
    required this.wicket,
  });

  int get totalRuns => batterRuns + extras;
}

/// Gestures 1–5 = fingers, 6 = thumb only, 7 = thumb + pinky.
/// Same number = OUT, otherwise the batter scores their own number.
/// `null` means the player did not choose within 3 seconds.
DeliveryResult evaluateDelivery({
  required int? batterMove,
  required int? bowlerMove,
}) {
  if (batterMove == null && bowlerMove == null) {
    return const DeliveryResult(
        type: DeliveryType.retry, batterRuns: 0, extras: 0, legalBall: false, wicket: false);
  }
  if (bowlerMove == null) {
    return const DeliveryResult(
        type: DeliveryType.noBall, batterRuns: 0, extras: 1, legalBall: false, wicket: false);
  }
  if (batterMove == null) {
    return const DeliveryResult(
        type: DeliveryType.dotBall, batterRuns: 0, extras: 0, legalBall: true, wicket: false);
  }
  if (batterMove == bowlerMove) {
    return const DeliveryResult(
        type: DeliveryType.wicket, batterRuns: 0, extras: 0, legalBall: true, wicket: true);
  }
  return DeliveryResult(
      type: DeliveryType.runs, batterRuns: batterMove, extras: 0, legalBall: true, wicket: false);
}

String formatOvers(int legalBalls) => '${legalBalls ~/ 6}.${legalBalls % 6}';

String ballCode(DeliveryResult r) {
  switch (r.type) {
    case DeliveryType.runs:
      return '${r.batterRuns}';
    case DeliveryType.wicket:
      return 'W';
    case DeliveryType.dotBall:
      return '•';
    case DeliveryType.noBall:
      return 'NB';
    case DeliveryType.retry:
      return 'R';
  }
}

DeliveryType deliveryTypeFromServer(String s) {
  switch (s) {
    case 'runs':
      return DeliveryType.runs;
    case 'wicket':
      return DeliveryType.wicket;
    case 'dot':
      return DeliveryType.dotBall;
    case 'noBall':
      return DeliveryType.noBall;
    default:
      return DeliveryType.retry;
  }
}

/// Running score of one innings.
class InningsScore {
  int score = 0;
  int wickets = 0;
  int legalBalls = 0;
  int noBalls = 0;
  final List<String> balls = [];

  void apply(DeliveryResult r) {
    if (r.type == DeliveryType.retry) return;
    score += r.totalRuns;
    if (r.type == DeliveryType.noBall) noBalls++;
    if (r.legalBall) legalBalls++;
    if (r.wicket) wickets++;
    balls.add(ballCode(r));
  }
}

enum InningsStatus { continuing, inningsOver, targetReached }

InningsStatus inningsStatus({
  required InningsScore innings,
  required int maxBalls,
  required int maxWickets,
  int? target,
}) {
  if (target != null && innings.score >= target) return InningsStatus.targetReached;
  if (innings.wickets >= maxWickets || innings.legalBalls >= maxBalls) {
    return InningsStatus.inningsOver;
  }
  return InningsStatus.continuing;
}

/// Result text once both innings are done (or the chase succeeded).
String matchResultText({
  required String firstBatter,
  required String secondBatter,
  required InningsScore first,
  required InningsScore second,
  required int maxBalls,
  required int maxWickets,
}) {
  String plural(int n, String w) => '$n $w${n == 1 ? '' : 's'}';
  if (second.score > first.score) {
    return '$secondBatter won by ${plural(maxWickets - second.wickets, 'wicket')} '
        'with ${plural(maxBalls - second.legalBalls, 'ball')} remaining';
  }
  if (second.score == first.score) return 'Match tied!';
  return '$firstBatter won by ${plural(first.score - second.score, 'run')}';
}

class FingerGesture {
  final int value;
  final String emoji;
  final String label;
  const FingerGesture(this.value, this.emoji, this.label);
}

const List<FingerGesture> kGestures = [
  FingerGesture(1, '☝️', 'One finger'),
  FingerGesture(2, '✌️', 'Two fingers'),
  FingerGesture(3, '3️⃣', 'Three fingers'),
  FingerGesture(4, '4️⃣', 'Four fingers'),
  FingerGesture(5, '🖐️', 'Five fingers'),
  FingerGesture(6, '👍', 'Thumb only'),
  FingerGesture(7, '🤙', 'Thumb + pinky'),
];

String gestureEmoji(int? v) =>
    v == null ? '⌛' : kGestures.firstWhere((g) => g.value == v, orElse: () => kGestures[0]).emoji;
