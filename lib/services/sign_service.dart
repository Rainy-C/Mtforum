import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'api_service.dart';

class AutoSignOutcome {
  final bool attempted;
  final bool success;
  final String message;

  const AutoSignOutcome({
    required this.attempted,
    required this.success,
    required this.message,
  });

  const AutoSignOutcome.skipped([this.message = ''])
      : attempted = false,
        success = true;
}

class SignService {
  SignService._();

  static final SignService instance = SignService._();

  static const String _autoSignKey = 'auto_sign_enabled';
  static const String _lastSignDateKey = 'auto_sign_last_success_date';
  static const String _lastSignAuthKey = 'auto_sign_last_success_auth';

  final ApiService _api = ApiService.instance;

  Future<bool> getAutoSignEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoSignKey) ?? false;
  }

  Future<void> setAutoSignEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoSignKey, enabled);
  }

  Future<bool> hasSignedToday() async {
    if (!_api.isLoggedIn) {
      return false;
    }

    final prefs = await SharedPreferences.getInstance();
    final lastDate = prefs.getString(_lastSignDateKey);
    final lastAuth = prefs.getString(_lastSignAuthKey);

    return lastDate == _todayKey() &&
        lastAuth != null &&
        lastAuth == _api.auth;
  }

  Future<bool> syncTodayStatus() async {
    if (await hasSignedToday()) {
      return true;
    }

    if (!_api.isLoggedIn) {
      return false;
    }

    final remoteSigned = await _api.isSignedToday();
    if (remoteSigned) {
      await _markSignedToday();
    }

    return remoteSigned;
  }

  Future<SignResult> signNow() async {
    final result = await _api.signIn();

    if (result.success) {
      await _markSignedToday();
    }

    return result;
  }

  /// App 启动时调用。
  ///
  /// 成功签到后当天不会再次请求。
  /// 如果第一次启动时网络失败，不记录成功日期，下次启动会自动重试。
  Future<AutoSignOutcome> runStartupAutoSign() async {
    if (!await getAutoSignEnabled()) {
      return const AutoSignOutcome.skipped('自动签到未开启');
    }

    if (!_api.isLoggedIn) {
      return const AutoSignOutcome.skipped('未登录');
    }

    if (await syncTodayStatus()) {
      return const AutoSignOutcome.skipped('今日已签到');
    }

    try {
      final result = await signNow();
      return AutoSignOutcome(
        attempted: true,
        success: result.success,
        message: result.message,
      );
    } catch (e) {
      return AutoSignOutcome(
        attempted: true,
        success: false,
        message: '自动签到失败：$e',
      );
    }
  }

  Future<void> _markSignedToday() async {
    final auth = _api.auth;
    if (auth == null || auth.isEmpty) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSignDateKey, _todayKey());
    await prefs.setString(_lastSignAuthKey, auth);
  }

  String _todayKey() {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '${now.year}-$month-$day';
  }
}
