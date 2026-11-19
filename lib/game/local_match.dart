import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/theme.dart';
import 'game_rules.dart';

enum LocalPhase { tossChoice, prep, selecting, reveal, inningsBreak, completed }

/// Offline "Pass & Play": two players share one phone, sitting face to face.
/// Player 0 uses the bottom half, player 1 the (upside-down) top half.
class LocalMatchController extends ChangeNotifier {
  static const int selectMs = 3000;
  static const int prepMs = 1500;
  static const int revealMs = 2000;
  static const int maxWickets = 1;

  final List<String> names;
  final int overs;
  final Random _rng = Random();

  LocalMatchController({required String player0, required String player1, required this.overs})
      : names = [player0, player1] {
    _toss();
  }

  LocalPhase phase = LocalPhase.tossChoice;
  int tossWinner = 0;
  int batter = 0;
  int innings = 1;
  InningsScore current = InningsScore();
  InningsScore? first;
  int? target;
  final List<int?> moves = [null, null];
  DeliveryResult? lastResult;
  List<int?> lastMoves = [null, null];
  int lastBatter = 0;
  DateTime _deadline = DateTime.now();
  String resultText = '';
  final Stopwatch matchClock = Stopwatch();

  Timer? _phaseTimer;
  Timer? _uiTimer;

  int get bowler => 1 - batter;
  int get maxBalls => overs * 6;
  int get remainingMs => max(0, _deadline.difference(DateTime.now()).inMilliseconds);

  void _toss() {
    tossWinner = _rng.nextBool() ? 0 : 1;
    phase = LocalPhase.tossChoice;
  }

  void chooseBatBowl(bool bat) {
    if (phase != LocalPhase.tossChoice) return;
    batter = bat ? tossWinner : 1 - tossWinner;
    innings = 1;
    first = null;
    target = null;
    matchClock
      ..reset()
      ..start();
    _startInnings();
  }

  void _startInnings() {
    current = InningsScore();
    lastResult = null;
    phase = LocalPhase.prep;
    notifyListeners();
    _phaseTimer?.cancel();
    _phaseTimer = Timer(const Duration(milliseconds: prepMs), _startSelecting);
  }

  void _startSelecting() {
    moves[0] = null;
    moves[1] = null;
    phase = LocalPhase.selecting;
    _deadline = DateTime.now().add(const Duration(milliseconds: selectMs));
    _phaseTimer?.cancel();
    _phaseTimer = Timer(const Duration(milliseconds: selectMs), _resolve);
    _uiTimer?.cancel();
    _uiTimer = Timer.periodic(const Duration(milliseconds: 100), (_) => notifyListeners());
    notifyListeners();
  }

  void select(int player, int move) {
    if (phase != LocalPhase.selecting || moves[player] != null) return;
    moves[player] = move; // locked
    notifyListeners();
    if (moves[0] != null && moves[1] != null) _resolve();
  }

  void _resolve() {
    if (phase != LocalPhase.selecting) return;
    _phaseTimer?.cancel();
    _uiTimer?.cancel();
    final r = evaluateDelivery(batterMove: moves[batter], bowlerMove: moves[bowler]);
    lastResult = r;
    lastMoves = [moves[0], moves[1]];
    lastBatter = batter;
    current.apply(r);
    playFx(r.wicket
        ? Fx.wicket
        : r.type == DeliveryType.noBall
            ? Fx.noBall
            : Fx.runs);
    phase = LocalPhase.reveal;
    notifyListeners();
    _phaseTimer = Timer(const Duration(milliseconds: revealMs), _afterReveal);
  }

  void _afterReveal() {
    final status = inningsStatus(
        innings: current, maxBalls: maxBalls, maxWickets: maxWickets, target: innings == 2 ? target : null);
    if (status == InningsStatus.continuing) {
      _startSelecting();
      return;
    }
    if (innings == 1) {
      first = current;
      target = current.score + 1;
      phase = LocalPhase.inningsBreak;
    } else {
      matchClock.stop();
      resultText = matchResultText(
        firstBatter: names[bowler], // roles swapped for innings 2
        secondBatter: names[batter],
        first: first!,
        second: current,
        maxBalls: maxBalls,
        maxWickets: maxWickets,
      );
      phase = LocalPhase.completed;
    }
    notifyListeners();
  }

  void startSecondInnings() {
    if (phase != LocalPhase.inningsBreak) return;
    innings = 2;
    batter = 1 - batter;
    _startInnings();
  }

  void rematch() {
    _phaseTimer?.cancel();
    _uiTimer?.cancel();
    first = null;
    target = null;
    current = InningsScore();
    lastResult = null;
    _toss();
    notifyListeners();
  }

  @override
  void dispose() {
    _phaseTimer?.cancel();
    _uiTimer?.cancel();
    super.dispose();
  }
}
