import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'api_service.dart';

/// 消息中心未读状态的单一数据源。
///
/// 底部导航和消息页共用这一份状态，避免各页面分别请求后出现 Badge 不一致。
class MessageBadgeService extends ChangeNotifier {
  MessageBadgeService._();
  static final MessageBadgeService instance = MessageBadgeService._();

  MessageUnreadSummary _summary = const MessageUnreadSummary.empty();
  MessageUnreadSummary get summary => _summary;

  bool _refreshing = false;
  bool get refreshing => _refreshing;

  DateTime? _lastRefresh;
  int _generation = 0;
  int _activeRefreshId = 0;
  bool _rerunAfterCurrent = false;
  static const Duration _minRefreshInterval = Duration(seconds: 20);

  Future<void> refresh({bool force = false}) async {
    final api = ApiService.instance;
    if (!api.isLoggedIn) {
      clear();
      return;
    }

    if (_refreshing) {
      if (force) _rerunAfterCurrent = true;
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
      final next = await api.getMessageUnreadSummary();
      if (generation == _generation && api.isLoggedIn) {
        _summary = next;
        _lastRefresh = DateTime.now();
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

  void clear() {
    _generation++;
    _activeRefreshId++;
    _rerunAfterCurrent = false;
    final hadState = _summary.hasUnread || _refreshing || _lastRefresh != null;
    _summary = const MessageUnreadSummary.empty();
    _lastRefresh = null;
    _refreshing = false;
    if (hadState) notifyListeners();
  }
}
