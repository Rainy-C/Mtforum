import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 「自动回复隐藏帖」设置。
///
/// 论坛里有一部分帖子把内容设成"回复可见"，不回复就什么都看不到。
/// 打开开关后，App 进入这类帖子时会自动用配置好的内容回复一次，
/// 随后刷新页面把隐藏内容显示出来。
///
/// **只处理"回复可见"这一类**：解析器把"没有权限查看 / 阅读权限不足"也归到了
/// `hiddenHint`，那种帖子回复了也看不到，自动回复只会平白打扰楼主，所以要排除。
class AutoReplyService extends ChangeNotifier {
  AutoReplyService._();

  static final AutoReplyService instance = AutoReplyService._();

  static const String _enabledKey = 'auto_reply_hidden_enabled';
  static const String _contentKey = 'auto_reply_hidden_content';
  static const String _repliedKey = 'auto_reply_replied_tids';

  /// 默认回复内容，用户可在设置里改。
  static const String defaultContent = '感谢分享，回复看看隐藏内容';

  /// 最多记住多少个已自动回复过的帖子，避免偏好设置无限增长。
  static const int _maxRemembered = 200;

  bool _enabled = false;
  String _content = defaultContent;
  List<String> _replied = const [];
  bool _loaded = false;

  bool get enabled => _enabled;
  String get content => _content.trim().isEmpty ? defaultContent : _content;
  bool get loaded => _loaded;

  /// 开关打开且回复内容非空时才真正生效。
  bool get active => _enabled && _content.trim().isNotEmpty;

  Future<void> init() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_enabledKey) ?? false;
    final saved = prefs.getString(_contentKey);
    if (saved != null && saved.trim().isNotEmpty) {
      _content = saved;
    }
    _replied = prefs.getStringList(_repliedKey) ?? const <String>[];
    _loaded = true;
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;
    _enabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
  }

  Future<void> setContent(String value) async {
    final next = value.trim();
    if (next.isEmpty || next == _content) return;
    _content = next;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_contentKey, next);
  }

  /// 已记录"自动回复过"的帖子数量。
  int get repliedCount => _replied.length;

  /// 这个帖子是否已经自动回复过（避免重复发帖）。
  bool hasReplied(String tid) => tid.isNotEmpty && _replied.contains(tid);

  Future<void> markReplied(String tid) async {
    if (tid.isEmpty || _replied.contains(tid)) return;
    final next = [..._replied, tid];
    _replied = next.length > _maxRemembered
        ? next.sublist(next.length - _maxRemembered)
        : next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_repliedKey, _replied);
  }

  /// 清空"已自动回复"记录（用户换号或想重新自动回复时用）。
  Future<void> clearRepliedHistory() async {
    if (_replied.isEmpty) return;
    _replied = const [];
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_repliedKey);
  }

  /// 该提示是否属于"回复可见"（而不是"权限不足"）。
  ///
  /// 只有回复能解锁的才值得自动回复；权限不足的帖子回复了也没用。
  static bool isReplyGatedHint(String? hint) {
    final text = (hint ?? '').trim();
    if (text.isEmpty) return false;
    if (text.contains('权限') || text.contains('无权')) return false;
    return text.contains('回复');
  }
}
