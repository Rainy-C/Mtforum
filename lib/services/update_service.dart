import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

List<String> normalizeUpdateChangelog(String raw) {
  var text = raw.trim();
  if (text.isEmpty) return const [];

  // 兼容服务端常见的几种公告格式：真实换行、JSON 中二次转义的
  // \\n/\\r\\n、HTML <br> / <p> / <li>，避免正文全部粘成一行。
  text = text
      .replaceAll(r'\r\n', '\n')
      .replaceAll(r'\n', '\n')
      .replaceAll(r'\r', '\n')
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</(?:p|div|li)>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<li\b[^>]*>', caseSensitive: false), '• ')
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll(RegExp(r'[\t ]+[•●▪]\s*'), '\n• ')
      .replaceAllMapped(
        RegExp(r'([。；;])\s*(?=\d{1,2}[.、)])'),
        (match) => '${match.group(1)}\n',
      );

  final lines = text
      .split(RegExp(r'[\n\r]+'))
      .map((line) => line
          .replaceFirst(RegExp(r'^[•●▪*\-]+\s*'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim())
      .where((line) => line.isNotEmpty)
      .toList();

  // 某些 update.json 只有一整个中文段落且完全没有换行；长度较长时按
  // 句号/分号/问号/感叹号拆成易读条目。没有自然分隔符时保持原文。
  if (lines.length == 1 && lines.first.length > 48) {
    final sentenceLines = <String>[];
    final buffer = StringBuffer();
    for (final rune in lines.first.runes) {
      final char = String.fromCharCode(rune);
      buffer.write(char);
      if ('。！？；;'.contains(char)) {
        final value = buffer.toString().trim();
        if (value.isNotEmpty) sentenceLines.add(value);
        buffer.clear();
      }
    }
    final tail = buffer.toString().trim();
    if (tail.isNotEmpty) sentenceLines.add(tail);
    if (sentenceLines.length > 1) return sentenceLines;
  }

  return lines;
}

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

    var info = UpdateInfo.fromJson(
      decoded.map((key, value) => MapEntry(key.toString(), value)),
    );
    final rawDownloadUri = Uri.tryParse(info.downloadUrl);
    if (rawDownloadUri != null && !rawDownloadUri.hasScheme) {
      info = UpdateInfo(
        version: info.version,
        versionCode: info.versionCode,
        changelog: info.changelog,
        downloadUrl: Uri.parse(manifestUrl).resolveUri(rawDownloadUri).toString(),
        size: info.size,
      );
    }
    if (info.version.isEmpty ||
        info.versionCode <= 0 ||
        info.downloadUrl.isEmpty) {
      throw const FormatException('update.json 缺少必要字段');
    }
    final downloadUri = Uri.tryParse(info.downloadUrl);
    if (downloadUri == null ||
        !const {'http', 'https'}.contains(downloadUri.scheme.toLowerCase()) ||
        downloadUri.host.isEmpty) {
      throw const FormatException(
        'update.json 的 downloadUrl 必须是 http/https 安装包地址',
      );
    }

    return UpdateCheckResult(
      currentVersion: currentName,
      currentVersionCode: currentCode,
      info: info,
    );
  }

  Future<int> startDownload(UpdateInfo info) async {
    final uri = Uri.tryParse(info.downloadUrl);
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        uri.host.isEmpty) {
      throw StateError('软件更新下载地址无效，只支持 http/https');
    }
    final id = await _channel.invokeMethod<int>('startDownload', {
      'url': info.downloadUrl,
      'fileName': 'MTForum-${info.version}-Release.apk',
    });
    if (id == null) throw StateError('启动下载失败');
    return id;
  }

  Future<void> openDownloadInBrowser(UpdateInfo info) async {
    final uri = Uri.tryParse(info.downloadUrl);
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        uri.host.isEmpty) {
      throw StateError('软件更新下载地址无效，只支持 http/https');
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) throw StateError('无法打开浏览器');
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
  final theme = Theme.of(context);
  final colors = theme.colorScheme;

  final lines = normalizeUpdateChangelog(info.changelog);

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: Icon(Icons.system_update_rounded, color: colors.primary),
      title: const Text('发现新版本'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 版本号卡片
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: colors.primaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'v${result.currentVersion}',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colors.onPrimaryContainer.withValues(alpha: 0.7),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.arrow_forward_rounded,
                        size: 18, color: colors.primary),
                  ),
                  Text(
                    'v${info.version}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colors.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            // 更新日志标题
            Row(
              children: [
                Icon(Icons.edit_note_rounded,
                    size: 18, color: colors.primary),
                const SizedBox(width: 5),
                Text(
                  '更新内容',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 更新日志内容。统一规范化换行后放在独立内容区，避免长公告粘连。
            Flexible(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: lines.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '新版本可用',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      )
                    : SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final line in lines)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(top: 7),
                                      child: Container(
                                        width: 5,
                                        height: 5,
                                        decoration: BoxDecoration(
                                          color: colors.primary,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 9),
                                    Expanded(
                                      child: Text(
                                        line,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(height: 1.55),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('稍后'),
        ),
        OutlinedButton.icon(
          onPressed: () async {
            Navigator.pop(dialogContext);
            try {
              await UpdateService.instance.openDownloadInBrowser(info);
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('打开浏览器失败：$e')),
                );
              }
            }
          },
          icon: const Icon(Icons.open_in_browser_rounded, size: 18),
          label: const Text('浏览器更新'),
        ),
        FilledButton.icon(
          onPressed: () {
            Navigator.pop(dialogContext);
            showUpdateDownloadDialog(context, info);
          },
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text('内置更新'),
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
