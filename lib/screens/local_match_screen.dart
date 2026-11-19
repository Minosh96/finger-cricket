import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../game/game_rules.dart';
import '../game/local_match.dart';
import '../widgets/game_widgets.dart';

/// Offline match on one phone. Top half is rotated 180° for player 2.
class LocalMatchScreen extends StatefulWidget {
  final String player0;
  final String player1;
  final int overs;

  const LocalMatchScreen({super.key, required this.player0, required this.player1, required this.overs});

  @override
  State<LocalMatchScreen> createState() => _LocalMatchScreenState();
}

class _LocalMatchScreenState extends State<LocalMatchScreen> {
  late final LocalMatchController c =
      LocalMatchController(player0: widget.player0, player1: widget.player1, overs: widget.overs);

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: AnimatedBuilder(
          animation: c,
          builder: (context, _) {
            final overlay = c.phase == LocalPhase.inningsBreak || c.phase == LocalPhase.completed;
            return Stack(
              children: [
                Column(
                  children: [
                    Expanded(child: RotatedBox(quarterTurns: 2, child: _PlayerHalf(c: c, idx: 1))),
                    _CenterStrip(c: c),
                    Expanded(child: _PlayerHalf(c: c, idx: 0)),
                  ],
                ),
                if (overlay) Positioned.fill(child: _Overlay(c: c)),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PlayerHalf extends StatelessWidget {
  final LocalMatchController c;
  final int idx;
  const _PlayerHalf({required this.c, required this.idx});

  @override
  Widget build(BuildContext context) {
    final batting = c.phase != LocalPhase.tossChoice && c.batter == idx;
    final role = c.phase == LocalPhase.tossChoice ? '' : (batting ? '🏏 BATTING' : '🎯 BOWLING');
    Widget body;
    switch (c.phase) {
      case LocalPhase.tossChoice:
        body = c.tossWinner == idx
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('🪙 You won the toss!', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton(
                          style: ElevatedButton.styleFrom(minimumSize: const Size(120, 52)),
                          onPressed: () => c.chooseBatBowl(true),
                          child: const Text('Bat')),
                      const SizedBox(width: 12),
                      ElevatedButton(
                          style: ElevatedButton.styleFrom(minimumSize: const Size(120, 52)),
                          onPressed: () => c.chooseBatBowl(false),
                          child: const Text('Bowl')),
                    ],
                  ),
                ],
              )
            : Center(
                child: Text('🪙 ${c.names[c.tossWinner]} won the toss…',
                    style: const TextStyle(fontSize: 18, color: Colors.white70))),
        break;
      case LocalPhase.prep:
        body = const Center(child: Text('Get ready…', style: TextStyle(fontSize: 24)));
        break;
      case LocalPhase.selecting:
        final locked = c.moves[idx] != null;
        body = Stack(
          children: [
            GesturePad(enabled: !locked, onPick: (v) => c.select(idx, v)),
            if (locked)
              const Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    child: Text('🔒 Move locked', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
          ],
        );
        break;
      case LocalPhase.reveal:
      case LocalPhase.inningsBreak:
      case LocalPhase.completed:
        final m = c.lastMoves[idx];
        body = Center(
          child: Text(m == null ? 'You ran out of time' : 'You chose ${gestureEmoji(m)} $m',
              style: const TextStyle(fontSize: 20, color: Colors.white70)),
        );
        break;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(c.names[idx],
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
              ),
              Text(role, style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(child: body),
        ],
      ),
    );
  }
}

class _CenterStrip extends StatelessWidget {
  final LocalMatchController c;
  const _CenterStrip({required this.c});

  @override
  Widget build(BuildContext context) {
    if (c.phase == LocalPhase.tossChoice) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: Text('🏏 Finger Cricket', style: TextStyle(fontSize: 20, color: AppColors.accent)),
      );
    }
    Widget middle;
    if (c.phase == LocalPhase.selecting) {
      middle = CountdownBar(remainingMs: c.remainingMs, totalMs: LocalMatchController.selectMs);
    } else if (c.lastResult != null && c.phase == LocalPhase.reveal) {
      final r = c.lastResult!;
      final b = c.lastBatter;
      middle = RevealCard(
        batterName: c.names[b],
        bowlerName: c.names[1 - b],
        batterMove: c.lastMoves[b],
        bowlerMove: c.lastMoves[1 - b],
        type: r.type,
        batterRuns: r.batterRuns,
      );
    } else {
      middle = const SizedBox(height: 12);
    }
    return Container(
      color: Colors.black26,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Scoreboard(
            battingName: c.names[c.batter],
            bowlingName: c.names[c.bowler],
            innings: c.innings,
            score: c.current.score,
            wickets: c.current.wickets,
            legalBalls: c.current.legalBalls,
            maxBalls: c.maxBalls,
            noBalls: c.current.noBalls,
            target: c.innings == 2 ? c.target : null,
            compact: true,
          ),
          const SizedBox(height: 6),
          middle,
          const SizedBox(height: 4),
          BallHistory(balls: c.current.balls),
        ],
      ),
    );
  }
}

class _Overlay extends StatelessWidget {
  final LocalMatchController c;
  const _Overlay({required this.c});

  @override
  Widget build(BuildContext context) {
    final f = c.first!;
    final firstBatter = c.innings == 1 ? c.batter : c.bowler;
    final children = <Widget>[];
    if (c.phase == LocalPhase.inningsBreak) {
      children.addAll([
        const Text('Innings Break', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
        const SizedBox(height: 12),
        InningsLine(
            batter: c.names[firstBatter],
            score: f.score,
            wickets: f.wickets,
            legalBalls: f.legalBalls,
            noBalls: f.noBalls),
        const SizedBox(height: 12),
        Text('${c.names[c.bowler]} needs ${c.target} to win off ${c.maxBalls} balls',
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, color: AppColors.accent)),
        Text('${c.names[c.bowler]} bats • ${c.names[c.batter]} bowls', style: const TextStyle(color: Colors.white70)),
        const SizedBox(height: 20),
        ElevatedButton(onPressed: c.startSecondInnings, child: const Text('Both ready – start')),
      ]);
    } else {
      final mins = c.matchClock.elapsed.inMinutes;
      final secs = c.matchClock.elapsed.inSeconds % 60;
      children.addAll([
        const Text('🏆', style: TextStyle(fontSize: 56)),
        Text(c.resultText,
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
        const SizedBox(height: 12),
        InningsLine(
            batter: c.names[c.bowler], score: f.score, wickets: f.wickets, legalBalls: f.legalBalls, noBalls: f.noBalls),
        InningsLine(
            batter: c.names[c.batter],
            score: c.current.score,
            wickets: c.current.wickets,
            legalBalls: c.current.legalBalls,
            noBalls: c.current.noBalls),
        Text('Match time ${mins}m ${secs}s', style: const TextStyle(color: Colors.white54)),
        const SizedBox(height: 20),
        ElevatedButton(onPressed: c.rematch, child: const Text('Rematch')),
        const SizedBox(height: 8),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Home')),
      ]);
    }
    return Container(
      color: Colors.black87,
      alignment: Alignment.center,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}
