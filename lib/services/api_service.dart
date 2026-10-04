import 'dart:async';
import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/network/cookie_manager.dart';
import '../core/network/forum_http_client.dart';
import '../core/network/waf/verification_gate.dart';
import '../core/network/waf/waf_interceptor.dart';
import '../data/forum_parser.dart';
import '../data/account_parser.dart';
import '../data/sign_parser.dart';
import '../data/portal_parser.dart';
import '../data/user_center_parser.dart';
import '../models/models.dart';

part '../features/auth/data/api_service_auth.dart';
part '../features/auth/data/api_service_session.dart';
part '../features/forum/data/api_service_forum.dart';
part '../features/thread/data/api_service_thread.dart';
part '../features/profile/data/api_service_profile.dart';
part '../features/messages/data/api_service_messages.dart';
part '../features/social/data/api_service_social.dart';
part '../features/mall/data/api_service_mall.dart';

/// MT 论坛网络门面。
///
/// 网络请求与 HTML 解析已经分离：
/// - ApiService：请求、Cookie、登录态、写操作。
/// - ForumParser：只负责把服务器响应解析成模型。
class ApiService {
  static const String baseUrl = 'https://bbs.binmt.cc';

  ApiService._();
  static final ApiService instance = ApiService._();

  final ForumParser _parser = const ForumParser();
  final AccountParser _accountParser = const AccountParser();
  final SignParser _signParser = const SignParser();
  final PortalParser _portalParser = const PortalParser();
  final UserCenterParser _userCenterParser = const UserCenterParser();
  final List<void Function()> _loginListeners = [];

  late final Dio _dio;
  late final Dio _desktopDio;
  late final CookieJar _cookieJar;
  late final ForumCookieManager _cookieManager;
  late final SharedPreferences _prefs;

  bool _initialized = false;
  String? _auth;
  String? _saltkey;
  String? _formhash;
  String? _formhashAuth;
  String? _currentUid;
  Future<String>? _formhashRefreshFuture;
  int _sessionGeneration = 0;
  final Map<String, ThreadDetail> _findPostPageCache = {};
  final Map<String, DateTime> _findPostPageCacheTimes = {};
  final Map<String, Future<ThreadDetail>> _findPostPageRequests = {};
  final Map<String, Future<_FavoriteDetailData?>> _favoriteDetailRequests = {};
  static const Duration _findPostPageCacheTtl = Duration(minutes: 2);

  /// 无感人机验证开关（默认开启）。
  static const String wafAutoVerifyPrefKey = 'waf_auto_verify';

  bool get isLoggedIn =>
      (_auth?.isNotEmpty ?? false) && (_saltkey?.isNotEmpty ?? false);
  String? get auth => _auth;
  String? get saltkey => _saltkey;
  String? get formhash => _formhash;
  String? get currentUid => _currentUid;

  /// 活跃 CookieJar（探测请求与人机验证回流共用）。
  CookieJar get activeCookieJar => _cookieJar;

  /// Cookie 管理器：核心 / 防护 Cookie 分流的唯一入口。
  ForumCookieManager get cookieManager => _cookieManager;

  void addLoginListener(void Function() listener) {
    if (!_loginListeners.contains(listener)) _loginListeners.add(listener);
  }

  void removeLoginListener(void Function() listener) {
    _loginListeners.remove(listener);
  }

  void _notifyLoginChanged() {
    for (final listener in List<void Function()>.from(_loginListeners)) {
      try {
        listener();
      } catch (_) {}
    }
  }

  Future<void> init() async {
    if (_initialized) {
      return;
    }

    // SharedPreferences 必须早于 Cookie 管理器初始化：防护 Cookie 的
    // 独立持久化依赖它。
    _prefs = await SharedPreferences.getInstance();

    _cookieManager = ForumCookieManager(baseUrl: baseUrl);
    await _cookieManager.init(_prefs);
    _cookieJar = _cookieManager.jar;

    // 无感人机验证：Dio 与不可见 WebView 共用同一份 UA 与同一个 CookieJar。
    final gate = VerificationGate.instance;
    final wafInterceptor = WafInterceptor(gate: gate);
    final desktopWafInterceptor = WafInterceptor(gate: gate);

    _dio = ForumHttpClient.buildSession(
      baseUrl: baseUrl,
      jar: _cookieJar,
      wafInterceptor: wafInterceptor,
    );
    // 拦截器需要在验证通过后用原参数重放请求，因此构建完成后回填 Dio。
    wafInterceptor.attach(_dio);

    _desktopDio = ForumHttpClient.buildDesktopSession(
      wafInterceptor: desktopWafInterceptor,
    );
    desktopWafInterceptor.attach(_desktopDio);

    // 探测 Dio：共用 CookieJar，但不挂验证拦截器，避免递归。
    gate.cookieManager = _cookieManager;
    gate.probeDio = ForumHttpClient.buildProbe(
      jar: _cookieJar,
      userAgent: ForumHttpClient.mobileUserAgent,
    );
    // 开关（默认开启）。关闭后完全不介入，请求照旧返回原始页面。
    gate.isEnabled = () => _prefs.getBool(wafAutoVerifyPrefKey) ?? true;

    // 所有 HTML/AJAX 响应只要带 formhash，就自动收入缓存。
    // 这样浏览帖子、签到页、社区等页面后，写操作无需再次专门请求。
    _dio.interceptors.add(
      InterceptorsWrapper(
        onResponse: (response, handler) {
          final data = response.data;
          if (data is String && data.isNotEmpty) {
            final hash = _extractFormhash(data);
            if (hash != null && hash.isNotEmpty) {
              _rememberFormhash(hash);
            }
            if (isLoggedIn) {
              final uid = RegExp(
                r'''discuz_uid\s*=\s*['"]?(\d+)''',
                caseSensitive: false,
              ).firstMatch(data)?.group(1);
              if (uid != null && uid != '0') _currentUid = uid;
            }
          }
          handler.next(response);
        },
      ),
    );

    _auth = _prefs.getString('forum_auth');
    _saltkey = _prefs.getString('forum_saltkey');

    _auth ??= _prefs.getString('auth');
    _saltkey ??= _prefs.getString('saltkey');

    if (isLoggedIn) {
      await _restoreSessionCookies();

      // formhash 与当前 auth 绑定。匹配当前账号时直接恢复，
      // App 启动不再为了 formhash 阻塞 1~3 次网络请求。
      final cachedHash = _prefs.getString('forum_formhash');
      final cachedAuth = _prefs.getString('forum_formhash_auth');
      if (cachedHash != null &&
          cachedHash.isNotEmpty &&
          cachedAuth == _auth) {
        _formhash = cachedHash;
        _formhashAuth = _auth;
      }
    }

    _initialized = true;
  }

  static Uri? resolveFindPostLocation(Uri requestUri, String? location) {
    final value = location?.trim() ?? '';
    if (value.isEmpty) return null;
    return requestUri.resolve(value.replaceAll('&amp;', '&'));
  }

  static String buildPostPreview(Post post) {
    final plain = post.content.trim();
    if (plain.isNotEmpty) return plain;
    final parts = <String>[];
    for (final content in post.richContent) {
      final text = content.text.trim();
      if (text.isNotEmpty) {
        parts.add(text);
        continue;
      }
      final label = switch (content.type) {
        PostContentType.emoji => '[表情]',
        PostContentType.image => '[图片]',
        PostContentType.attachment => '[附件]',
        PostContentType.audio => '[音频]',
        PostContentType.video || PostContentType.flash => '[视频]',
        PostContentType.code => '[代码]',
        _ => '',
      };
      if (label.isNotEmpty && (parts.isEmpty || parts.last != label)) {
        parts.add(label);
      }
    }
    if (parts.isEmpty && post.images.isNotEmpty) return '[图片]';
    return parts.join(' ').trim();
  }

}
