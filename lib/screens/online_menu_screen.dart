import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../services/online_service.dart';
import 'online_game_screen.dart';

/// Screen 2 – Create or Join a room.
class OnlineMenuScreen extends StatefulWidget {
  const OnlineMenuScreen({super.key});

  @override
  State<OnlineMenuScreen> createState() => _OnlineMenuScreenState();
}

class _OnlineMenuScreenState extends State<OnlineMenuScreen> {
  final _code = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    OnlineService.instance.callQuietly('ping'); // wake the server up early
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(String action, Map<String, dynamic> data) async {
    setState(() => _busy = true);
    try {
      final res = await OnlineService.instance.call(action, data);
      final code = res['code']?.toString();
      if (code == null || !mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => OnlineGameScreen(code: code)));
    } catch (e) {
      if (mounted) {
        final msg = e.toString();
        showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Could not connect'),
            content: SelectableText(msg),
            actions: [
              TextButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: msg));
                  Navigator.pop(ctx);
                },
                child: const Text('Copy'),
              ),
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = AppPrefs.instance.nickname;
    return Scaffold(
      appBar: AppBar(title: const Text('Play Online')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('Playing as $name', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Create Room'),
              onPressed: () => _run('createRoom', {'name': name}),
            ),
            const SizedBox(height: 40),
            const Divider(),
            const SizedBox(height: 16),
            TextField(
              controller: _code,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 28, letterSpacing: 8, fontWeight: FontWeight.bold),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: '6-digit room code', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.cardLight, foregroundColor: Colors.white),
              icon: const Icon(Icons.login),
              label: const Text('Join Room'),
              onPressed: () {
                final code = _code.text.trim();
                if (code.length != 6) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('Room codes have 6 digits')));
                  return;
                }
                _run('joinRoom', {'code': code, 'name': name});
              },
            ),
            if (_busy) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          ],
        ),
      ),
    );
  }
}
