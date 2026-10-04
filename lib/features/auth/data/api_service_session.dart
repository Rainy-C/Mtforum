part of '../../../services/api_service.dart';

extension _ApiServiceSessionPart on ApiService {
  Future<String> getFormhash() async {
    final currentAuth = _auth;
    final current = _formhash;

    if (currentAuth != null &&
        currentAuth.isNotEmpty &&
        current != null &&
        current.isNotEmpty &&
        _formhashAuth == currentAuth) {
      return current;
    }

    _formhash = null;
    _formhashAuth = null;
    return refreshFormhash();
  }
  Future<String> refreshFormhash() {
    final currentAuth = _auth;
    if (currentAuth == null || currentAuth.isEmpty) {
      return Future<String>.error(
        StateError('请先登录'),
      );
    }

    final running = _formhashRefreshFuture;
    if (running != null) {
      return running;
    }

    final generation = _sessionGeneration;
    final future = _refreshFormhashInternal(generation);
    _formhashRefreshFuture = future;

    future.then(
      (_) {
        if (generation == _sessionGeneration &&
            identical(_formhashRefreshFuture, future)) {
          _formhashRefreshFuture = null;
        }
      },
      onError: (Object _, StackTrace __) {
        if (generation == _sessionGeneration &&
            identical(_formhashRefreshFuture, future)) {
          _formhashRefreshFuture = null;
        }
      },
    );

    return future;
  }
  Future<String> _refreshFormhashInternal(
    int generation,
  ) async {
    // 这些页面都属于登录后常用页面。并发获取，首个有效结果立即返回。
    // mobile=2 明确要求移动模板，避免部分桌面模板不输出 formhash。
    final candidates = <String>[
      '/home.php?mod=space&do=profile&mycenter=1&mobile=2',
      '/k_misign-sign.html?mobile=2',
      '/home.php?mod=spacecp&ac=credit&mobile=2',
      '/forum.php?forumlist=1&mobile=2',
    ];

    final completer = Completer<String>();
    var remaining = candidates.length;

    for (final path in candidates) {
      unawaited(
        (() async {
          try {
            final response = await _dio
                .get<String>(
                  path,
                  options: Options(
                    responseType: ResponseType.plain,
                    followRedirects: true,
                    validateStatus: (status) =>
                        status != null && status < 400,
                  ),
                )
                .timeout(const Duration(seconds: 8));

            if (generation != _sessionGeneration) {
              return;
            }

            final hash = _extractFormhash(response.data ?? '');
            if (hash != null && hash.isNotEmpty) {
              _rememberFormhash(
                hash,
                generation: generation,
              );

              if (!completer.isCompleted) {
                completer.complete(hash);
              }
              return;
            }
          } catch (_) {
            // 单个候选失败不影响其它并发候选。
          } finally {
            remaining -= 1;

            if (remaining == 0 && !completer.isCompleted) {
              completer.completeError(
                StateError('未获取到 formhash'),
              );
            }
          }
        })(),
      );
    }

    return completer.future;
  }
  Future<void> _primeFormhashAfterLogin() async {
    try {
      await refreshFormhash().timeout(
        const Duration(seconds: 8),
      );
    } catch (_) {
      // 登录成功不应该依赖 formhash 是否在这一刻获取成功。
      // 回复/签到/收藏/商城等真正写操作会通过 getFormhash() 再获取。
    }
  }
  void _rememberFormhash(
    String hash, {
    int? generation,
  }) {
    if (hash.isEmpty) {
      return;
    }

    if (generation != null && generation != _sessionGeneration) {
      return;
    }

    // 未登录页面拿到的是游客 formhash，绝不能带进登录后的写操作。
    final currentAuth = _auth;
    if (currentAuth == null || currentAuth.isEmpty) {
      return;
    }

    _formhash = hash;
    _formhashAuth = currentAuth;

    unawaited(_prefs.setString('forum_formhash', hash));
    unawaited(_prefs.setString('forum_formhash_auth', currentAuth));
  }
  Future<void> _clearCachedFormhash() async {
    _sessionGeneration += 1;
    _formhash = null;
    _formhashAuth = null;
    _formhashRefreshFuture = null;
    _findPostPageCache.clear();
    _findPostPageCacheTimes.clear();
    _findPostPageRequests.clear();
    _favoriteDetailRequests.clear();

    await _prefs.remove('forum_formhash');
    await _prefs.remove('forum_formhash_auth');
  }
  String? _extractFormhash(String body) {
    final js = RegExp(
      r'''formhash\s*=\s*['"]([a-fA-F0-9]+)['"]''',
      caseSensitive: false,
    ).firstMatch(body);
    if (js != null) return js.group(1);

    final byName = RegExp(
      r'''name\s*=\s*['"]formhash['"][^>]*value\s*=\s*['"]([a-fA-F0-9]+)['"]''',
      caseSensitive: false,
    ).firstMatch(body);
    if (byName != null) return byName.group(1);

    final byValueFirst = RegExp(
      r'''value\s*=\s*['"]([a-fA-F0-9]+)['"][^>]*name\s*=\s*['"]formhash['"]''',
      caseSensitive: false,
    ).firstMatch(body);
    if (byValueFirst != null) return byValueFirst.group(1);

    // Comiis 的很多已登录页面不提供 input/JS 变量，而只把 formhash
    // 放在退出、私信删除等链接的 query 参数里。
    final byQuery = RegExp(
      r'''(?:[?&]|&amp;)formhash=([a-fA-F0-9]+)''',
      caseSensitive: false,
    ).firstMatch(body);
    return byQuery?.group(1);
  }
  String? _sessionCookieValueFromResponse(
    Response<dynamic> response,
    String name,
  ) {
    final headers = response.headers.map['set-cookie'];
    if (headers == null || headers.isEmpty) return null;

    final pattern = RegExp(
      '(?:^|,\\s*)${RegExp.escape(name)}=([^;,\\r\\n]*)',
      caseSensitive: false,
    );
    String? resolved;
    for (final header in headers) {
      final match = pattern.firstMatch(header);
      final value = match?.group(1)?.trim();
      if (value != null && value.isNotEmpty) {
        // 同名 Cookie 若在响应中出现多次，以最后一个非空值为准。
        resolved = value;
      }
    }
    return resolved;
  }
  Future<void> _backfillSessionCookieFromResponse(
    Response<dynamic> response,
    String name,
  ) async {
    final value = _sessionCookieValueFromResponse(response, name);
    if (value == null || value.isEmpty) return;

    final uri = Uri.parse(baseUrl);
    final existing = await _cookieJar.loadForRequest(uri);
    for (final cookie in existing) {
      if (cookie.name == name && cookie.value.isNotEmpty) {
        return;
      }
    }

    // 真实登录响应里的两个会话 Cookie 都是当前论坛域、Path=/。
    // 这里只在 CookieManager 漏收时兜底，不覆盖已经正常保存的 Cookie。
    final cookie = Cookie(name, value)..path = '/';
    await _cookieJar.saveFromResponse(uri, [cookie]);
  }
}
