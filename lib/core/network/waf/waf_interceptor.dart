import 'package:dio/dio.dart';

import '../../utils/logger.dart';
import 'interstitial_detector.dart';
import 'waf_flags.dart';
import 'verification_gate.dart';

/// 写操作在人机验证后被拦下时抛出的异常。
///
/// 业务层看到它就提示用户"重新提交"，**绝不自动重放**——
/// 自动重放 POST/PUT/PATCH/DELETE 会造成重复发帖、重复回复、重复点赞。
class WafResubmitRequired implements Exception {
  const WafResubmitRequired(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 无感人机验证拦截器。
///
/// 工作方式：
/// 1. 业务请求返回 **HTTP 200 但不是论坛页**（WAF / 人机验证页）时命中；
/// 2. 交给 [VerificationGate] 在后台用不可见 WebView 完成挑战；
/// 3. 验证通过后：
///    - **GET / HEAD**：用原 URL、原参数自动重放，用户只感觉"多等了片刻"；
///    - **写操作**：直接抛出 [WafResubmitRequired]，由业务层重新发起，
///      绝不自动重放。
class WafInterceptor extends Interceptor {
  WafInterceptor({required this.gate});

  final VerificationGate gate;

  /// 用于重放请求的 Dio。构建期存在循环依赖（Dio 需要拦截器、拦截器需要
  /// Dio），因此由调用方在 Dio 构建完成后通过 [attach] 回填。
  Dio? _dio;

  /// 绑定业务 Dio。
  void attach(Dio dio) => _dio = dio;


  /// 只有幂等方法才允许自动重放。
  static bool isReplayableMethod(String method) {
    final m = method.toUpperCase();
    return m == 'GET' || m == 'HEAD';
  }

  /// 是否可以对该请求做人机验证判定。
  bool _isInspectable(RequestOptions options) {
    if (options.extra[WafFlags.handled] == true) return false;
    if (options.extra[WafFlags.probe] == true) return false;
    return true;
  }

  /// 该响应体是否是「不是一个能用的论坛页」。
  bool _isInterstitial(Response<dynamic> response) {
    final data = response.data;
    if (data is! String || data.isEmpty) return false;
    return InterstitialDetector.looksLikeInterstitialPage(
      data,
      response.headers.value('content-type'),
    );
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) async {
    final options = response.requestOptions;
    if (!_isInspectable(options) || !_isInterstitial(response)) {
      handler.next(response);
      return;
    }

    AppLogger.w('WAF', '命中拦截页：${options.method} ${options.uri}');
    final recovered = await gate.verifyAndRecover(options);

    if (!recovered) {
      // 验证不可用 / 失败：把原始拦截页交回业务层，由业务层按"加载失败"处理。
      handler.next(response);
      return;
    }

    if (!isReplayableMethod(options.method)) {
      // 写操作绝不自动重放。
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.badResponse,
          response: response,
          error: const WafResubmitRequired('人机验证已完成，请重新提交'),
          message: '人机验证已完成，请重新提交',
        ),
        true,
      );
      return;
    }

    try {
      final replayed = await _replay(options);
      handler.resolve(replayed);
    } catch (e) {
      AppLogger.w('WAF', '重放失败: $e');
      handler.next(response);
    }
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final response = err.response;
    final options = err.requestOptions;
    // WAF 也可能用 403 / 503 返回挑战页。
    final status = response?.statusCode ?? 0;
    final looksLikeChallenge = status == 403 || status == 503 || status == 200;
    if (response == null ||
        !looksLikeChallenge ||
        !_isInspectable(options) ||
        !_isInterstitial(response)) {
      handler.next(err);
      return;
    }
    if (status != 200 && !isReplayableMethod(options.method)) {
      handler.next(err);
      return;
    }

    AppLogger.w('WAF', '命中拦截响应：$status ${options.uri}');
    final recovered = await gate.verifyAndRecover(options);
    if (!recovered) {
      handler.next(err);
      return;
    }

    if (!isReplayableMethod(options.method)) {
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.badResponse,
          response: response,
          error: const WafResubmitRequired('人机验证已完成，请重新提交'),
          message: '人机验证已完成，请重新提交',
        ),
        true,
      );
      return;
    }

    try {
      final replayed = await _replay(options);
      handler.resolve(replayed);
    } catch (e) {
      AppLogger.w('WAF', '重放失败: $e');
      handler.next(err);
    }
  }

  /// 用原 URL、原方法、原参数、原 UA 重放一次。
  ///
  /// 只用于幂等方法（见 [isReplayableMethod]）。
  Future<Response<dynamic>> _replay(RequestOptions options) {
    final dio = _dio;
    if (dio == null) {
      throw StateError('WafInterceptor 未绑定 Dio');
    }
    final clone = options.copyWith(
      extra: {...options.extra, WafFlags.handled: true},
    );
    // fetch 会重新走一遍拦截器链（CookieManager 会补上最新 Cookie），
    // 而 WafFlags.handled 让本拦截器直接放行。
    return dio.fetch<dynamic>(clone);
  }
}
