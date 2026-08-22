import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeService extends ChangeNotifier {
  ThemeService._();
  static final ThemeService instance = ThemeService._();

  static const _key = 'theme_mode';
  static const _textScaleKey = 'text_scale';

  ThemeMode _mode = ThemeMode.system;
  double _textScale = 1.0;

  ThemeMode get mode => _mode;
  bool get isDark => _mode == ThemeMode.dark;
  double get textScale => _textScale;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final savedScale = prefs.getDouble(_textScaleKey);
    if (savedScale != null) {
      _textScale = savedScale.clamp(0.85, 1.25).toDouble();
    }

    switch (prefs.getString(_key)) {
      case 'light':
        _mode = ThemeMode.light;
        break;
      case 'dark':
        _mode = ThemeMode.dark;
        break;
      default:
        _mode = ThemeMode.system;
    }
  }

  Future<void> setTextScale(double value) async {
    final next = value.clamp(0.85, 1.25).toDouble();
    if ((_textScale - next).abs() < 0.001) return;
    _textScale = next;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_textScaleKey, next);
  }

  Future<void> resetTextScale() => setTextScale(1.0);

  Future<void> setMode(ThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      },
    );
  }
}
