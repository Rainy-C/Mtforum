import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// 仅用于匿名启动统计和反馈回执路由的随机安装标识。
///
/// 不读取论坛 UID、Android ID、IMEI、OAID、MAC 或论坛 Cookie。
class InstallIdentityService {
  InstallIdentityService._();
  static final InstallIdentityService instance = InstallIdentityService._();

  static const _storageKey = 'anonymous_install_id_v1';

  Future<String> getId() async {
    final prefs = await SharedPreferences.getInstance();
    var value = prefs.getString(_storageKey)?.trim() ?? '';
    if (!_isValid(value)) {
      value = _generate();
      await prefs.setString(_storageKey, value);
    }
    return value;
  }

  static bool _isValid(String value) {
    return RegExp(r'^[A-Za-z0-9_-]{16,128}$').hasMatch(value);
  }

  static String _generate() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
