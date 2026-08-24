import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import 'update_service.dart';

class FeedbackSubmitResult {
  final bool success;
  final String message;
  final String? id;

  const FeedbackSubmitResult({
    required this.success,
    required this.message,
    this.id,
  });
}

class FeedbackService {
  FeedbackService._();
  static final FeedbackService instance = FeedbackService._();

  /// 可在发布时通过 --dart-define 覆盖为 HTTPS 地址。
  /// 旧版地址仅作兼容默认值，服务端新接口路径统一为 /api/v1/feedback。
  static const endpoint = String.fromEnvironment(
    'MTFORUM_FEEDBACK_URL',
    defaultValue: 'http://107.151.233.210:8888/api/v1/feedback',
  );


  /// 旧反馈服务异常时的内置候选地址。通过 dart-define 指定的 endpoint 仍然优先。
  static const fallbackEndpoint =
      'http://107.151.233.210:8888/api/v1/feedback';

  /// 候选服务健康检查地址，仅用于诊断；正常提交不会额外预请求一次。
  static const fallbackHealthEndpoint =
      'http://107.151.233.210:8888/healthz';

  static List<String> get endpointCandidates {
    final seen = <String>{};
    final out = <String>[];
    for (final value in <String>[endpoint, fallbackEndpoint]) {
      final normalized = value.trim();
      final uri = Uri.tryParse(normalized);
      final isPlaceholder = uri?.host.endsWith('example.com') == true;
      if (normalized.isNotEmpty && !isPlaceholder && seen.add(normalized)) {
        out.add(normalized);
      }
    }
    return out;
  }

  /// 可选的轻量客户端令牌。服务端未配置 FEEDBACK_APP_TOKEN 时无需设置。
  static const appToken = String.fromEnvironment(
    'MTFORUM_FEEDBACK_TOKEN',
    defaultValue: '',
  );

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      responseType: ResponseType.plain,
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json; charset=utf-8',
      },
      validateStatus: (status) => status != null && status >= 200 && status < 600,
    ),
  );

  Future<FeedbackSubmitResult> submit({
    required String content,
    String contact = '',
  }) async {
    final normalizedContent = content.trim();
    final normalizedContact = contact.trim();

    if (normalizedContent.length < 2) {
      return const FeedbackSubmitResult(
        success: false,
        message: '反馈内容至少需要 2 个字符',
      );
    }
    if (normalizedContent.length > 2000) {
      return const FeedbackSubmitResult(
        success: false,
        message: '反馈内容不能超过 2000 个字符',
      );
    }
    if (normalizedContact.length > 120) {
      return const FeedbackSubmitResult(
        success: false,
        message: '联系方式不能超过 120 个字符',
      );
    }

    var versionName = '';
    var versionCode = '';
    try {
      final info = await UpdateService.instance.getCurrentVersionInfo();
      versionName = '${info['versionName'] ?? ''}'.trim();
      versionCode = '${info['versionCode'] ?? ''}'.trim();
    } catch (_) {
      // 版本信息不是提交反馈的硬依赖。
    }

    final headers = <String, dynamic>{};
    if (appToken.isNotEmpty) {
      headers['X-MTForum-Token'] = appToken;
    }

    FeedbackSubmitResult? lastFailure;
    for (final target in endpointCandidates) {
      try {
        final response = await _dio.post<String>(
          target,
          data: jsonEncode({
            'content': normalizedContent,
            'contact': normalizedContact,
            'appVersion': versionName,
            'versionCode': versionCode,
            'platform': Platform.operatingSystem,
          }),
          options: Options(headers: headers),
        );

        Map<String, dynamic> body = const {};
        final raw = response.data?.trim() ?? '';
        if (raw.isNotEmpty) {
          try {
            final decoded = jsonDecode(raw);
            if (decoded is Map) {
              body = decoded.map((key, value) => MapEntry('$key', value));
            }
          } catch (_) {
            // 非 JSON 响应继续按 HTTP 状态处理。
          }
        }

        final status = response.statusCode ?? 0;
        final serverMessage = '${body['message'] ?? ''}'.trim();
        final feedbackId = '${body['id'] ?? ''}'.trim();

        if (status >= 200 && status < 300 && body['ok'] != false) {
          return FeedbackSubmitResult(
            success: true,
            message: serverMessage.isEmpty ? '反馈已提交，感谢您的支持' : serverMessage,
            id: feedbackId.isEmpty ? null : feedbackId,
          );
        }

        if (status == 429) {
          return const FeedbackSubmitResult(
            success: false,
            message: '提交过于频繁，请稍后再试',
          );
        }
        if (status == 413) {
          return const FeedbackSubmitResult(
            success: false,
            message: '反馈内容过长',
          );
        }
        if (status == 400) {
          return FeedbackSubmitResult(
            success: false,
            message: serverMessage.isEmpty ? '反馈内容格式不正确' : serverMessage,
          );
        }
        if (status == 401 || status == 403) {
          return const FeedbackSubmitResult(
            success: false,
            message: '反馈服务验证失败，请更新客户端后重试',
          );
        }

        lastFailure = FeedbackSubmitResult(
          success: false,
          message: serverMessage.isEmpty
              ? '反馈服务暂时不可用（HTTP $status）'
              : serverMessage,
        );
      } on DioException catch (e) {
        final type = e.type;
        if (type == DioExceptionType.connectionTimeout ||
            type == DioExceptionType.sendTimeout ||
            type == DioExceptionType.receiveTimeout) {
          lastFailure = const FeedbackSubmitResult(
            success: false,
            message: '连接反馈服务器超时，请稍后重试',
          );
        } else {
          lastFailure = const FeedbackSubmitResult(
            success: false,
            message: '无法连接反馈服务器，请检查网络后重试',
          );
        }
      } catch (_) {
        lastFailure = const FeedbackSubmitResult(
          success: false,
          message: '提交失败，请稍后重试',
        );
      }
    }

    return lastFailure ??
        const FeedbackSubmitResult(
          success: false,
          message: '反馈服务暂时不可用，请稍后重试',
        );
  }
}
