part of '../../../models/models.dart';

class PmMessage {
  final String? pmid;
  final String? senderUid;
  final String content;
  final String time;
  final String date;
  final bool isMine;
  final List<String> imageUrls;

  const PmMessage({
    this.pmid,
    this.senderUid,
    required this.content,
    this.time = '',
    this.date = '',
    this.isMine = false,
    this.imageUrls = const [],
  });
}

class PmConversationData {
  final String touid;
  final String pmid;
  final String formhash;
  final String peerName;
  final String? peerAvatarUrl;
  final bool? peerOnline;
  final int endTimestamp;
  final List<PmMessage> messages;

  const PmConversationData({
    required this.touid,
    required this.pmid,
    required this.formhash,
    required this.peerName,
    this.peerAvatarUrl,
    this.peerOnline,
    required this.endTimestamp,
    this.messages = const [],
  });
}

class PmConversationSummary {
  final String touid;
  final String username;
  final String? avatarUrl;
  final String? lastMessage;
  final String? lastTime;
  final bool hasUnread;

  const PmConversationSummary({
    required this.touid,
    required this.username,
    this.avatarUrl,
    this.lastMessage,
    this.lastTime,
    this.hasUnread = false,
  });
}

/// 单个消息入口的未读状态。
///
/// Discuz 某些模板只给出“有新消息”标记而不输出精确数字，
/// 因此 [count] 允许为空；此时 UI 使用“新”Badge，而不是伪造数量。
class UnreadBadgeInfo {
  final int? count;
  final bool hasUnread;

  const UnreadBadgeInfo({
    this.count,
    this.hasUnread = false,
  });

  const UnreadBadgeInfo.none()
      : count = 0,
        hasUnread = false;

  bool get isVisible => hasUnread || (count ?? 0) > 0;

  String? get label {
    if (!isVisible) return null;
    final value = count;
    if (value == null) return '新';
    if (value > 99) return '99+';
    return '$value';
  }
}

/// 消息中心三类入口的未读汇总。
class MessageUnreadSummary {
  final UnreadBadgeInfo privateMessages;
  final UnreadBadgeInfo notices;
  final UnreadBadgeInfo friendRequests;

  const MessageUnreadSummary({
    this.privateMessages = const UnreadBadgeInfo.none(),
    this.notices = const UnreadBadgeInfo.none(),
    this.friendRequests = const UnreadBadgeInfo.none(),
  });

  const MessageUnreadSummary.empty()
      : privateMessages = const UnreadBadgeInfo.none(),
        notices = const UnreadBadgeInfo.none(),
        friendRequests = const UnreadBadgeInfo.none();

  bool get hasUnread =>
      privateMessages.isVisible || notices.isVisible || friendRequests.isVisible;

  /// 底部导航的汇总 Badge。若存在只能确认“有新消息”但无法确认数量的
  /// 来源，则用 `N+` / `新` 表示，避免把不完整数字当成精确总数。
  String? get totalLabel {
    final entries = [privateMessages, notices, friendRequests];
    var exactTotal = 0;
    var hasUnknown = false;

    for (final entry in entries) {
      if (!entry.isVisible) continue;
      if (entry.count == null) {
        hasUnknown = true;
      } else {
        exactTotal += entry.count!;
      }
    }

    if (exactTotal <= 0 && !hasUnknown) return null;
    if (hasUnknown) {
      if (exactTotal <= 0) return '新';
      return exactTotal > 99 ? '99+' : '$exactTotal+';
    }
    return exactTotal > 99 ? '99+' : '$exactTotal';
  }
}

class NoticeItem {
  final String id;
  final String type;
  final String authorUid;
  final String username;
  final String? avatarUrl;
  final String content;
  final String actionText;
  final String time;
  final String? targetTitle;
  final String? targetUrl;
  final String? tid;
  final String? pid;
  final String? ignoreUrl;
  final bool isSystem;
  final bool isUnread;

  const NoticeItem({
    this.id = '',
    this.type = '',
    this.authorUid = '',
    this.username = '',
    this.avatarUrl,
    required this.content,
    this.actionText = '',
    this.time = '',
    this.targetTitle,
    this.targetUrl,
    this.tid,
    this.pid,
    this.ignoreUrl,
    this.isSystem = false,
    this.isUnread = false,
  });

  bool get hasThreadTarget => tid != null && tid!.isNotEmpty;
}

class NoticePageData {
  final List<NoticeItem> items;
  final bool hasMore;
  final int totalPages;

  const NoticePageData({
    required this.items,
    this.hasMore = false,
    this.totalPages = 1,
  });
}
