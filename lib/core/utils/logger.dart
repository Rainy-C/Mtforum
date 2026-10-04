import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// 统一日志出口。
///
/// 之前各模块直接 `debugPrint` / `print`，无法按标签过滤，也无法在发布版
/// 彻底关闭。这里统一到 [developer.log]，release 构建下仅保留警告与错误。
abstract final class AppLogger {
  /// Release 构建下是否仍然输出 info/debug。默认关闭，避免刷屏。
  static bool verbose = false;

  static bool get _enabled => kDebugMode || verbose;

  static void d(String tag, String message) {
    if (!_enabled) return;
    developer.log(message, name: tag, level: 500);
  }

  static void i(String tag, String message) {
    if (!_enabled) return;
    developer.log(message, name: tag, level: 800);
  }

  /// 警告：调试版与发布版都输出（用于人机验证、Cookie 等关键路径）
  static void w(String tag, String message) {
    developer.log(message, name: tag, level: 900);
  }

  /// 错误
  static void e(String tag, String message, [Object? error, StackTrace? st]) {
    developer.log(
      message,
      name: tag,
      level: 1000,
      error: error,
      stackTrace: st,
    );
  }
}
