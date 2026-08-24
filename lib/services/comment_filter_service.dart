import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 评论与回复通知共用的本地关键词过滤设置。
///
/// 过滤只发生在客户端展示层，不会向论坛提交屏蔽规则，也不会改变论坛账号。
class CommentFilterService extends ChangeNotifier {
  CommentFilterService._();

  static final CommentFilterService instance = CommentFilterService._();

  static const _commentsEnabledKey = 'comment_filter_comments_enabled';
  static const _noticesEnabledKey = 'comment_filter_notices_enabled';
  static const _keywordsKey = 'comment_filter_keywords';

  bool _commentsEnabled = false;
  bool _noticesEnabled = false;
  List<String> _keywords = const [];
  bool _loaded = false;

  bool get commentsEnabled => _commentsEnabled;
  bool get noticesEnabled => _noticesEnabled;
  List<String> get keywords => List.unmodifiable(_keywords);
  bool get hasKeywords => _keywords.isNotEmpty;

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _commentsEnabled = prefs.getBool(_commentsEnabledKey) ?? false;
    _noticesEnabled = prefs.getBool(_noticesEnabledKey) ?? false;
    _keywords = _normalize(prefs.getStringList(_keywordsKey) ?? const []);
    _loaded = true;
    notifyListeners();
  }

  Future<void> setCommentsEnabled(bool value) async {
    _commentsEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_commentsEnabledKey, value);
  }

  Future<void> setNoticesEnabled(bool value) async {
    _noticesEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_noticesEnabledKey, value);
  }

  Future<void> setKeywordsFromText(String value) async {
    _keywords = _normalize(value.split(RegExp(r'[,，;；\n\r]+')));
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keywordsKey, _keywords);
  }

  bool matches(String value) {
    if (_keywords.isEmpty || value.trim().isEmpty) return false;
    final normalized = value.toLowerCase();
    return _keywords.any((keyword) => normalized.contains(keyword.toLowerCase()));
  }

  List<String> _normalize(Iterable<String> values) {
    final result = <String>[];
    final seen = <String>{};
    for (final value in values) {
      final keyword = value.trim();
      final key = keyword.toLowerCase();
      if (keyword.isNotEmpty && seen.add(key)) result.add(keyword);
    }
    return result;
  }
}
