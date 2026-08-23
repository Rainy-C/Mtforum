import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/models.dart';

/// Android 系统通知同步。
///
/// 不参与 App 内 Badge 展示，只把服务端真实未读私信状态同步到通知栏。
class SystemNotificationService {
  SystemNotificationService._();
  static final SystemNotificationService instance = SystemNotificationService._();

  static const MethodChannel _channel = MethodChannel('mtforum/notifications');

  bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> syncPrivateMessages(
    List<PmConversationSummary> conversations,
  ) async {
    if (!_supported) return;

    final unread = conversations
        .where((item) => item.hasUnread)
        .map(
          (item) => <String, String>{
            'touid': item.touid,
            'username': item.username,
            'message': item.lastMessage?.trim() ?? '',
          },
        )
        .toList(growable: false);

    try {
      await _channel.invokeMethod<void>(
        'syncPrivateMessages',
        {'messages': unread},
      );
    } on PlatformException {
      // 系统通知属于辅助能力，不因为权限/ROM 异常破坏消息主流程。
    } on MissingPluginException {
      // 非 Android 或旧安装包上静默跳过。
    }
  }

  Future<String?> takePendingPrivateMessageTouid() async {
    if (!_supported) return null;
    try {
      final value = await _channel.invokeMethod<String>(
        'takePendingPrivateMessageTouid',
      );
      final touid = value?.trim();
      return touid == null || touid.isEmpty ? null : touid;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> clearPrivateMessages() async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('clearPrivateMessages');
    } on PlatformException {
      // 同上。
    } on MissingPluginException {
      // 同上。
    }
  }
}
