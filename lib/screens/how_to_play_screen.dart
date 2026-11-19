import 'package:flutter/material.dart';

import '../game/game_rules.dart';

class HowToPlayScreen extends StatelessWidget {
  const HowToPlayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('How to Play')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _H('Gestures'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final g in kGestures)
                Chip(label: Text('${g.emoji}  ${g.value} – ${g.label}')),
            ],
          ),
          const _H('Each ball'),
          const _P('Batter and bowler secretly tap a gesture within 3 seconds.\n'
              '• Same number → the batter is OUT.\n'
              '• Different numbers → the batter scores their own number.'),
          const _H('Running out of time'),
          const _P('• Bowler doesn\'t choose → NO-BALL: +1 run, the ball does not count.\n'
              '• Batter doesn\'t choose → DOT BALL: 0 runs, counts as a ball.\n'
              '• Neither chooses → the ball is replayed.\n'
              '• Miss 4 balls in a row online → you forfeit.'),
          const _H('Match'),
          const _P('• Coin toss – the winner chooses to bat or bowl.\n'
              '• 1 wicket per innings, 2 overs (6 legal balls each) by default.\n'
              '• Second batter must beat the first score. The chase ends as soon as they pass it.\n'
              '• Same score → tie. Rematch when both players agree.'),
          const _H('Pass & Play'),
          const _P('Two players share one phone, sitting face to face. '
              'Each player uses their own half of the screen. Your choice is never highlighted.'),
        ],
      ),
    );
  }
}

class _H extends StatelessWidget {
  final String t;
  const _H(this.t);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(t, style: Theme.of(context).textTheme.titleLarge),
      );
}

class _P extends StatelessWidget {
  final String t;
  const _P(this.t);
  @override
  Widget build(BuildContext context) => Text(t, style: const TextStyle(fontSize: 15, height: 1.5));
}
