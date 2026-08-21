import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UpdateInfo {
  final String version;
  final int versionCode;
  final String changelog;
  final String downloadUrl;
  final int? size;

  const UpdateInfo({
    required this.version,
    required this.versionCode,
    required this.changelog,
    required this.downloadUrl,
    this.size,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      version: '${json['version'] ?? ''}'.trim(),
      versionCode: int.tryParse('${json['versionCode'] ?? 0}') ?? 0,
      changelog: '${json['changelog'] ?? ''}'.trim(),
      downloadUrl: '${json['downloadUrl'] ?? ''}'.trim(),
      size: int.tryParse('${json['size'] ?? ''}'),
    );
  }
}

class UpdateCheckResult {
  final String currentVersion;
  final int currentVersionCode;
  final UpdateInfo info;

  const UpdateCheckResult({
    required this.currentVersion,
    required this.currentVersionCode,
    required this.info,
  });

  bool get hasUpdate => info.versionCode > currentVersionCode;
}

class DownloadProgress {
  final int status;
  final int downloaded;
  final int total;

  const DownloadProgress({
    required this.status,
    required this.downloaded,
    required this.total,
  });

  double? get fraction {
    if (total <= 0) return null;
    return downloaded / total;
  }

  bool get completed => status == 8; // DownloadManager.STATUS_SUCCESSFUL
  bool get failed => status == 16; // DownloadManager.STATUS_FAILED
}

class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  static const _channel = MethodChannel('mtforum/update');
  static const _startupKey = 'startup_auto_check_update';
  static const manifestUrl = String.fromEnvironment(
    'MTFORUM_UPDATE_URL',
    defaultValue: '',
  );

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: const {
        'Accept': 'application/json',
        'Cache-Control': 'no-cache',
      },
    ),
  );

  Future<bool> getStartupCheckEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_startupKey) ?? true;
  }

  Future<void> setStartupCheckEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_startupKey, value);
  }

  Future<Map<String, dynamic>> getCurrentVersionInfo() async {
    final raw = await _channel.invokeMapMethod<String, dynamic>('getVersionInfo');
    return raw ?? const <String, dynamic>{};
  }

  Future<UpdateCheckResult> check() async {
    if (manifestUrl.isEmpty) {
      throw StateError('更新地址未配置，请通过 MTFORUM_UPDATE_URL 构建');
    }

    final version = await getCurrentVersionInfo();
    final currentName = '${version['versionName'] ?? ''}';
    final currentCode = int.tryParse('${version['versionCode'] ?? 0}') ?? 0;

    final response = await _dio.get<dynamic>(
      manifestUrl,
      queryParameters: {'_': DateTime.now().millisecondsSinceEpoch},
      options: Options(responseType: ResponseType.plain),
    );

    dynamic decoded = response.data;
    if (decoded is String) decoded = jsonDecode(decoded);
    if (decoded is! Map) {
      throw const FormatException('update.json 格式错误');
    }

    final info = UpdateInfo.fromJson(
      decoded.map((key, value) => MapEntry(key.toString(), value)),
    );
    if (info.version.isEmpty ||
        info.versionCode <= 0 ||
        info.downloadUrl.isEmpty) {
      throw const FormatException('update.json 缺少必要字段');
    }

    return UpdateCheckResult(
      currentVersion: currentName,
      currentVersionCode: currentCode,
      info: info,
    );
  }

  Future<int> startDownload(UpdateInfo info) async {
    final id = await _channel.invokeMethod<int>('startDownload', {
      'url': info.downloadUrl,
      'fileName': 'MTForum-${info.version}-Release.apk',
    });
    if (id == null) throw StateError('启动下载失败');
    return id;
  }

  Future<DownloadProgress> queryDownload(int id) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'queryDownload',
      {'id': id},
    );
    if (result == null) {
      return const DownloadProgress(status: 16, downloaded: 0, total: 0);
    }
    return DownloadProgress(
      status: int.tryParse('${result['status'] ?? 0}') ?? 0,
      downloaded: int.tryParse('${result['downloaded'] ?? 0}') ?? 0,
      total: int.tryParse('${result['total'] ?? 0}') ?? 0,
    );
  }

  Future<String> installDownload(int id) async {
    return await _channel.invokeMethod<String>('installDownload', {'id': id}) ??
        'failed';
  }
}

Future<void> showUpdateDialog(
  BuildContext context,
  UpdateCheckResult result,
) async {
  if (!result.hasUpdate) return;
  final info = result.info;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('发现新版本'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('v${result.currentVersion}  →  v${info.version}'),
          const SizedBox(height: 12),
          Text(info.changelog.isEmpty ? '新版本可用' : info.changelog),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('稍后'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(dialogContext);
            showUpdateDownloadDialog(context, info);
          },
          child: const Text('下载更新'),
        ),
      ],
    ),
  );
}

Future<void> showUpdateDownloadDialog(
  BuildContext context,
  UpdateInfo info,
) async {
  final service = UpdateService.instance;
  int? downloadId;
  Timer? timer;
  final progress = ValueNotifier<DownloadProgress?>(null);
  final error = ValueNotifier<String?>(null);

  try {
    downloadId = await service.startDownload(info);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('下载失败：$e')),
      );
    }
    progress.dispose();
    error.dispose();
    return;
  }

  timer = Timer.periodic(const Duration(milliseconds: 650), (_) async {
    try {
      final value = await service.queryDownload(downloadId!);
      progress.value = value;
      if (value.completed || value.failed) timer?.cancel();
      if (value.failed) error.value = '安装包下载失败';
    } catch (e) {
      timer?.cancel();
      error.value = '$e';
    }
  });

  if (!context.mounted) {
    timer?.cancel();
    progress.dispose();
    error.dispose();
    return;
  }

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text('正在下载 v${info.version}'),
        content: ValueListenableBuilder<DownloadProgress?>(
          valueListenable: progress,
          builder: (_, value, __) {
            return ValueListenableBuilder<String?>(
              valueListenable: error,
              builder: (_, errorText, __) {
                if (errorText != null) return Text(errorText);
                if (value == null) {
                  return const LinearProgressIndicator();
                }
                if (value.completed) {
                  return const Text('下载完成，可以安装新版本。');
                }
                final percent = value.fraction == null
                    ? null
                    : '${(value.fraction! * 100).clamp(0, 100).toStringAsFixed(0)}%';
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LinearProgressIndicator(value: value.fraction),
                    const SizedBox(height: 10),
                    Text(percent == null ? '下载中…' : '下载中 $percent'),
                  ],
                );
              },
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              timer?.cancel();
              Navigator.pop(dialogContext);
            },
            child: const Text('后台下载'),
          ),
          ValueListenableBuilder<DownloadProgress?>(
            valueListenable: progress,
            builder: (_, value, __) {
              return FilledButton(
                onPressed: value?.completed == true
                    ? () async {
                        final result = await service.installDownload(downloadId!);
                        if (result == 'permission') {
                          if (dialogContext.mounted) {
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              const SnackBar(
                                content: Text('请允许“安装未知应用”，返回后再次点击安装'),
                              ),
                            );
                          }
                        } else if (result == 'started' && dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                        }
                      }
                    : null,
                child: const Text('安装'),
              );
            },
          ),
        ],
      );
    },
  );

  timer?.cancel();
  progress.dispose();
  error.dispose();
}
