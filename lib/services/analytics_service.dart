import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'feedback_service.dart';
import 'update_service.dart';

class AppStats {
  final int totalLaunches;
  final int uniqueInstalls;
  final int active7d;
  final int active30d;

  const AppStats({
    required this.totalLaunches,
    required this.uniqueInstalls,
    required this.active7d,
    required this.active30d,
  });
}

class AnalyticsService {
  AnalyticsService._();
  static final AnalyticsService instance = AnalyticsService._();

  static const _installIdKey = 'anonymous_install_id_v1';

  /// 如需把统计接口部署到和反馈接口不同的服务器，可单独覆盖
  /// --dart-define=MTFORUM_ANALYTICS_URL=https://example.com/api/v1/app/launch
  static const _launchEndpointOverride = String.fromEnvironment(
    'MTFORUM_ANALYTICS_URL',
    defaultValue: '',
  );

  /// 可选。默认会从启动统计接口自动推导到 /api/v1/app/stats
  static const _statsEndpointOverride = String.fromEnvironment(
    'MTFORUM_STATS_URL',
    defaultValue: '',
  );

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      sendTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 10),
      responseType: ResponseType.plain,
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json; charset=utf-8',
      },
      validateStatus: (status) => status != null && status >= 200 && status < 600,
    ),
  );

  late final String _launchId = _generateOpaqueId();
  Future<AppStats?>? _reportFuture;
  AppStats? _latestStats;

  AppStats? get latestStats => _latestStats;
  bool get isConfigured => _launchEndpoints.isNotEmpty && _statsEndpoints.isNotEmpty;

  List<String> get _launchEndpoints {
    if (_launchEndpointOverride.isNotEmpty) {
      return <String>[_launchEndpointOverride];
    }
    return _dedupeEndpoints(
      FeedbackService.endpointCandidates
          .map((endpoint) => _replaceFeedbackEndpoint(endpoint, 'app/launch')),
    );
  }

  List<String> get _statsEndpoints {
    if (_statsEndpointOverride.isNotEmpty) {
      return <String>[_statsEndpointOverride];
    }
    if (_launchEndpointOverride.isNotEmpty) {
      return <String>[
        _replaceLastPathSegment(_launchEndpointOverride, 'stats'),
      ];
    }
    return _dedupeEndpoints(
      FeedbackService.endpointCandidates
          .map((endpoint) => _replaceFeedbackEndpoint(endpoint, 'app/stats')),
    );
  }

  /// 每个 App 进程只会上报一次，同一进程重复调用会复用同一个 Future
  Future<AppStats?> reportLaunch() {
    return _reportFuture ??= _reportLaunchImpl();
  }

  Future<AppStats?> _reportLaunchImpl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var installId = prefs.getString(_installIdKey)?.trim() ?? '';
      if (!_isValidOpaqueId(installId)) {
        installId = _generateOpaqueId();
        await prefs.setString(_installIdKey, installId);
      }

      var versionName = '';
      var versionCode = '';
      try {
        final info = await UpdateService.instance.getCurrentVersionInfo();
        versionName = '${info['versionName'] ?? ''}'.trim();
        versionCode = '${info['versionCode'] ?? ''}'.trim();
      } catch (_) {
        // 版本信息缺失不影响匿名启动统计
      }

      final headers = <String, dynamic>{};
      if (FeedbackService.appToken.isNotEmpty) {
        headers['X-MTForum-Token'] = FeedbackService.appToken;
      }

      for (final endpoint in _launchEndpoints) {
        try {
          final response = await _dio.post<String>(
            endpoint,
            data: jsonEncode({
              'installId': installId,
              'launchId': _launchId,
              'appVersion': versionName,
              'versionCode': versionCode,
              'platform': Platform.operatingSystem,
            }),
            options: Options(headers: headers),
          );

          if ((response.statusCode ?? 0) < 200 ||
              (response.statusCode ?? 0) >= 300) {
            continue;
          }

          final stats = _parseStats(response.data);
          if (stats != null) {
            _latestStats = stats;
          }
          return stats;
        } catch (_) {
          // 当前统计服务不可用时自动尝试下一个候选地址。
        }
      }
      return null;
    } catch (_) {
      // 匿名统计永远不能影响正常启动
      return null;
    }
  }

  Future<AppStats?> fetchStats() async {
    for (final endpoint in _statsEndpoints) {
      try {
        final response = await _dio.get<String>(endpoint);
        if ((response.statusCode ?? 0) < 200 ||
            (response.statusCode ?? 0) >= 300) {
          continue;
        }

        final stats = _parseStats(response.data);
        if (stats != null) {
          _latestStats = stats;
          return stats;
        }
      } catch (_) {
        // 当前统计查询地址失败时继续尝试候选地址。
      }
    }
    return _latestStats;
  }

  AppStats? _parseStats(String? raw) {
    return parseStatsForTest(raw);
  }

  static AppStats? parseStatsForTest(String? raw) {
    final text = raw?.trim() ?? '';
    if (text.isEmpty) return null;

    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) return null;
      if (decoded['ok'] == false || decoded['status'] == false) return null;
      final payload = decoded['data'] is Map
          ? decoded['data'] as Map
          : decoded;

      int readInt(String key) {
        final value = payload[key];
        if (value is int) return value;
        if (value is num) return value.toInt();
        return int.tryParse('$value') ?? 0;
      }

      return AppStats(
        totalLaunches: readInt('totalLaunches'),
        uniqueInstalls: readInt('uniqueInstalls'),
        active7d: readInt('active7d'),
        active30d: readInt('active30d'),
      );
    } catch (_) {
      return null;
    }
  }

  String _replaceFeedbackEndpoint(String endpoint, String suffix) {
    try {
      final uri = Uri.parse(endpoint);
      final segments = List<String>.from(uri.pathSegments);
      if (segments.isNotEmpty && segments.last == 'feedback') {
        segments.removeLast();
      }
      segments.addAll(suffix.split('/'));
      return uri
          .replace(pathSegments: segments, query: null, fragment: null)
          .toString();
    } catch (_) {
      return endpoint;
    }
  }

  List<String> _dedupeEndpoints(Iterable<String> values) {
    final seen = <String>{};
    final out = <String>[];
    for (final value in values) {
      final normalized = value.trim();
      if (normalized.isNotEmpty && seen.add(normalized)) {
        out.add(normalized);
      }
    }
    return out;
  }

  String _replaceLastPathSegment(String endpoint, String replacement) {
    try {
      final uri = Uri.parse(endpoint);
      final segments = List<String>.from(uri.pathSegments);
      if (segments.isEmpty) return endpoint;
      segments[segments.length - 1] = replacement;
      return uri
          .replace(pathSegments: segments, query: null, fragment: null)
          .toString();
    } catch (_) {
      return endpoint;
    }
  }

  static bool _isValidOpaqueId(String value) {
    return RegExp(r'^[A-Za-z0-9_-]{16,128}$').hasMatch(value);
  }

  static String _generateOpaqueId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  }
}
