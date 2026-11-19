import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'local_match_screen.dart';

class LocalSetupScreen extends StatefulWidget {
  const LocalSetupScreen({super.key});

  @override
  State<LocalSetupScreen> createState() => _LocalSetupScreenState();
}

class _LocalSetupScreenState extends State<LocalSetupScreen> {
  final _p2 = TextEditingController(text: 'Player 2');
  int _overs = 2;

  @override
  void dispose() {
    _p2.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pass & Play')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          ListTile(
            leading: const Icon(Icons.person),
            title: Text(AppPrefs.instance.nickname),
            subtitle: const Text('Player 1 – bottom of the screen'),
          ),
          TextField(
            controller: _p2,
            maxLength: 16,
            decoration: const InputDecoration(
              labelText: 'Player 2 (top of the screen, upside down)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Overs per innings'),
          Wrap(
            spacing: 8,
            children: [
              for (final o in [1, 2, 3, 5])
                ChoiceChip(label: Text('$o'), selected: _overs == o, onSelected: (_) => setState(() => _overs = o)),
            ],
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () {
              final p2 = _p2.text.trim().isEmpty ? 'Player 2' : _p2.text.trim();
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => LocalMatchScreen(player0: AppPrefs.instance.nickname, player1: p2, overs: _overs),
                ),
              );
            },
            child: const Text('Start – toss the coin'),
          ),
        ],
      ),
    );
  }
}
