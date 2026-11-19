import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../game/game_rules.dart';
import '../models/room.dart';
import '../services/online_service.dart';
import '../widgets/game_widgets.dart';

/// One screen that follows the room through every phase:
/// Lobby → Toss → Live Match / Ball Result → Innings Break → Final Result.
/// The server (Cloud Functions) controls every transition.
class OnlineGameScreen extends StatefulWidget {
  final String code;
  const OnlineGameScreen({super.key, required this.code});

  @override
  State<OnlineGameScreen> createState() => _OnlineGameScreenState();
}

class _OnlineGameScreenState extends State<OnlineGameScreen> {
  final svc = OnlineService.instance;
  late final String uid = svc.uid!;
  StreamSubscription<Object?>? _sub;
  Timer? _ticker;
  RoomView? room;
  String? fatal;
  bool busy = false;

  String? _lockedRoundKey; // round I already submitted for
  String? _tickRoundKey;
  int _tickSentAt = 0;
  String? _lastFxRound;

  String get code => widget.code;

  @override
  void initState() {
    super.initState();
    _sub = svc.roomStream(code).listen(_onRoom, onError: (Object e) {
      if (mounted) setState(() => fatal = 'You no longer have access to this room.');
    });
    svc.startPresence(code, uid);
    svc.callQuietly('ping');
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) => _onTick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _sub?.cancel();
    svc.stopPresence();
    super.dispose();
  }

  void _onRoom(Object? raw) {
    if (!mounted) return;
    if (raw == null) {
      setState(() => fatal = 'This room was closed.');
      return;
    }
    final r = RoomView.fromRaw(code, raw);
    final lr = r.match?.lastResult;
    if (lr != null && lr.roundKey != _lastFxRound) {
      _lastFxRound = lr.roundKey;
      final t = deliveryTypeFromServer(lr.type);
      playFx(t == DeliveryType.wicket
          ? Fx.wicket
          : t == DeliveryType.noBall
              ? Fx.noBall
              : Fx.runs);
    }
    setState(() => room = r);
  }

  /// 10×/second: redraw the countdown and ask the server to resolve the
  /// delivery once both moves are locked or the deadline has passed.
  void _onTick() {
    final r = room;
    if (r == null || r.status != 'playing') return;
    setState(() {});
    final m = r.match;
    if (m == null || m.roundKey.isEmpty) return;
    final locks = r.locks[m.roundKey] ?? const <String>{};
    final both = locks.contains(m.batterUid) && locks.contains(m.bowlerUid);
    final due = both || svc.serverNow > m.deadlineAt + 1100;
    if (!due) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_tickRoundKey == m.roundKey && now - _tickSentAt < 2500) return;
    _tickRoundKey = m.roundKey;
    _tickSentAt = now;
    svc.callQuietly('tick', {'code': code, 'roundKey': m.roundKey});
  }

  Future<void> _action(String action, [Map<String, dynamic> extra = const {}]) async {
    setState(() => busy = true);
    try {
      await svc.call(action, {'code': code, ...extra});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _pick(int move) async {
    final m = room?.match;
    if (m == null || _lockedRoundKey == m.roundKey) return;
    final key = m.roundKey;
    setState(() => _lockedRoundKey = key);
    try {
      await svc.submitMove(code, key, uid, move);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Too late – the server deadline had passed')));
      }
    }
  }

  Future<void> _leave() async {
    final status = room?.status;
    final inMatch = status == 'toss' || status == 'playing' || status == 'innings_break';
    if (inMatch) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Leave match?'),
          content: const Text('Leaving now gives your opponent the win.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Stay')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Leave')),
          ],
        ),
      );
      if (ok != true) return;
    }
    svc.stopPresence();
    svc.callQuietly('leaveRoom', {'code': code});
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Room $code'),
          leading: IconButton(icon: const Icon(Icons.close), onPressed: _leave),
        ),
        body: SafeArea(child: _body()),
      ),
    );
  }

  Widget _body() {
    if (fatal != null) {
      return _centered([
        Text(fatal!, style: const TextStyle(fontSize: 18)),
        const SizedBox(height: 16),
        ElevatedButton(onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst), child: const Text('Home')),
      ]);
    }
    final r = room;
    if (r == null) return const Center(child: CircularProgressIndicator());
    switch (r.status) {
      case 'waiting':
      case 'lobby':
        return _lobby(r);
      case 'toss':
        return _toss(r);
      case 'playing':
        return _match(r);
      case 'innings_break':
        return _inningsBreak(r);
      case 'completed':
      case 'abandoned':
        return _result(r);
      default:
        return _centered([Text('Unknown state: ${r.status}')]);
    }
  }

  Widget _centered(List<Widget> children) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: children),
        ),
      );

  // ---------------- Screen 3 – Lobby ----------------
  Widget _lobby(RoomView r) {
    final me = r.player(uid);
    final isHost = r.hostUid == uid;
    return _centered([
      const Text('Room code', style: TextStyle(color: Colors.white70)),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(code, style: const TextStyle(fontSize: 44, letterSpacing: 6, fontWeight: FontWeight.w900)),
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code copied')));
            },
          ),
        ],
      ),
      const SizedBox(height: 16),
      for (final p in r.players)
        Card(
          child: ListTile(
            leading: Icon(Icons.circle, size: 14, color: p.connected ? Colors.greenAccent : Colors.redAccent),
            title: Text('${p.name}${p.uid == uid ? ' (you)' : ''}${p.uid == r.hostUid ? ' ⭐' : ''}'),
            trailing: Text(p.ready ? '✅ Ready' : 'Not ready'),
          ),
        ),
      if (r.players.length < 2)
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text('Waiting for your friend to join with this code…', style: TextStyle(color: Colors.white70)),
        ),
      const SizedBox(height: 12),
      Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('Overs: '),
          if (isHost)
            DropdownButton<int>(
              value: r.overs,
              items: [for (var o = 1; o <= 10; o++) DropdownMenuItem(value: o, child: Text('$o'))],
              onChanged: busy ? null : (v) => v == null ? null : _action('setOvers', {'overs': v}),
            )
          else
            Text('${r.overs}', style: const TextStyle(fontWeight: FontWeight.bold)),
          const Text('  •  1 wicket  •  3 s per ball'),
        ],
      ),
      const SizedBox(height: 20),
      ElevatedButton(
        onPressed: (busy || r.players.length < 2 || (me?.ready ?? false)) ? null : () => _action('ready'),
        child: Text((me?.ready ?? false) ? 'Waiting for opponent…' : 'I\'m Ready'),
      ),
    ]);
  }

  // ---------------- Screen 4 – Toss ----------------
  Widget _toss(RoomView r) {
    final won = r.tossWinnerUid == uid;
    return _centered([
      TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 6.283 * 3),
        duration: const Duration(milliseconds: 1200),
        curve: Curves.easeOut,
        builder: (context, a, _) =>
            Transform(alignment: Alignment.center, transform: Matrix4.rotationX(a), child: const Text('🪙', style: TextStyle(fontSize: 90))),
      ),
      const SizedBox(height: 16),
      Text(won ? 'You won the toss!' : '${r.nameOf(r.tossWinnerUid)} won the toss',
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
      const SizedBox(height: 20),
      if (won) ...[
        ElevatedButton(onPressed: busy ? null : () => _action('chooseBatBowl', {'choice': 'bat'}), child: const Text('🏏 Bat First')),
        const SizedBox(height: 12),
        ElevatedButton(onPressed: busy ? null : () => _action('chooseBatBowl', {'choice': 'bowl'}), child: const Text('🎯 Bowl First')),
      ] else
        const Text('Waiting for their choice…', style: TextStyle(color: Colors.white70)),
    ]);
  }

  // ---------------- Screens 5 & 6 – Live match + ball result ----------------
  Widget _match(RoomView r) {
    final m = r.match!;
    final now = svc.serverNow;
    final amBatter = m.batterUid == uid;
    final oppUid = r.opponentOf(uid);
    final opp = oppUid == null ? null : r.player(oppUid);
    final locks = r.locks[m.roundKey] ?? const <String>{};
    final iLocked = _lockedRoundKey == m.roundKey || locks.contains(uid);
    final oppLocked = oppUid != null && locks.contains(oppUid);
    final selecting = now >= m.startAt && now <= m.deadlineAt;

    Widget centre;
    if (now < m.startAt) {
      final lr = m.lastResult;
      centre = lr == null
          ? Text(amBatter ? 'Get ready – you are BATTING 🏏' : 'Get ready – you are BOWLING 🎯',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))
          : RevealCard(
              batterName: r.nameOf(lr.batterUid),
              bowlerName: r.nameOf(lr.bowlerUid),
              batterMove: lr.batterMove,
              bowlerMove: lr.bowlerMove,
              type: deliveryTypeFromServer(lr.type),
              batterRuns: lr.batterRuns,
            );
    } else if (selecting) {
      centre = Column(children: [
        CountdownBar(remainingMs: m.deadlineAt - now, totalMs: r.selectionMs),
        const SizedBox(height: 6),
        Text(amBatter ? 'Pick your shot!' : 'Bowl a number!', style: const TextStyle(fontSize: 18)),
      ]);
    } else {
      centre = const Column(children: [
        SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 3)),
        SizedBox(height: 8),
        Text('Umpire checking…'),
      ]);
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Scoreboard(
            battingName: r.nameOf(m.batterUid),
            bowlingName: r.nameOf(m.bowlerUid),
            innings: m.innings,
            score: m.score,
            wickets: m.wickets,
            legalBalls: m.legalBalls,
            maxBalls: r.maxBalls,
            noBalls: m.noBalls,
            target: m.target,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(iLocked && selecting ? '🔒 You: locked' : '🙂 You: ${amBatter ? 'batting' : 'bowling'}'),
              Row(children: [
                Icon(Icons.circle, size: 10, color: (opp?.connected ?? false) ? Colors.greenAccent : Colors.redAccent),
                const SizedBox(width: 4),
                Text(oppLocked && selecting
                    ? '${opp?.name ?? 'Opponent'}: 🔒 locked'
                    : '${opp?.name ?? 'Opponent'}${(opp?.connected ?? false) ? '' : ' (offline)'}'),
              ]),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(flex: 4, child: Center(child: centre)),
          BallHistory(balls: m.balls),
          const SizedBox(height: 8),
          Expanded(
            flex: 5,
            child: Stack(
              children: [
                GesturePad(enabled: selecting && !iLocked, onPick: _pick),
                if (selecting && iLocked)
                  const Center(
                    child: Card(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        child: Text('🔒 Move locked', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- Screen 7 – Innings break ----------------
  Widget _inningsBreak(RoomView r) {
    final m = r.match!;
    final lr = m.lastResult;
    final iAmReady = r.breakReady.contains(uid);
    return _centered([
      if (lr != null)
        RevealCard(
          batterName: r.nameOf(lr.batterUid),
          bowlerName: r.nameOf(lr.bowlerUid),
          batterMove: lr.batterMove,
          bowlerMove: lr.bowlerMove,
          type: deliveryTypeFromServer(lr.type),
          batterRuns: lr.batterRuns,
        ),
      const SizedBox(height: 16),
      const Text('Innings Break', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
      InningsLine(
          batter: r.nameOf(m.batterUid), score: m.score, wickets: m.wickets, legalBalls: m.legalBalls, noBalls: m.noBalls),
      const SizedBox(height: 8),
      Text('Target: ${m.score + 1} off ${r.maxBalls} balls',
          style: const TextStyle(fontSize: 20, color: AppColors.accent, fontWeight: FontWeight.bold)),
      Text('${r.nameOf(m.bowlerUid)} bats next • ${r.nameOf(m.batterUid)} bowls',
          style: const TextStyle(color: Colors.white70)),
      const SizedBox(height: 20),
      ElevatedButton(
        onPressed: (busy || iAmReady) ? null : () => _action('ready'),
        child: Text(iAmReady ? 'Waiting for opponent…' : 'Ready for 2nd innings'),
      ),
    ]);
  }

  // ---------------- Screen 8 – Final result ----------------
  Widget _result(RoomView r) {
    final res = r.result;
    final m = r.match;
    final won = res?.winnerUid == uid;
    final oppUid = r.opponentOf(uid);
    final oppLeft = oppUid == null || (r.player(oppUid)?.left ?? false);
    final iAskedRematch = r.rematch.contains(uid);
    final duration = (m != null && res != null && res.endedAt > m.startedAt)
        ? Duration(milliseconds: res.endedAt - m.startedAt)
        : null;
    final shareText = StringBuffer('🏏 Finger Cricket – ${res?.text ?? 'Match over'}\n');
    final lines = <Widget>[];
    if (m != null) {
      final f = m.first;
      if (f != null) {
        lines.add(InningsLine(
            batter: r.nameOf(f.batterUid), score: f.score, wickets: f.wickets, legalBalls: f.legalBalls, noBalls: f.noBalls));
        shareText.writeln('${r.nameOf(f.batterUid)}: ${f.score}/${f.wickets} (${formatOvers(f.legalBalls)} ov)');
      }
      lines.add(InningsLine(
          batter: r.nameOf(m.batterUid), score: m.score, wickets: m.wickets, legalBalls: m.legalBalls, noBalls: m.noBalls));
      shareText.writeln('${r.nameOf(m.batterUid)}: ${m.score}/${m.wickets} (${formatOvers(m.legalBalls)} ov)');
    }
    return _centered([
      Text(res?.tie == true ? '🤝' : (won ? '🏆' : '🏏'), style: const TextStyle(fontSize: 64)),
      Text(res?.tie == true ? 'It\'s a tie!' : (won ? 'You won!' : (res?.winnerUid == null ? 'Match over' : 'You lost')),
          style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: AppColors.accent)),
      const SizedBox(height: 4),
      Text(res?.text ?? '', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18)),
      const SizedBox(height: 12),
      ...lines,
      if (duration != null)
        Text('Match time ${duration.inMinutes}m ${duration.inSeconds % 60}s',
            style: const TextStyle(color: Colors.white54)),
      const SizedBox(height: 20),
      if (r.status == 'completed')
        ElevatedButton(
          onPressed: (busy || oppLeft || iAskedRematch) ? null : () => _action('requestRematch'),
          child: Text(oppLeft
              ? 'Opponent left'
              : iAskedRematch
                  ? 'Waiting for opponent…'
                  : (r.rematch.isNotEmpty ? 'Accept Rematch' : 'Rematch')),
        ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        icon: const Icon(Icons.share),
        label: const Text('Copy result to share'),
        onPressed: () {
          Clipboard.setData(ClipboardData(text: shareText.toString()));
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Result copied – paste it anywhere')));
        },
      ),
      TextButton(onPressed: _leave, child: const Text('Home')),
    ]);
  }
}
