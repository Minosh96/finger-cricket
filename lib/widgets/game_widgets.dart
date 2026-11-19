import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../game/game_rules.dart';

/// Seven big gesture buttons. The chosen button is NOT highlighted so the
/// opponent can never see a selection on screen.
class GesturePad extends StatelessWidget {
  final bool enabled;
  final ValueChanged<int> onPick;
  final double maxButton;

  const GesturePad({super.key, required this.enabled, required this.onPick, this.maxButton = 84});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final byWidth = (c.maxWidth - 40) / 4;
      final byHeight = c.maxHeight.isFinite ? (c.maxHeight - 16) / 2 : maxButton;
      final size = [byWidth, byHeight, maxButton].reduce((a, b) => a < b ? a : b).clamp(40.0, 120.0).toDouble();
      return Center(
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final g in kGestures)
              _GestureButton(gesture: g, size: size, enabled: enabled, onTap: () => onPick(g.value)),
          ],
        ),
      );
    });
  }
}

class _GestureButton extends StatelessWidget {
  final FingerGesture gesture;
  final double size;
  final bool enabled;
  final VoidCallback onTap;

  const _GestureButton({required this.gesture, required this.size, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.35,
      child: Material(
        color: AppColors.cardLight,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: enabled
              ? () {
                  playFx(Fx.tap);
                  onTap();
                }
              : null,
          child: SizedBox(
            width: size,
            height: size,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(gesture.emoji, style: TextStyle(fontSize: size * 0.36)),
                Text('${gesture.value}',
                    style: TextStyle(fontSize: size * 0.2, fontWeight: FontWeight.bold, color: AppColors.accent)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class Scoreboard extends StatelessWidget {
  final String battingName;
  final String bowlingName;
  final int innings;
  final int score;
  final int wickets;
  final int legalBalls;
  final int maxBalls;
  final int noBalls;
  final int? target;
  final bool compact;

  const Scoreboard({
    super.key,
    required this.battingName,
    required this.bowlingName,
    required this.innings,
    required this.score,
    required this.wickets,
    required this.legalBalls,
    required this.maxBalls,
    required this.noBalls,
    this.target,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final need = target == null ? null : target! - score;
    final ballsLeft = maxBalls - legalBalls;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: compact ? 6 : 12),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Innings $innings • 🏏 $battingName  vs  🎯 $bowlingName',
              style: const TextStyle(fontSize: 13, color: Colors.white70), textAlign: TextAlign.center),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('$score/$wickets',
                  style: TextStyle(fontSize: compact ? 28 : 40, fontWeight: FontWeight.w900, color: Colors.white)),
              const SizedBox(width: 12),
              Text('(${formatOvers(legalBalls)} / ${formatOvers(maxBalls)} ov)',
                  style: const TextStyle(fontSize: 15, color: Colors.white70)),
            ],
          ),
          Text(
            [
              'No-balls: $noBalls',
              if (need != null && need > 0) 'Need $need off $ballsLeft',
              if (target != null) 'Target $target',
            ].join('  •  '),
            style: const TextStyle(fontSize: 13, color: AppColors.accent),
          ),
        ],
      ),
    );
  }
}

class CountdownBar extends StatelessWidget {
  final int remainingMs;
  final int totalMs;

  const CountdownBar({super.key, required this.remainingMs, required this.totalMs});

  @override
  Widget build(BuildContext context) {
    final frac = (remainingMs / totalMs).clamp(0.0, 1.0).toDouble();
    final secs = (remainingMs / 1000).clamp(0, 99).ceil();
    return Row(
      children: [
        Text('⏱ $secs', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(width: 10),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: frac,
              minHeight: 12,
              color: frac > 0.34 ? AppColors.accent : AppColors.out,
              backgroundColor: Colors.white12,
            ),
          ),
        ),
      ],
    );
  }
}

class BallHistory extends StatelessWidget {
  final List<String> balls;
  const BallHistory({super.key, required this.balls});

  @override
  Widget build(BuildContext context) {
    if (balls.isEmpty) {
      return const Text('No balls bowled yet', style: TextStyle(color: Colors.white54, fontSize: 12));
    }
    final recent = balls.length > 12 ? balls.sublist(balls.length - 12) : balls;
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      alignment: WrapAlignment.center,
      children: [
        for (final b in recent)
          CircleAvatar(
            radius: 14,
            backgroundColor: b == 'W'
                ? AppColors.out
                : b == 'NB'
                    ? AppColors.noBall
                    : (b == '6' || b == '7')
                        ? AppColors.accent
                        : Colors.white24,
            child: Text(b,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: (b == '6' || b == '7') ? Colors.black : Colors.white)),
          ),
      ],
    );
  }
}

/// Reveal of one delivery: both gestures + outcome.
class RevealCard extends StatelessWidget {
  final String batterName;
  final String bowlerName;
  final int? batterMove;
  final int? bowlerMove;
  final DeliveryType type;
  final int batterRuns;

  const RevealCard({
    super.key,
    required this.batterName,
    required this.bowlerName,
    required this.batterMove,
    required this.bowlerMove,
    required this.type,
    required this.batterRuns,
  });

  @override
  Widget build(BuildContext context) {
    late final String headline;
    late final String sub;
    var color = AppColors.accent;
    switch (type) {
      case DeliveryType.runs:
        headline = '+$batterRuns ${batterRuns == 1 ? 'RUN' : 'RUNS'}';
        sub = batterRuns >= 6 ? 'What a shot!' : 'Different gestures – batter scores';
        break;
      case DeliveryType.wicket:
        headline = 'OUT! 🏏';
        sub = 'Matching gestures';
        color = AppColors.out;
        break;
      case DeliveryType.dotBall:
        headline = 'DOT BALL';
        sub = 'Batter ran out of time';
        color = Colors.white;
        break;
      case DeliveryType.noBall:
        headline = 'NO-BALL  +1';
        sub = 'Bowler ran out of time – ball doesn\'t count';
        color = AppColors.noBall;
        break;
      case DeliveryType.retry:
        headline = 'REPLAY';
        sub = 'Both players ran out of time';
        color = Colors.white;
        break;
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.6, end: 1),
      duration: const Duration(milliseconds: 350),
      curve: Curves.elasticOut,
      builder: (context, s, child) => Transform.scale(scale: s, child: child),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _MoveBubble(name: '🏏 $batterName', move: batterMove),
              const Text('vs', style: TextStyle(fontSize: 16, color: Colors.white54)),
              _MoveBubble(name: '🎯 $bowlerName', move: bowlerMove),
            ],
          ),
          const SizedBox(height: 6),
          Text(headline, style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: color)),
          Text(sub, style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }
}

class _MoveBubble extends StatelessWidget {
  final String name;
  final int? move;
  const _MoveBubble({required this.name, required this.move});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(gestureEmoji(move), style: const TextStyle(fontSize: 40)),
        Text(move == null ? 'timed out' : '$move',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.accent)),
        Text(name, style: const TextStyle(fontSize: 12, color: Colors.white70), overflow: TextOverflow.ellipsis),
      ],
    );
  }
}

/// Simple scorecard line used on the innings-break and result screens.
class InningsLine extends StatelessWidget {
  final String batter;
  final int score;
  final int wickets;
  final int legalBalls;
  final int noBalls;
  const InningsLine({
    super.key,
    required this.batter,
    required this.score,
    required this.wickets,
    required this.legalBalls,
    required this.noBalls,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Text('🏏', style: TextStyle(fontSize: 26)),
        title: Text(batter, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('${formatOvers(legalBalls)} overs • $noBalls no-ball${noBalls == 1 ? '' : 's'} • '
            '$legalBalls legal deliveries'),
        trailing: Text('$score/$wickets', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
      ),
    );
  }
}
