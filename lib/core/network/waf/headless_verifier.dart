import 'dart:async';

import 'package:flutter/services.dart';

import '../../utils/logger.dart';

/// 一次后台验证会话（对应原生侧一个不可见 WebView 实例）。
class HeadlessVerificationSession {
  const HeadlessVerificationSession({
    required this.id,
    required this.url,
  });

  /// 原生侧会话 id，用于取 Cookie / 销毁。
  final String id;

  /// 被验证的原始 URL。
  final String url;
}

/// 不可见 WebView 桥（Android 原生 `WebView`，通过 MethodChannel 驱动）。
///
/// 为什么用原生而不是引入 webview 插件：
/// - 项目已有 MethodChannel 基础设施，不新增依赖；
/// - 原生 `WebView` 的 Cookie 容器是 App 私有的，可与 Dio 的 CookieJar
///   做精确的双向同步，而不必担心插件在不同平台上的 `getAllCookies`
///   行为差异（Windows 上直接 `UnimplementedError`）。
///
/// **注意**：这里只提供"跑 JS、读写 Cookie"的能力，**不做通过判定**。
/// 是否通过由 [VerificationGate] 用"原 URL + 原 UA 重新请求能否拿到论坛页"
/// 判定——这是唯一权威判据。
abstract final class HeadlessVerifier {
  static const MethodChannel _channel =
      MethodChannel('com.binmt.mtforum/headless_verification');

  static bool? _available;

  /// 原生能力是否可用（非 Android 平台或旧版本返回 false）。
  static Future<bool> get isAvailable async {
    final cached = _available;
    if (cached != null) return cached;
    try {
      final ok = await _channel.invokeMethod<bool>('isAvailable') ?? false;
      _available = ok;
      return ok;
    } on MissingPluginException {
      _available = false;
      return false;
    } on PlatformException catch (e) {
      AppLogger.w('WAF', '不可见 WebView 能力探测失败: ${e.message}');
      _available = false;
      return false;
    }
  }

  /// 启动一次后台验证。
  ///
  /// - [url]：触发拦截的**原始 URL**；
  /// - [userAgent]：必须与 Dio 完全一致的 UA，否则验证拿到的 Cookie
  ///   与后续 API 请求不匹配，会出现"浏览器过了、接口还是不行"；
  /// - [cookies]：**只注入论坛核心登录 Cookie**，不注入任何防护 Cookie；
  /// - [staleCookieNames]：启动前需要清掉的旧防护 Cookie 名。
  static Future<HeadlessVerificationSession?> start({
    required String url,
    required String userAgent,
    required Map<String, String> cookies,
    required List<String> staleCookieNames,
  }) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'start',
        <String, dynamic>{
          'url': url,
          'userAgent': userAgent,
          'cookies': cookies,
          'staleCookieNames': staleCookieNames,
        },
      );
      final id = result?['id'] as String?;
      if (id == null || id.isEmpty) return null;
      return HeadlessVerificationSession(id: id, url: url);
    } on MissingPluginException {
      AppLogger.w('WAF', '原生不可见 WebView 不可用');
      return null;
    } on PlatformException catch (e) {
      AppLogger.w('WAF', '启动不可见 WebView 失败: ${e.message}');
      return null;
    }
  }

  /// 读取当前会话的 Cookie（`name=value` 映射）以及加载完成次数。
  static Future<({Map<String, String> cookies, int loadCount})> read(
    String sessionId,
  ) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'cookies',
        <String, dynamic>{'id': sessionId},
      );
      if (result == null) return (cookies: <String, String>{}, loadCount: 0);

      final raw = result['cookie'] as String? ?? '';
      final loadCount = (result['loadCount'] as num?)?.toInt() ?? 0;
      return (cookies: _parseCookieHeader(raw), loadCount: loadCount);
    } on MissingPluginException {
      return (cookies: <String, String>{}, loadCount: 0);
    } on PlatformException catch (e) {
      AppLogger.d('WAF', '读取不可见 WebView Cookie 失败: ${e.message}');
      return (cookies: <String, String>{}, loadCount: 0);
    }
  }

  /// 销毁会话（停止加载并释放 WebView）。
  static Future<void> dispose(String sessionId) async {
    try {
      await _channel.invokeMethod<void>('dispose', <String, dynamic>{
        'id': sessionId,
      });
    } on MissingPluginException {
      // 忽略：能力不可用时也没有会话需要销毁。
    } on PlatformException catch (e) {
      AppLogger.d('WAF', '销毁不可见 WebView 失败: ${e.message}');
    }
  }

  /// 解析 `a=b; c=d` 形式的 Cookie 头。
  static Map<String, String> _parseCookieHeader(String raw) {
    final out = <String, String>{};
    for (final pair in raw.split(';')) {
      final trimmed = pair.trim();
      if (trimmed.isEmpty) continue;
      final eq = trimmed.indexOf('=');
      if (eq <= 0) continue;
      final name = trimmed.substring(0, eq).trim();
      final value = trimmed.substring(eq + 1).trim();
      if (name.isEmpty) continue;
      out[name] = value;
    }
    return out;
  }
}
