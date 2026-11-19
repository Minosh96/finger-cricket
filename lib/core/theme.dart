import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppColors {
  static const pitch = Color(0xFF0B3D2E);
  static const card = Color(0xFF145A43);
  static const cardLight = Color(0xFF1E7A5C);
  static const accent = Color(0xFFFFC145);
  static const out = Color(0xFFE5484D);
  static const noBall = Color(0xFF4EA8FF);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.cardLight,
    brightness: Brightness.dark,
    primary: AppColors.accent,
    surface: AppColors.pitch,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.pitch,
    appBarTheme: const AppBarTheme(backgroundColor: AppColors.pitch, centerTitle: true),
    cardTheme: const CardThemeData(color: AppColors.card),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.black,
        minimumSize: const Size(200, 52),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
  );
}

/// Locally stored preferences: nickname + sound/vibration toggle.
class AppPrefs {
  AppPrefs._();
  static final AppPrefs instance = AppPrefs._();

  SharedPreferences? _prefs;
  String nickname = '';
  bool soundOn = true;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    nickname = _prefs!.getString('nickname') ?? '';
    soundOn = _prefs!.getBool('soundOn') ?? true;
  }

  Future<void> setNickname(String v) async {
    nickname = v;
    await _prefs?.setString('nickname', v);
  }

  Future<void> setSound(bool v) async {
    soundOn = v;
    await _prefs?.setBool('soundOn', v);
  }
}

enum Fx { tap, runs, wicket, noBall }

/// Tiny built-in feedback (no audio assets needed).
void playFx(Fx fx) {
  if (!AppPrefs.instance.soundOn) return;
  switch (fx) {
    case Fx.tap:
      HapticFeedback.selectionClick();
      break;
    case Fx.runs:
      SystemSound.play(SystemSoundType.click);
      HapticFeedback.lightImpact();
      break;
    case Fx.wicket:
      SystemSound.play(SystemSoundType.alert);
      HapticFeedback.heavyImpact();
      break;
    case Fx.noBall:
      SystemSound.play(SystemSoundType.click);
      HapticFeedback.mediumImpact();
      break;
  }
}
