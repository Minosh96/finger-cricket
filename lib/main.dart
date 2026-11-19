import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'screens/welcome_screen.dart';
import 'services/online_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppPrefs.instance.load();
  await OnlineService.instance.init();
  runApp(const FingerCricketApp());
}

class FingerCricketApp extends StatelessWidget {
  const FingerCricketApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Finger Cricket',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const WelcomeScreen(),
    );
  }
}
