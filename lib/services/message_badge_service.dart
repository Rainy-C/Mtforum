import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'api_service.dart';
import 'system_notification_service.dart';

/// 消息中心未读状态的单一数据源。
///
/// App 内 Badge 和 Android 系统私信通知共用同一份真实未读快照，
/// 避免 `checknewpm` 清零后两边状态互相矛盾。
class MessageBadgeService extends ChangeNotifier {
  MessageBadgeService._();
  static final MessageBadgeService instance = MessageBadgeService._();

  MessageUnreadSummary _summary = const MessageUnreadSummary.empty();
  MessageUnreadSummary get summary => _summary;
  PmConversationSummary? _latestPrivateMessage;
  PmConversationSummary? get latestPrivateMessage => _latestPrivateMessage;

  bool _refreshing = false;
  bool get refreshing => _refreshing;

  DateTime? _lastRefresh;
  int _generation = 0;
  int _activeRefreshId = 0;
  bool _rerunAfterCurrent = false;
  Timer? _pollTimer;
  bool _privateMessagePolling = false;
  int _privateMessageRefreshId = 0;

  static const Duration _minRefreshInterval = Duration(seconds: 30);
  static const Duration _noticePollInterval = Duration(minutes: 3);
  static const Duration _privateMessageListPollInterval = Duration(minutes: 3);
  static const String _lastSeenNoticeIdKey = 'last_seen_notice_id_v1';
  DateTime? _lastNoticePoll;
  DateTime? _lastPrivateMessageListPoll;

  void startPolling() {
    if (_pollTimer != null) return;
    _pollTimer = Timer.periodic(
      _minRefreshInterval,
      (_) => _refreshPrivateMessages(),
    );
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  UnreadBadgeInfo _privateMessageBadge(
    List<PmConversationSummary> conversations,
  ) {
    final unreadCount = conversations.where((item) => item.hasUnread).length;
    return unreadCount == 0
        ? const UnreadBadgeInfo.none()
        : UnreadBadgeInfo(count: unreadCount, hasUnread: true);
  }

  /// 每 30 秒先走轻量 checknewpm；kmnums 私信列表与通知列表每 3 分钟兜底。
  Future<void> _refreshPrivateMessages() async {
    final api = ApiService.instance;
    if (_privateMessagePolling || _refreshing) return;
    if (!api.isLoggedIn) {
      clear();
      return;
    }

    final generation = _generation;
    final pmRefreshId = ++_privateMessageRefreshId;
    _privateMessagePolling = true;
    try {
      var quickHasNew = false;
      try {
        quickHasNew = await api.checkNewPrivateMessage();
      } catch (_) {}
      final now = DateTime.now();
      final listDue = _lastPrivateMessageListPoll == null ||
          now.difference(_lastPrivateMessageListPoll!) >=
              _privateMessageListPollInterval;
      if (!quickHasNew && !listDue) {
        if (_lastNoticePoll == null ||
            now.difference(_lastNoticePoll!) >= _noticePollInterval) {
          await _refreshNoticeBadge();
        }
        return;
      }
      final conversations = await api.getPmConversations();
      _lastPrivateMessageListPoll = now;
      if (generation != _generation ||
          pmRefreshId != _privateMessageRefreshId ||
          !api.isLoggedIn) {
        return;
      }

      _summary = MessageUnreadSummary(
        privateMessages: _privateMessageBadge(conversations),
        notices: _summary.notices,
        friendRequests: _summary.friendRequests,
      );
      _latestPrivateMessage =
          conversations.isEmpty ? null : conversations.first;
      notifyListeners();
      await SystemNotificationService.instance
          .syncPrivateMessages(conversations);
      if (_lastNoticePoll == null ||
          DateTime.now().difference(_lastNoticePoll!) >= _noticePollInterval) {
        await _refreshNoticeBadge();
      }
    } catch (_) {
      // 网络失败时保留上一份状态和现有系统通知。
    } finally {
      _privateMessagePolling = false;
    }
  }

  Future<void> refresh({bool force = false}) async {
    final api = ApiService.instance;
    if (!api.isLoggedIn) {
      clear();
      return;
    }

    if (_refreshing) {
      if (force) {
        _rerunAfterCurrent = true;
        // 强制刷新通常来自“已读/恢复前台”，立即让旧私信快照失效。
        _privateMessageRefreshId++;
      }
      return;
    }
    final now = DateTime.now();
    if (!force &&
        _lastRefresh != null &&
        now.difference(_lastRefresh!) < _minRefreshInterval) {
      return;
    }

    final generation = _generation;
    final refreshId = ++_activeRefreshId;
    _refreshing = true;
    notifyListeners();
    try {
      final pmRefreshId = ++_privateMessageRefreshId;
      List<PmConversationSummary>? pmConversations;
      try {
        pmConversations = await api.getPmConversations();
      } catch (_) {
        // 列表请求失败时 getMessageUnreadSummary 会使用旧信号降级。
      }

      final next = await api.getMessageUnreadSummary(
        pmConversations: pmConversations,
      );
      if (generation == _generation && api.isLoggedIn) {
        if (pmConversations != null) {
          _lastPrivateMessageListPoll = DateTime.now();
          _latestPrivateMessage =
              pmConversations.isEmpty ? null : pmConversations.first;
        }
        final noticeBadge = await _detectNoticeBadge();
        _summary = MessageUnreadSummary(
          privateMessages: next.privateMessages,
          notices: noticeBadge,
          friendRequests: next.friendRequests,
        );
        _lastRefresh = DateTime.now();

        // 只有拿到真实列表快照才同步系统通知。请求失败时保留旧通知，
        // 避免一次网络异常把仍未读的系统通知错误清掉。
        if (pmConversations != null &&
            pmRefreshId == _privateMessageRefreshId) {
          await SystemNotificationService.instance
              .syncPrivateMessages(pmConversations);
        }
      }
    } catch (_) {
      // 未读探测属于辅助能力，失败时保留上一份状态，不影响主流程。
    } finally {
      if (refreshId == _activeRefreshId) {
        _refreshing = false;
        notifyListeners();
        if (_rerunAfterCurrent) {
          _rerunAfterCurrent = false;
          Future<void>.microtask(() => refresh(force: true));
        }
      }
    }
  }

  Future<UnreadBadgeInfo> _detectNoticeBadge() async {
    final api = ApiService.instance;
    if (!api.isLoggedIn) return const UnreadBadgeInfo.none();
    try {
      final page = await api.getNoticePage(view: 'mypost', page: 1);
      _lastNoticePoll = DateTime.now();
      final ids = page.items
          .map((item) => int.tryParse(item.id))
          .whereType<int>()
          .where((id) => id > 0)
          .toList(growable: false);
      if (ids.isEmpty) return const UnreadBadgeInfo.none();

      final prefs = await SharedPreferences.getInstance();
      final lastSeen = prefs.getInt(_lastSeenNoticeIdKey);
      final newest = ids.reduce((a, b) => a > b ? a : b);
      if (lastSeen == null) {
        // 首次启用只建立基线，不能把账号历史通知全部伪装成新通知。
        await prefs.setInt(_lastSeenNoticeIdKey, newest);
        return const UnreadBadgeInfo.none();
      }
      final count = ids.where((id) => id > lastSeen).length;
      return count == 0
          ? const UnreadBadgeInfo.none()
          : UnreadBadgeInfo(count: count, hasUnread: true);
    } catch (_) {
      return _summary.notices;
    }
  }

  Future<void> _refreshNoticeBadge() async {
    final badge = await _detectNoticeBadge();
    if (!ApiService.instance.isLoggedIn) return;
    _summary = MessageUnreadSummary(
      privateMessages: _summary.privateMessages,
      notices: badge,
      friendRequests: _summary.friendRequests,
    );
    notifyListeners();
  }

  Future<void> markNoticesSeen(Iterable<NoticeItem> items) async {
    final ids = items
        .map((item) => int.tryParse(item.id))
        .whereType<int>()
        .where((id) => id > 0)
        .toList(growable: false);
    if (ids.isNotEmpty) {
      final newest = ids.reduce((a, b) => a > b ? a : b);
      final prefs = await SharedPreferences.getInstance();
      final previous = prefs.getInt(_lastSeenNoticeIdKey) ?? 0;
      if (newest > previous) {
        await prefs.setInt(_lastSeenNoticeIdKey, newest);
      }
    }
    if (_summary.notices.isVisible) {
      _summary = MessageUnreadSummary(
        privateMessages: _summary.privateMessages,
        notices: const UnreadBadgeInfo.none(),
        friendRequests: _summary.friendRequests,
      );
      notifyListeners();
    }
  }

  void clear() {
    _generation++;
    _activeRefreshId++;
    _privateMessageRefreshId++;
    _rerunAfterCurrent = false;
    final hadState = _summary.hasUnread || _refreshing || _lastRefresh != null;
    _summary = const MessageUnreadSummary.empty();
    _latestPrivateMessage = null;
    _lastNoticePoll = null;
    _lastPrivateMessageListPoll = null;
    _lastRefresh = null;
    _refreshing = false;
    unawaited(SystemNotificationService.instance.clearPrivateMessages());
    if (hadState) notifyListeners();
  }
}
