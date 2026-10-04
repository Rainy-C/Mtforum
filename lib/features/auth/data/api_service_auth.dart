part of '../../../services/api_service.dart';

extension ApiServiceAuthPart on ApiService {
  Future<LoginResult> login(
    String username,
    String password, {
    int questionId = 0,
    String answer = '',
  }) async {
    await _cookieJar.deleteAll();
    _auth = null;
    _saltkey = null;
    _currentUid = null;
    await _clearCachedFormhash();

    final loginPage = await _dio.get<String>(
      '/member.php',
      queryParameters: const {
        'mod': 'logging',
        'action': 'login',
        'mobile': 2,
      },
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
        validateStatus: (status) => status != null && status < 400,
      ),
    );

    // 真实论坛在 GET 登录页阶段下发 saltkey。正常情况下 CookieManager
    // 会自动写入 CookieJar，但历史上存在极低概率的“页面已拿到 Set-Cookie，
    // Jar 中却没有 saltkey”情况。直接从真实响应头兜底回填，避免后续把
    // 已经成功的登录误判成会话 Cookie 缺失。
    await _backfillSessionCookieFromResponse(
      loginPage,
      'cQWy_2132_saltkey',
    );

    final loginHtml = loginPage.data ?? '';
    final formhash = _extractFormhash(loginHtml) ?? '';
    final loginhash = RegExp(r'loginhash=([A-Za-z0-9]+)')
            .firstMatch(loginHtml)
            ?.group(1) ??
        '';

    if (formhash.isEmpty || loginhash.isEmpty) {
      return const LoginResult(
        success: false,
        message: '无法获取登录表单凭证',
      );
    }

    final response = await _dio.post<String>(
      '/member.php',
      queryParameters: {
        'mod': 'logging',
        'action': 'login',
        'loginsubmit': 'yes',
        'loginhash': loginhash,
        'handlekey': 'loginform',
        'inajax': 1,
      },
      data: {
        'formhash': formhash,
        'referer': '${ApiService.baseUrl}/forum.php',
        'fastloginfield': 'username',
        'cookietime': '31104000',
        'username': username,
        'password': password,
        'questionid': '$questionId',
        'answer': answer,
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: {
          'X-Requested-With': 'XMLHttpRequest',
          'Referer': '${ApiService.baseUrl}/member.php?mod=logging&action=login&mobile=2',
        },
        responseType: ResponseType.plain,
        followRedirects: true,
        validateStatus: (status) => status != null && status < 400,
      ),
    );

    final body = response.data ?? '';
    final success =
        body.contains('登录成功') || body.contains('succeedhandle_loginform');
    if (!success) {
      return LoginResult(
        success: false,
        message: _extractMessage(body) ?? '登录失败',
      );
    }

    // 真实探测确认 auth 由登录 POST 下发，而 saltkey 通常只在前面的
    // GET 登录页下发。两处都做响应头兜底回填，这样即使 CookieManager
    // 极低概率漏收某个 Set-Cookie，也不会出现“服务器已登录成功、App 却
    // 因 Jar 少一个 Cookie 判失败”的假失败。
    await _backfillSessionCookieFromResponse(
      response,
      'cQWy_2132_auth',
    );
    await _backfillSessionCookieFromResponse(
      response,
      'cQWy_2132_saltkey',
    );

    // CookieManager 已经处理了所有 Set-Cookie/重定向 Cookie；上面的
    // 回填只负责补足漏收的真实 Set-Cookie。最终仍统一从 CookieJar
    // 读取并保持 auth + saltkey 的原登录态约束。
    // 必须从 CookieJar 读取最终值，而不是只看最终响应头。
    final cookies = await _cookieJar.loadForRequest(Uri.parse(ApiService.baseUrl));
    String? auth;
    String? saltkey;
    for (final cookie in cookies) {
      if (cookie.name == 'cQWy_2132_auth') auth = cookie.value;
      if (cookie.name == 'cQWy_2132_saltkey') saltkey = cookie.value;
    }

    if (auth == null || auth.isEmpty || saltkey == null || saltkey.isEmpty) {
      await _cookieJar.deleteAll();
      return const LoginResult(
        success: false,
        message: '登录成功但未取得论坛会话 Cookie',
      );
    }

    // auth 原样保存，禁止 Uri.decodeComponent，避免破坏 Discuz Cookie。
    await _persistSession(auth, saltkey);

    // 登录页产生的游客 formhash 与新的 auth 会话不是同一凭证。
    // 清掉它，但绝不能清掉已经验证成功的 auth/saltkey。
    await _clearCachedFormhash();

    _notifyLoginChanged();

    // formhash 是后续写操作凭证，不是“登录是否成功”的判据。
    // 后台预热即可，失败时由具体写操作再通过 getFormhash() 补取。
    unawaited(_primeFormhashAfterLogin());

    return const LoginResult(
      success: true,
      message: '登录成功',
    );
  }
  Future<void> logout() async {
    if (isLoggedIn) {
      try {
        final hash = await getFormhash();
        await _dio.get<String>(
          '/member.php',
          queryParameters: {
            'mod': 'logging',
            'action': 'logout',
            'formhash': hash,
            'mobile': 2,
          },
          options: Options(
            responseType: ResponseType.plain,
            followRedirects: true,
          ),
        );
      } catch (_) {
        // 即使远端退出请求失败，也必须清理本地登录状态。
      }
    }

    await clearCredentials();
  }
  /// 保留给旧调用方的兼容入口，不再在 UI 暴露 Cookie 登录。
  Future<void> saveCredentials(String auth, String saltkey) async {
    await _cookieJar.deleteAll();
    _currentUid = null;
    await _persistSession(auth, saltkey);
    await _restoreSessionCookies();
    await _clearCachedFormhash();
    _notifyLoginChanged();
    unawaited(_primeFormhashAfterLogin());
  }
  Future<void> clearCredentials() async {
    _auth = null;
    _saltkey = null;
    _currentUid = null;
    await _clearCachedFormhash();

    await _prefs.remove('forum_auth');
    await _prefs.remove('forum_saltkey');
    await _prefs.remove('auth');
    await _prefs.remove('saltkey');
    await _cookieJar.deleteAll();
    _notifyLoginChanged();
  }
  Future<void> _persistSession(String auth, String saltkey) async {
    _auth = auth;
    _saltkey = saltkey;

    await _prefs.setString('forum_auth', auth);
    await _prefs.setString('forum_saltkey', saltkey);
    // 清理旧 key，防止两套状态互相覆盖。
    await _prefs.remove('auth');
    await _prefs.remove('saltkey');
  }
  Future<void> _restoreSessionCookies() async {
    // 只恢复核心登录 Cookie。防护 Cookie 由 ForumCookieManager 独立管理，
    // 绝不混进账号登录态（否则切账号/重启会把过期防护值反复"复活"）。
    await _cookieManager.restoreCoreCookies(auth: _auth, saltkey: _saltkey);
  }
  String? _extractMessage(String body) {
    final document = html_parser.parse(body);
    final paragraph = document.querySelector('p')?.text.trim();
    if (paragraph != null && paragraph.isNotEmpty) return paragraph;
    final text = document.body?.text.trim();
    return text?.isNotEmpty == true ? text : null;
  }
  String _extractAjaxMessage(String raw) {
    if (raw.trim().isEmpty) return '';

    var source = raw;
    final cdata = RegExp(
      r'<!\[CDATA\[(.*?)\]\]>',
      dotAll: true,
      caseSensitive: false,
    ).firstMatch(source);
    if (cdata != null) {
      source = cdata.group(1) ?? source;
    }

    final document = html_parser.parseFragment(source);
    for (final node in document.querySelectorAll('script, style')) {
      node.remove();
    }

    final preferred = document.querySelector(
      '#messagetext p, #messagetext, p',
    );
    var text = (preferred?.text ?? document.text ?? '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (text.isEmpty && !source.contains('<')) {
      text = source.trim();
    }

    return text;
  }
}
