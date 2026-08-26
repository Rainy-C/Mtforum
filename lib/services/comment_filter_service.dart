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
  static const _keywordContainsEnabledKey =
      'comment_filter_keyword_contains_enabled';
  static const _matchLengthLimitEnabledKey =
      'comment_filter_match_length_limit_enabled';
  static const _maxMatchedContentLengthKey =
      'comment_filter_max_matched_content_length';
  static const defaultMaxMatchedContentLength = 20;

  bool _commentsEnabled = false;
  bool _noticesEnabled = false;
  bool _keywordContainsEnabled = false;
  bool _matchLengthLimitEnabled = false;
  int _maxMatchedContentLength = defaultMaxMatchedContentLength;
  List<String> _keywords = const [];
  bool _loaded = false;

  bool get commentsEnabled => _commentsEnabled;
  bool get noticesEnabled => _noticesEnabled;
  bool get keywordContainsEnabled => _keywordContainsEnabled;
  bool get fuzzyMatchingEnabled => _keywordContainsEnabled;
  bool get matchLengthLimitEnabled => _matchLengthLimitEnabled;
  int get maxMatchedContentLength => _maxMatchedContentLength;
  List<String> get keywords => List.unmodifiable(_keywords);
  bool get hasKeywords => _keywords.isNotEmpty;
  bool get hasRules => hasKeywords;

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _commentsEnabled = prefs.getBool(_commentsEnabledKey) ?? false;
    _noticesEnabled = prefs.getBool(_noticesEnabledKey) ?? false;
    _keywordContainsEnabled =
        prefs.getBool(_keywordContainsEnabledKey) ?? false;
    _matchLengthLimitEnabled =
        prefs.getBool(_matchLengthLimitEnabledKey) ?? false;
    _maxMatchedContentLength =
        (prefs.getInt(_maxMatchedContentLengthKey) ??
                defaultMaxMatchedContentLength)
            .clamp(1, 500)
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

  Future<void> setKeywordContainsEnabled(bool value) async {
    _keywordContainsEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keywordContainsEnabledKey, value);
  }

  Future<void> setFuzzyMatchingEnabled(bool value) {
    return setKeywordContainsEnabled(value);
  }

  Future<void> setMatchLengthLimitEnabled(bool value) async {
    _matchLengthLimitEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_matchLengthLimitEnabledKey, value);
  }

  Future<void> setMaxMatchedContentLength(int value) async {
    _maxMatchedContentLength = value.clamp(1, 500).toInt();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _maxMatchedContentLengthKey,
      _maxMatchedContentLength,
    );
  }

  Future<void> setKeywordsFromText(String value) async {
    _keywords = _normalize(value.split(RegExp(r'[,，;；\n\r]+')));
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keywordsKey, _keywords);
  }

  bool matches(String value) => matchesKeyword(value);

  bool matchesKeyword(String value) {
    if (_keywords.isEmpty || value.trim().isEmpty) return false;
    final normalized = _normalizeMatchText(value);
    final matched = _keywords.any(
      (keyword) {
        final normalizedKeyword = _normalizeMatchText(keyword);
        return _keywordContainsEnabled
            ? normalized.contains(normalizedKeyword)
            : normalized == normalizedKeyword;
      },
    );
    if (!matched) return false;
    if (!_matchLengthLimitEnabled) return true;
    final contentLength = value.replaceAll(RegExp(r'\s+'), '').runes.length;
    return contentLength <= _maxMatchedContentLength;
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

  String _normalizeMatchText(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }
}
