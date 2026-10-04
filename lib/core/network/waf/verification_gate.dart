import 'dart:async';

import 'package:dio/dio.dart';

import '../../utils/logger.dart';
import '../cookie_manager.dart';
import 'headless_verifier.dart';
import 'interstitial_detector.dart';
import 'waf_flags.dart';

/// 无感人机验证守门器。
///
/// **用户完全的不可见**：拦截页出现时，后台启动一个不可见的原生 WebView，
/// 用**原始 URL + 与 Dio 完全一致的 UA** 跑一遍 JS 挑战；验证 Cookie 回流到
/// CookieJar 后，用同样的 URL / UA 重新请求一次，确认拿到真正的论坛页，才
/// 判定通过并销毁 WebView。整个过程不弹页面、不弹 Dialog、不要求点击。
///
/// 唯一权威判据是「重新请求原 URL 能拿到论坛页」，**不是**"发现了某个
/// 验证 Cookie"。这一点让本实现对任何厂商的 JS 挑战都成立。
class VerificationGate {
  VerificationGate._();

  static final VerificationGate instance = VerificationGate._();

  // ------------------------------------------------------------------
  // 依赖注入（由 ApiService.init 绑定）
  // ------------------------------------------------------------------

  /// 功能开关：关闭后完全不介入。
  bool Function() isEnabled = () => true;

  /// 当前账号的 Cookie 管理器（提供 CookieJar 与核心 Cookie 串）。
  ForumCookieManager? cookieManager;

  /// 探测用的 Dio：与业务 Dio 共用 CookieJar，但**不挂载拦截器**，
  /// 避免"探测 → 又判定为拦截页 → 再探测"的递归。
  Dio? probeDio;

  // ------------------------------------------------------------------
  // 运行状态
  // ------------------------------------------------------------------

  /// 结论缓存有效期：验证通过后的一小段时间内不再重复验证。
  static const Duration _successTtl = Duration(minutes: 3);

  /// 失败冷却：避免验证器不可用时每次都拉起 WebView。
  static const Duration _failureCooldown = Duration(seconds: 30);

  /// 单次验证总预算（纯 JS 挑战实测 < 5s）。
  static const Duration _verificationBudget = Duration(seconds: 25);

  /// WebView Cookie 轮询间隔。
  static const Duration _pollInterval = Duration(milliseconds: 900);

  /// 两次探测之间的最小间隔（探测是一次完整请求，必须节流）。
  static const Duration _minProbeGap = Duration(milliseconds: 1400);

  Completer<bool>? _inFlight;
  DateTime _lastFailureAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastSuccessAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// 是否处于「刚验证过」的窗口内。
  bool get recentlyVerified =>
      DateTime.now().difference(_lastSuccessAt) < _successTtl;

  bool get _inCooldown =>
      DateTime.now().difference(_lastFailureAt) < _failureCooldown;

  /// 全局验证次数（用于诊断；不参与业务逻辑）。
  int verificationCount = 0;

  /// 从拦截页恢复。返回 true 表示"已验证通过，可以重放原请求"。
  ///
  /// - [options]：触发拦截的请求（提供原 URL 与原始 UA）。
  Future<bool> verifyAndRecover(RequestOptions options) async {
    if (!isEnabled()) return false;
    if (recentlyVerified) return true;

    // 单飞：并发失败请求共用同一次验证结果。
    final existing = _inFlight;
    if (existing != null) return existing.future;

    if (_inCooldown) {
      AppLogger.d('WAF', '验证处于冷却期，跳过');
      return false;
    }

    final completer = Completer<bool>();
    _inFlight = completer;
    var ok = false;
    try {
      ok = await _runVerification(options);
    } catch (e, st) {
      AppLogger.w('WAF', '人机验证流程异常: $e');
      AppLogger.d('WAF', '$st');
      ok = false;
    } finally {
      if (ok) {
        _lastSuccessAt = DateTime.now();
      } else {
        _lastFailureAt = DateTime.now();
      }
      _inFlight = null;
      if (!completer.isCompleted) completer.complete(ok);
    }
    return ok;
  }

  Future<bool> _runVerification(RequestOptions options) async {
    final manager = cookieManager;
    final probe = probeDio;
    if (manager == null || probe == null) {
      AppLogger.w('WAF', '验证依赖未初始化，跳过');
      return false;
    }
    if (!await HeadlessVerifier.isAvailable) {
      AppLogger.w('WAF', '当前平台不支持后台验证，跳过');
      return false;
    }

    final url = options.uri.toString();
    final userAgent = _resolveUserAgent(options);
    verificationCount++;

    // 1) 清理旧防护 Cookie：罐里与 WebView 里都清，让挑战从干净状态开始。
    final staleNames = await manager.currentWafCookieNames();
    await manager.clearWafCookies();

    // 2) 只注入论坛核心登录 Cookie（游客为空）。
    final coreCookieString = await manager.buildCoreCookieString();
    final injected = <String, String>{
      for (final e in _parseCookieHeader(coreCookieString)) e.key: e.value,
    };

    AppLogger.i(
      'WAF',
      '开始无感验证 #$verificationCount url=$url '
          '核心Cookie=${injected.length} 清理防护Cookie=${staleNames.length}',
    );

    final session = await HeadlessVerifier.start(
      url: url,
      userAgent: userAgent,
      cookies: injected,
      staleCookieNames: staleNames,
    );
    if (session == null) {
      AppLogger.w('WAF', '无法启动不可见 WebView');
      return false;
    }

    final deadline = DateTime.now().add(_verificationBudget);
    var lastProbeAt = DateTime.fromMillisecondsSinceEpoch(0);
    var syncedWafCookies = <String, String>{};

    try {
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(_pollInterval);

        // 3) WebView Cookie → CookieJar 回流（每一轮都回流，保证挑战新写入的
        //    acw_sc__v2 / acw_tc 立即可用于探测请求）。
        final snapshot = await HeadlessVerifier.read(session.id);
        if (snapshot.cookies.isNotEmpty) {
          final extras = await manager.syncFromWebView(snapshot.cookies);
          if (extras.isNotEmpty) {
            syncedWafCookies = {...syncedWafCookies, ...extras};
          }
        }

        // 4) 节流后探测。
        if (DateTime.now().difference(lastProbeAt) < _minProbeGap) continue;
        lastProbeAt = DateTime.now();

        final passed = await _probe(probe, url, userAgent);
        if (passed) {
          // 5) 持久化防护 Cookie（与账号无关），冷启动不必重新验证。
          if (syncedWafCookies.isNotEmpty) {
            await manager.persistWafCookies(syncedWafCookies);
          }
          AppLogger.i('WAF', '验证通过，已拿到论坛页');
          return true;
        }
      }

      AppLogger.w('WAF', '验证超时，未拿到论坛页');
      return false;
    } finally {
      // 6) 无论成败都销毁 WebView。
      await HeadlessVerifier.dispose(session.id);
      AppLogger.d('WAF', '不可见 WebView 已销毁');
    }
  }

  /// 探测：原 URL + 原 UA 重新请求一次，能否拿到论坛页。
  Future<bool> _probe(Dio probe, String url, String userAgent) async {
    try {
      final response = await probe.get<String>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          followRedirects: true,
          headers: {'User-Agent': userAgent},
          validateStatus: (status) => status != null && status < 500,
          // 业务请求的默认 UA 与这里一致；显式再写一次，防止被 BaseOptions 覆盖。
          extra: const {WafFlags.probe: true},
        ),
      );

      if (response.statusCode != 200) return false;
      final body = response.data ?? '';
      if (body.isEmpty) return false;

      final contentType = response.headers.value('content-type');
      if (contentType != null &&
          contentType.isNotEmpty &&
          !InterstitialDetector.isHtmlDocument(contentType)) {
        // 探测目标不是 HTML（例如跳到了文件下载）——仍算通过本次探测，
        // 因为"不是拦截页"这一条已经满足。
        return true;
      }
      return InterstitialDetector.isUsableForumPage(body, contentType);
    } catch (e) {
      AppLogger.d('WAF', '探测请求失败: $e');
      return false;
    }
  }

  String _resolveUserAgent(RequestOptions options) {
    final raw = options.headers['User-Agent'];
    if (raw is String && raw.trim().isNotEmpty) return raw.trim();
    return 'Mozilla/5.0 (Linux; Android 16) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/150.0.0.0 Mobile Safari/537.36';
  }

  static Map<String, String> _parseCookieHeader(String raw) {
    final out = <String, String>{};
    for (final pair in raw.split(';')) {
      final trimmed = pair.trim();
      if (trimmed.isEmpty) continue;
      final eq = trimmed.indexOf('=');
      if (eq <= 0) continue;
      out[trimmed.substring(0, eq).trim()] = trimmed.substring(eq + 1).trim();
    }
    return out;
  }
}
