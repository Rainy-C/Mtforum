import 'dart:io' show Cookie;

import 'package:cookie_jar/cookie_jar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/logger.dart';
import 'waf/cookie_bridge.dart';

/// 论坛 Cookie 管理器：负责 CookieJar 的读写、核心/防护 Cookie 分流，
/// 以及「防护 Cookie 独立持久化」。
///
/// 持久化策略（重点）：
/// - **账号登录态**（`cQWy_2132_auth` / `cQWy_2132_saltkey`）由
///   `ApiService` 走 SharedPreferences 保存，绝不写进防护 Cookie 存储；
/// - **防护 Cookie**（`acw_sc__v2` 等）另存一份，键里带 host，与账号无关。
///   这样切账号 / 退登 / 重启都不会把某个账号的登录态扩散出去，同时冷启动
///   不必重新过一遍人机验证。
class ForumCookieManager {
  ForumCookieManager({required this.baseUrl});

  /// 站点根地址，例如 `https://bbs.binmt.cc`
  final String baseUrl;

  /// Discuz 会话 Cookie 名（cookiepre = `cQWy_2132_`）。
  static const String authCookieName = 'cQWy_2132_auth';
  static const String saltkeyCookieName = 'cQWy_2132_saltkey';

  static const String _wafStoreKey = 'forum_waf_cookies_v1';

  /// 活跃 CookieJar。所有 Dio 实例共用同一个，保证 Cookie 一致。
  final CookieJar jar = CookieJar();

  SharedPreferences? _prefs;

  Uri get siteUri => Uri.parse(baseUrl);

  String get siteHost => siteUri.host;

  Future<void> init(SharedPreferences prefs) async {
    _prefs = prefs;
    await _restoreWafCookies();
  }

  // ------------------------------------------------------------------
  // 读取
  // ------------------------------------------------------------------

  Future<List<Cookie>> loadForRequest() => jar.loadForRequest(siteUri);

  /// 当前请求应当携带的完整 Cookie 头。
  Future<String> buildRequestCookieHeader() async {
    final cookies = await loadForRequest();
    return cookies
        .where((c) => c.name.isNotEmpty)
        .map((c) => '${c.name}=${c.value}')
        .join('; ');
  }

  /// **只含论坛核心登录态**的 Cookie 串 —— 注入验证 WebView 时使用。
  ///
  /// 防护 Cookie 一定不能带进去：罐里可能是服务端已判过期的旧值，
  /// 灌进验证页会让 JS 挑战继续基于旧值计算，永远拿不到新值。
  Future<String> buildCoreCookieString() async {
    final cookies = await loadForRequest();
    return CookieClassifier.coreCookiesOf(
      cookies
          .where((c) => c.name.isNotEmpty)
          .map((c) => '${c.name}=${c.value}')
          .join('; '),
    );
  }

  /// 罐里现存的防护 Cookie 名（用于启动验证前清理）。
  Future<List<String>> currentWafCookieNames() async {
    final cookies = await loadForRequest();
    return cookies
        .where((c) => CookieClassifier.isWafCookie(c.name))
        .map((c) => c.name)
        .toSet()
        .toList();
  }

  // ------------------------------------------------------------------
  // 写入
  // ------------------------------------------------------------------

  /// 恢复账号核心 Cookie（登录态来自 SharedPreferences）。
  Future<void> restoreCoreCookies({String? auth, String? saltkey}) async {
    final cookies = <Cookie>[];
    if (auth != null && auth.isNotEmpty) {
      cookies.add(Cookie(authCookieName, auth));
    }
    if (saltkey != null && saltkey.isNotEmpty) {
      cookies.add(Cookie(saltkeyCookieName, saltkey));
    }
    if (cookies.isEmpty) return;
    await jar.saveFromResponse(siteUri, cookies);
  }

  /// 清空 CookieJar（登出 / 登录前）。
  Future<void> clearAll() => jar.deleteAll();

  /// 清理罐里的防护 Cookie。
  ///
  /// 启动验证前调用：让 JS 挑战从一个干净的状态开始，而不是拿到客户端
  /// 手里那条可能已经过期的旧值。
  Future<void> clearWafCookies() async {
    final names = await currentWafCookieNames();
    if (names.isEmpty) return;
    final kept = <Cookie>[];
    for (final cookie in await loadForRequest()) {
      if (!CookieClassifier.isWafCookie(cookie.name)) kept.add(cookie);
    }
    await jar.deleteAll();
    if (kept.isNotEmpty) {
      await jar.saveFromResponse(siteUri, kept);
    }
    AppLogger.d('COOKIE', '清理防护 Cookie: ${names.join(', ')}');
  }

  /// 把 WebView 的 Cookie 回流到 CookieJar。
  ///
  /// 返回**罐里原本没有的** Cookie（即验证 / 防火墙新下发的客户端级 Cookie），
  /// 供调用方持久化。
  Future<Map<String, String>> syncFromWebView(
    Map<String, String> webCookies,
  ) async {
    if (webCookies.isEmpty) return const {};

    final existing = await loadForRequest();
    final existingNames = existing.map((c) => c.name).toSet();

    final additions = <Cookie>[];
    for (final entry in webCookies.entries) {
      if (entry.key.isEmpty) continue;
      try {
        additions.add(
          Cookie(entry.key, entry.value)
            ..domain = '.$siteHost'
            ..path = '/'
            ..secure = siteUri.scheme == 'https'
            // 一律按会话 Cookie 处理：各端 expires 单位不可信，
            // 带上只会制造"内存有、落盘没有"的失效。
            ..httpOnly = false,
        );
      } catch (e) {
        AppLogger.d('COOKIE', '跳过非法 Cookie "${entry.key}": $e');
      }
    }
    if (additions.isEmpty) return const {};

    await jar.saveFromResponse(siteUri, additions);

    final extras = <String, String>{};
    for (final cookie in additions) {
      if (!existingNames.contains(cookie.name) ||
          CookieClassifier.isWafCookie(cookie.name)) {
        extras[cookie.name] = cookie.value;
      }
    }
    AppLogger.i(
      'COOKIE',
      'WebView → CookieJar 回流 ${additions.length} 条'
          '${extras.isEmpty ? '' : '（新增 ${extras.length}）'}',
    );
    return extras;
  }

  // ------------------------------------------------------------------
  // 防护 Cookie 持久化
  // ------------------------------------------------------------------

  /// 只持久化防护 Cookie，避免账号态扩散。
  Future<void> persistWafCookies(Map<String, String> cookies) async {
    final prefs = _prefs;
    if (prefs == null) return;
    final waf = <String, String>{};
    for (final entry in cookies.entries) {
      if (CookieClassifier.isWafCookie(entry.key)) {
        waf[entry.key] = entry.value;
      }
    }
    if (waf.isEmpty) return;
    final encoded = waf.entries
        .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
    await prefs.setString(_wafStoreKey, '$siteHost|$encoded');
    AppLogger.d('COOKIE', '持久化防护 Cookie: ${waf.keys.join(', ')}');
  }

  /// 冷启动时把上次的防护 Cookie 灌回罐里，避免重新验证。
  Future<void> _restoreWafCookies() async {
    final prefs = _prefs;
    if (prefs == null) return;
    final raw = prefs.getString(_wafStoreKey);
    if (raw == null || raw.isEmpty) return;

    final separator = raw.indexOf('|');
    if (separator <= 0) return;
    final host = raw.substring(0, separator);
    if (host != siteHost) {
      // 换站点就丢弃，绝不跨站复用。
      await prefs.remove(_wafStoreKey);
      return;
    }

    final cookies = <Cookie>[];
    for (final pair in raw.substring(separator + 1).split('&')) {
      if (pair.isEmpty) continue;
      final eq = pair.indexOf('=');
      if (eq <= 0) continue;
      final name = Uri.decodeComponent(pair.substring(0, eq));
      final value = Uri.decodeComponent(pair.substring(eq + 1));
      if (name.isEmpty) continue;
      cookies.add(
        Cookie(name, value)
          ..domain = '.$siteHost'
          ..path = '/'
          ..secure = siteUri.scheme == 'https',
      );
    }
    if (cookies.isEmpty) return;
    await jar.saveFromResponse(siteUri, cookies);
    AppLogger.d('COOKIE', '恢复防护 Cookie ${cookies.length} 条');
  }

  /// 清掉持久化的防护 Cookie（登录态损坏、验证连续失败时调用）。
  Future<void> clearPersistedWafCookies() async {
    await _prefs?.remove(_wafStoreKey);
  }
}
