import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

import 'waf/waf_interceptor.dart';

/// 论坛 HTTP 客户端工厂。
///
/// 统一在这里创建 Dio，保证：
/// - **UA 唯一**：Dio 与不可见 WebView 使用完全相同的 UA。UA 不一致会导致
///   服务端把 WAF Cookie 绑定到另一套指纹上，出现"浏览器过了、接口还是不行"；
/// - 所有业务 Dio 共用一个 CookieJar；
/// - 探测 Dio 与业务 Dio 共用 CookieJar，但**不挂验证拦截器**（避免递归）。
abstract final class ForumHttpClient {
  /// 移动端 UA —— 与原生不可见 WebView 完全一致。
  static const String mobileUserAgent =
      'Mozilla/5.0 (Linux; Android 16) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/150.0.0.0 Mobile Safari/537.36';

  /// 桌面 UA —— 部分页面（收藏详情）只在桌面模板输出数据。
  static const String desktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/150.0.0.0 Safari/537.36';

  static const String acceptLanguage = 'zh-CN,zh;q=0.9';

  static BaseOptions _baseOptions({
    required String baseUrl,
    required String userAgent,
  }) {
    return BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 25),
      sendTimeout: const Duration(seconds: 20),
      headers: {
        'User-Agent': userAgent,
        'Accept-Language': acceptLanguage,
        'Accept-Encoding': 'gzip',
      },
    );
  }

  /// 业务客户端（移动模板）：Cookie 同步 + 无感验证。
  static Dio buildSession({
    required String baseUrl,
    required CookieJar jar,
    required WafInterceptor wafInterceptor,
  }) {
    final dio = Dio(_baseOptions(baseUrl: baseUrl, userAgent: mobileUserAgent));
    dio.interceptors.add(CookieManager(jar));
    dio.interceptors.add(wafInterceptor);
    return dio;
  }

  /// 业务客户端（桌面模板）：**刻意不挂 CookieManager**。
  ///
  /// 桌面模板请求需要精确控制 Cookie（PC UA + 不带 `mobile` 参数，
  /// 否则服务端继续返回不含阅读量的移动页），Cookie 由调用方通过
  /// 显式 `Cookie` 请求头给出。挂上 CookieManager 会把移动模板的
  /// Cookie 一并注入，破坏这个前提。
  static Dio buildDesktopSession({
    required WafInterceptor wafInterceptor,
  }) {
    final dio = Dio(
      _baseOptions(baseUrl: '', userAgent: desktopUserAgent),
    );
    dio.interceptors.add(wafInterceptor);
    return dio;
  }

  /// 探测客户端：与业务共用 CookieJar，但不挂验证拦截器。
  static Dio buildProbe({
    required CookieJar jar,
    required String userAgent,
  }) {
    final dio = Dio(_baseOptions(baseUrl: '', userAgent: userAgent));
    dio.interceptors.add(CookieManager(jar));
    return dio;
  }
}
