import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 评论与回复通知共用的本地过滤设置。
///
/// 过滤只发生在客户端展示层，不会向论坛提交屏蔽规则，也不会改变论坛账号。
class CommentFilterService extends ChangeNotifier {
  CommentFilterService._();

  static final CommentFilterService instance = CommentFilterService._();

  static const _commentsEnabledKey = 'comment_filter_comments_enabled';
  static const _noticesEnabledKey = 'comment_filter_notices_enabled';
  static const _keywordsKey = 'comment_filter_keywords';
  static const _shortReplyEnabledKey = 'comment_filter_short_reply_enabled';
  static const _shortReplyMaxLengthKey =
      'comment_filter_short_reply_max_length';
  static const defaultShortReplyMaxLength = 3;

  bool _commentsEnabled = false;
  bool _noticesEnabled = false;
  bool _shortReplyEnabled = false;
  int _shortReplyMaxLength = defaultShortReplyMaxLength;
  List<String> _keywords = const [];
  bool _loaded = false;

  bool get commentsEnabled => _commentsEnabled;
  bool get noticesEnabled => _noticesEnabled;
  bool get shortReplyEnabled => _shortReplyEnabled;
  int get shortReplyMaxLength => _shortReplyMaxLength;
  List<String> get keywords => List.unmodifiable(_keywords);
  bool get hasKeywords => _keywords.isNotEmpty;
  bool get hasRules => hasKeywords || _shortReplyEnabled;

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _commentsEnabled = prefs.getBool(_commentsEnabledKey) ?? false;
    _noticesEnabled = prefs.getBool(_noticesEnabledKey) ?? false;
    _shortReplyEnabled = prefs.getBool(_shortReplyEnabledKey) ?? false;
    _shortReplyMaxLength = (prefs.getInt(_shortReplyMaxLengthKey) ??
            defaultShortReplyMaxLength)
        .clamp(1, 20)
        .toInt();
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

  Future<void> setShortReplyEnabled(bool value) async {
    _shortReplyEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_shortReplyEnabledKey, value);
  }

  Future<void> setShortReplyMaxLength(int value) async {
    _shortReplyMaxLength = value.clamp(1, 20).toInt();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_shortReplyMaxLengthKey, _shortReplyMaxLength);
  }

  Future<void> setKeywordsFromText(String value) async {
    _keywords = _normalize(value.split(RegExp(r'[,，;；\n\r]+')));
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keywordsKey, _keywords);
  }

  bool matches(String value) {
    return matchesKeyword(value) || matchesShortReply(value);
  }

  bool matchesKeyword(String value) {
    if (_keywords.isEmpty || value.trim().isEmpty) return false;
    final normalized = value.toLowerCase();
    return _keywords.any((keyword) => normalized.contains(keyword.toLowerCase()));
  }

  bool matchesShortReply(String value) {
    if (!_shortReplyEnabled) return false;
    final normalized = value.replaceAll(RegExp(r'\s+'), '');
    if (normalized.isEmpty) return false;
    return normalized.runes.length <= _shortReplyMaxLength;
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
