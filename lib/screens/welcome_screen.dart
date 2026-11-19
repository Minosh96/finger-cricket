import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/online_service.dart';
import 'how_to_play_screen.dart';
import 'local_setup_screen.dart';
import 'online_menu_screen.dart';

/// Screen 1 – Welcome: logo, nickname, Play Online, Pass & Play, How to Play, sound.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _name = TextEditingController(text: AppPrefs.instance.nickname);
  bool _sound = AppPrefs.instance.soundOn;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<bool> _saveName() async {
    final n = _name.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (n.isEmpty || n.length > 16) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Enter a nickname (1–16 characters)')));
      return false;
    }
    await AppPrefs.instance.setNickname(n);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final online = OnlineService.instance.firebaseReady;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Text('🏏 ✌️ 👍', style: TextStyle(fontSize: 56)),
                const SizedBox(height: 8),
                const Text('Finger Cricket',
                    style: TextStyle(fontSize: 38, fontWeight: FontWeight.w900, color: AppColors.accent)),
                const Text('Online Hand Cricket Challenge', style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 32),
                TextField(
                  controller: _name,
                  maxLength: 16,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Your nickname',
                    prefixIcon: Icon(Icons.person),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  icon: const Icon(Icons.public),
                  label: const Text('Play Online'),
                  onPressed: () async {
                    if (!await _saveName() || !context.mounted) return;
                    if (!online) {
                      showDialog<void>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('Online play not set up'),
                          content: const Text('This build has no Firebase project connected yet.\n\n'
                              'Use Pass & Play for now, or follow README → Part B to switch on online play.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
                          ],
                        ),
                      );
                      return;
                    }
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const OnlineMenuScreen()));
                  },
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.cardLight, foregroundColor: Colors.white),
                  icon: const Icon(Icons.people),
                  label: const Text('Pass & Play (1 phone)'),
                  onPressed: () async {
                    if (!await _saveName() || !context.mounted) return;
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const LocalSetupScreen()));
                  },
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  icon: const Icon(Icons.menu_book),
                  label: const Text('How to Play'),
                  onPressed: () =>
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const HowToPlayScreen())),
                ),
                SwitchListTile(
                  title: const Text('Sound & vibration'),
                  value: _sound,
                  onChanged: (v) {
                    setState(() => _sound = v);
                    AppPrefs.instance.setSound(v);
                  },
                ),
                if (!online)
                  const Text('Offline build – online play turns on after Firebase setup',
                      style: TextStyle(fontSize: 12, color: Colors.white38)),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: const SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(bottom: 12, top: 4),
          child: Text(
            'Developed by Melow',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.white54),
          ),
        ),
      ),
    );
  }
}
