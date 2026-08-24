enum ForumLinkKind { thread, user, external }

class ForumLinkTarget {
  final ForumLinkKind kind;
  final String url;
  final String? id;
  final String? pid;

  const ForumLinkTarget({
    required this.kind,
    required this.url,
    this.id,
    this.pid,
  });
}

const String _forumBaseUrl = 'https://bbs.binmt.cc';

/// 将正文链接归一化，并识别 MT 论坛内部的帖子/用户链接。
///
/// 支持：
/// - thread-123-1-1.html
/// - forum.php?mod=viewthread&tid=123
/// - forum.php?mod=redirect&goto=findpost&ptid=123&pid=456
/// - space-uid-123.html
/// - home.php?mod=space&uid=123&do=profile
ForumLinkTarget resolveForumLink(String rawUrl) {
  final raw = _cleanRawUrl(rawUrl);
  final normalized = _normalizeUrl(raw);

  // 先对原始/归一化字符串做一次兜底识别。Discuz/Comiis 有时会给
  // href 混入转义、fragment 或不完全规范的 URL；只靠 Uri.path 判断会
  // 偶发漏掉 thread-xxxx-1-1.html，最终被当成外链交给浏览器。
  final directThread = _threadIdFromText(raw) ?? _threadIdFromText(normalized);
  final directUser = _userIdFromText(raw) ?? _userIdFromText(normalized);

  final uri = Uri.tryParse(normalized);
  final pid = _postIdFromText(raw) ?? _postIdFromText(normalized);
  final internal = _looksLikeForumUrl(raw) ||
      (uri != null && _isForumHost(uri.host));

  if (!internal) {
    return ForumLinkTarget(kind: ForumLinkKind.external, url: normalized);
  }

  if (directThread != null) {
    return ForumLinkTarget(
      kind: ForumLinkKind.thread,
      url: normalized,
      id: directThread,
      pid: pid,
    );
  }

  if (uri != null) {
    final tid = _threadId(uri, normalized);
    if (tid != null && tid.isNotEmpty) {
      return ForumLinkTarget(
        kind: ForumLinkKind.thread,
        url: normalized,
        id: tid,
        pid: pid,
      );
    }
  }

  if (directUser != null) {
    return ForumLinkTarget(
      kind: ForumLinkKind.user,
      url: normalized,
      id: directUser,
    );
  }

  if (uri != null) {
    final uid = _userId(uri, normalized);
    if (uid != null && uid.isNotEmpty) {
      return ForumLinkTarget(
        kind: ForumLinkKind.user,
        url: normalized,
        id: uid,
      );
    }
  }

  return ForumLinkTarget(kind: ForumLinkKind.external, url: normalized);
}

String? _postIdFromText(String value) {
  return RegExp(r'(?:[?&])pid=(\d+)', caseSensitive: false)
      .firstMatch(value)
      ?.group(1);
}

String _cleanRawUrl(String value) {
  return value
      .trim()
      .replaceAll('&amp;', '&')
      .replaceAll('&#38;', '&')
      .replaceAll('&#x26;', '&')
      .replaceAll('\u200b', '')
      .replaceAll('\ufeff', '');
}

String _normalizeUrl(String value) {
  if (value.isEmpty) return value;
  if (value.startsWith('//')) return 'https:$value';

  final parsed = Uri.tryParse(value);
  if (parsed != null && parsed.hasScheme) return value;

  final base = Uri.parse('$_forumBaseUrl/');
  return base.resolve(value).toString();
}

bool _isForumHost(String host) {
  final value = host.toLowerCase();
  return value == 'bbs.binmt.cc' ||
      value == 'www.bbs.binmt.cc' ||
      value == 'binmt.cc' ||
      value == 'www.binmt.cc';
}

bool _looksLikeForumUrl(String value) {
  final lower = value.toLowerCase();
  if (lower.startsWith('/') ||
      lower.startsWith('thread-') ||
      lower.startsWith('space-uid-') ||
      lower.startsWith('forum.php') ||
      lower.startsWith('home.php')) {
    return true;
  }
  return RegExp(
    r'^(?:https?:)?//(?:www\.)?(?:bbs\.)?binmt\.cc(?:/|$)',
    caseSensitive: false,
  ).hasMatch(value);
}

String? _threadIdFromText(String value) {
  final pretty = RegExp(
    r'(?:^|/)thread-(\d+)(?:-(?:\d+|\w+))*\.html(?:[?#].*)?$',
    caseSensitive: false,
  ).firstMatch(value);
  if (pretty != null) return pretty.group(1);

  final loosePretty = RegExp(
    r'(?:^|/)thread-(\d+)(?:-|\.html|$)',
    caseSensitive: false,
  ).firstMatch(value);
  if (loosePretty != null) return loosePretty.group(1);

  final query = RegExp(
    r'(?:[?&])(?:tid|ptid)=(\d+)',
    caseSensitive: false,
  ).firstMatch(value);
  return query?.group(1);
}

String? _userIdFromText(String value) {
  final match = RegExp(
    r'(?:space-uid-|[?&]uid=)(\d+)',
    caseSensitive: false,
  ).firstMatch(value);
  return match?.group(1);
}

String? _threadId(Uri uri, String raw) {
  final query = uri.queryParameters;
  final direct = query['tid'] ?? query['ptid'];
  if (direct != null && RegExp(r'^\d+$').hasMatch(direct)) {
    return direct;
  }

  final pretty = RegExp(
    r'(?:^|/)thread-(\d+)(?:-|\.html|$)',
    caseSensitive: false,
  ).firstMatch(uri.path);
  if (pretty != null) return pretty.group(1);

  final fallback = RegExp(
    r'(?:[?&])(?:tid|ptid)=(\d+)',
    caseSensitive: false,
  ).firstMatch(raw);
  return fallback?.group(1);
}

String? _userId(Uri uri, String raw) {
  final pretty = RegExp(
    r'(?:^|/)space-uid-(\d+)(?:-|\.html|$)',
    caseSensitive: false,
  ).firstMatch(uri.path);
  if (pretty != null) return pretty.group(1);

  final query = uri.queryParameters;
  final isSpacePage = uri.path.toLowerCase().endsWith('home.php') &&
      (query['mod']?.toLowerCase() == 'space' || query.containsKey('uid'));
  if (isSpacePage) {
    final uid = query['uid'];
    if (uid != null && RegExp(r'^\d+$').hasMatch(uid)) return uid;
  }

  final fallback = RegExp(
    r'(?:space-uid-|[?&]uid=)(\d+)',
    caseSensitive: false,
  ).firstMatch(raw);
  return fallback?.group(1);
}
