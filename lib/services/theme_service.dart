import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeService extends ChangeNotifier {
  ThemeService._();
  static final ThemeService instance = ThemeService._();

  static const _key = 'theme_mode';
  static const _textScaleKey = 'text_scale';
  static const _customFontPathKey = 'custom_font_path';
  static const _customFontNameKey = 'custom_font_name';
  static const _customFontFamilyKey = 'custom_font_family';

  ThemeMode _mode = ThemeMode.system;
  double _textScale = 1.0;
  String? _customFontPath;
  String? _customFontName;
  String? _customFontFamily;

  ThemeMode get mode => _mode;
  bool get isDark => _mode == ThemeMode.dark;
  double get textScale => _textScale;
  bool get hasCustomFont => _customFontFamily != null;
  String? get customFontName => _customFontName;
  String? get customFontFamily => _customFontFamily;

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

    final fontPath = prefs.getString(_customFontPathKey);
    final fontName = prefs.getString(_customFontNameKey);
    final fontFamily = prefs.getString(_customFontFamilyKey);
    if (fontPath != null && fontName != null && fontFamily != null) {
      try {
        final file = File(fontPath);
        if (!await file.exists()) {
          throw FileSystemException(
            '自定义字体文件不存在',
            fontPath,
          );
        }
        await _loadFont(await file.readAsBytes(), fontFamily);
        _customFontPath = fontPath;
        _customFontName = fontName;
        _customFontFamily = fontFamily;
      } catch (_) {
        await prefs.remove(_customFontPathKey);
        await prefs.remove(_customFontNameKey);
        await prefs.remove(_customFontFamilyKey);
      }
    }
  }

  Future<void> installCustomFont(Uint8List bytes, String fileName) async {
    if (bytes.isEmpty) throw const FormatException('字体文件为空');
    final extension = fileName.toLowerCase().split('.').last;
    if (extension != 'ttf' && extension != 'otf') {
      throw const FormatException('仅支持 TTF 和 OTF 字体');
    }

    final family = 'MTForumCustomFont_${DateTime.now().microsecondsSinceEpoch}';
    await _loadFont(bytes, family);

    final directory = await getApplicationSupportDirectory();
    final file = File('${directory.path}/mtforum_custom_font.$extension');
    await file.writeAsBytes(bytes, flush: true);

    final previousPath = _customFontPath;
    _customFontPath = file.path;
    _customFontName = fileName.trim().isEmpty ? '自定义字体' : fileName.trim();
    _customFontFamily = family;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_customFontPathKey, file.path);
    await prefs.setString(_customFontNameKey, _customFontName!);
    await prefs.setString(_customFontFamilyKey, family);

    if (previousPath != null && previousPath != file.path) {
      try {
        final previous = File(previousPath);
        if (await previous.exists()) await previous.delete();
      } catch (_) {}
    }
  }

  Future<void> clearCustomFont() async {
    final path = _customFontPath;
    _customFontPath = null;
    _customFontName = null;
    _customFontFamily = null;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_customFontPathKey);
    await prefs.remove(_customFontNameKey);
    await prefs.remove(_customFontFamilyKey);

    if (path != null) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  Future<void> _loadFont(Uint8List bytes, String family) async {
    final loader = FontLoader(family);
    loader.addFont(
      Future.value(
        ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes),
      ),
    );
    await loader.load();
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
