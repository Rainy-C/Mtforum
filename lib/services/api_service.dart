import 'dart:async';
import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/forum_parser.dart';
import '../data/account_parser.dart';
import '../data/sign_parser.dart';
import '../data/portal_parser.dart';
import '../data/user_center_parser.dart';
import '../models/models.dart';

/// MT 论坛网络门面。
///
/// 网络请求与 HTML 解析已经分离：
/// - ApiService：请求、Cookie、登录态、写操作。
/// - ForumParser：只负责把服务器响应解析成模型。
class ApiService {
  static const String baseUrl = 'https://bbs.binmt.cc';

  ApiService._();
  static final ApiService instance = ApiService._();

  final ForumParser _parser = const ForumParser();
  final AccountParser _accountParser = const AccountParser();
  final SignParser _signParser = const SignParser();
  final PortalParser _portalParser = const PortalParser();
  final UserCenterParser _userCenterParser = const UserCenterParser();
  final List<void Function()> _loginListeners = [];

  late final Dio _dio;
  late final CookieJar _cookieJar;
  late final SharedPreferences _prefs;

  bool _initialized = false;
  String? _auth;
  String? _saltkey;
  String? _formhash;
  String? _formhashAuth;
  String? _currentUid;
  Future<String>? _formhashRefreshFuture;
  int _sessionGeneration = 0;

  bool get isLoggedIn =>
      (_auth?.isNotEmpty ?? false) && (_saltkey?.isNotEmpty ?? false);
  String? get auth => _auth;
  String? get saltkey => _saltkey;
  String? get formhash => _formhash;
  String? get currentUid => _currentUid;

  void addLoginListener(void Function() listener) {
    if (!_loginListeners.contains(listener)) _loginListeners.add(listener);
  }

  void removeLoginListener(void Function() listener) {
    _loginListeners.remove(listener);
  }

  void _notifyLoginChanged() {
    for (final listener in List<void Function()>.from(_loginListeners)) {
      try {
        listener();
      } catch (_) {}
    }
  }

  Future<void> init() async {
    if (_initialized) {
      return;
    }

    _cookieJar = CookieJar();
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 25),
        sendTimeout: const Duration(seconds: 20),
        headers: const {
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 16) AppleWebKit/537.36 '
                  '(KHTML, like Gecko) Chrome/150.0.0.0 Mobile Safari/537.36',
          'Accept-Language': 'zh-CN,zh;q=0.9',
          'Accept-Encoding': 'gzip',
        },
      ),
    );
    _dio.interceptors.add(CookieManager(_cookieJar));

    // 所有 HTML/AJAX 响应只要带 formhash，就自动收入缓存。
    // 这样浏览帖子、签到页、社区等页面后，写操作无需再次专门请求。
    _dio.interceptors.add(
      InterceptorsWrapper(
        onResponse: (response, handler) {
          final data = response.data;
          if (data is String && data.isNotEmpty) {
            final hash = _extractFormhash(data);
            if (hash != null && hash.isNotEmpty) {
              _rememberFormhash(hash);
            }
            if (isLoggedIn) {
              final uid = RegExp(
                r'''discuz_uid\s*=\s*['"]?(\d+)''',
                caseSensitive: false,
              ).firstMatch(data)?.group(1);
              if (uid != null && uid != '0') _currentUid = uid;
            }
          }
          handler.next(response);
        },
      ),
    );

    _prefs = await SharedPreferences.getInstance();

    _auth = _prefs.getString('forum_auth');
    _saltkey = _prefs.getString('forum_saltkey');

    _auth ??= _prefs.getString('auth');
    _saltkey ??= _prefs.getString('saltkey');

    if (isLoggedIn) {
      await _restoreSessionCookies();

      // formhash 与当前 auth 绑定。匹配当前账号时直接恢复，
      // App 启动不再为了 formhash 阻塞 1~3 次网络请求。
      final cachedHash = _prefs.getString('forum_formhash');
      final cachedAuth = _prefs.getString('forum_formhash_auth');
      if (cachedHash != null &&
          cachedHash.isNotEmpty &&
          cachedAuth == _auth) {
        _formhash = cachedHash;
        _formhashAuth = _auth;
      }
    }

    _initialized = true;
  }

  Future<void> _restoreSessionCookies() async {
    final cookies = <Cookie>[];
    if (_auth?.isNotEmpty ?? false) {
      cookies.add(Cookie('cQWy_2132_auth', _auth!));
    }
    if (_saltkey?.isNotEmpty ?? false) {
      cookies.add(Cookie('cQWy_2132_saltkey', _saltkey!));
    }
    if (cookies.isNotEmpty) {
      await _cookieJar.saveFromResponse(Uri.parse(baseUrl), cookies);
    }
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

    await _prefs.remove('forum_formhash');
    await _prefs.remove('forum_formhash_auth');
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

  Future<List<Thread>> getThreadList({
    int page = 1,
    String view = 'hot',
  }) async {
    const supportedViews = {'hot', 'newthread', 'digest', 'sofa'};
    final normalizedView = supportedViews.contains(view) ? view : 'hot';

    final response = await _dio.get<String>(
      '/forum.php',
      queryParameters: {
        'mod': 'guide',
        'view': normalizedView,
        'index': 1,
        'page': page,
        'mobile': 2,
      },
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );

    return _parser.parseThreadList(
      response.data ?? '',
      baseUrl: baseUrl,
    );
  }

  Future<ThreadDetail> getThreadDetail(String tid, {int page = 1}) async {
    final response = await _dio.get<String>(
      '/thread-$tid-$page-1.html',
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
        // Discuz 对已删除/不存在/审核中的主题会直接返回 404，并在响应体中
        // 给出可读提示。这里允许 4xx 返回给业务层处理，避免 Dio 先抛出
        // 一整段 bad response 异常给 UI。
        validateStatus: (status) => status != null && status < 500,
      ),
    );

    final body = response.data ?? '';
    final status = response.statusCode ?? 0;
    final missingThread = status == 404 ||
        body.contains('指定的主题不存在或已被删除或正在被审核') ||
        body.contains('指定的主题不存在') ||
        body.contains('主题不存在或已被删除');

    if (missingThread) {
      throw StateError('帖子不存在、已被删除或正在审核');
    }
    if (status == 401 || status == 403) {
      throw StateError('当前账号无权查看此帖子，请检查登录状态或帖子权限');
    }
    if (status >= 400) {
      throw StateError('帖子加载失败（HTTP $status）');
    }

    final detail = _parser.parseThreadDetail(
      body,
      tid: tid,
      page: page,
      baseUrl: baseUrl,
    );

    if (detail.formhash.isNotEmpty) {
      _rememberFormhash(detail.formhash);
    }
    return detail;
  }

  Future<PostEditorForm> getNewThreadForm(String fid) async {
    if (!isLoggedIn) {
      throw StateError('请先登录');
    }

    Future<String> request({bool mobileFallback = false}) async {
      final response = await _dio.get<String>(
        '/forum.php',
        queryParameters: {
          'mod': 'post',
          'action': 'newthread',
          'fid': fid,
          if (mobileFallback) 'mobile': 2,
        },
        options: Options(
          headers: {
            'Referer': '$baseUrl/forum-$fid-1.html',
            if (mobileFallback) 'Cache-Control': 'no-cache',
          },
          responseType: ResponseType.plain,
          followRedirects: true,
        ),
      );
      return response.data ?? '';
    }

    var body = await request();
    var form = _parser.parsePostEditorForm(body, fallbackFid: fid);

    // 个别移动端响应会先返回“数据加载中”壳页，或者首屏表单虽完整但
    // 没输出附件上传的 uploadformdata。缺任一关键字段时用 mobile=2 再取一次。
    if (form.formhash.isEmpty || form.posttime.isEmpty || !form.canUploadImages) {
      final retryBody = await request(mobileFallback: true);
      final retryForm = _parser.parsePostEditorForm(
        retryBody,
        fallbackFid: fid,
      );
      final retryHasBaseForm =
          retryForm.formhash.isNotEmpty && retryForm.posttime.isNotEmpty;
      final shouldUseRetry = retryHasBaseForm &&
          ((form.formhash.isEmpty || form.posttime.isEmpty) ||
              (!form.canUploadImages && retryForm.canUploadImages));
      if (shouldUseRetry) {
        body = retryBody;
        form = retryForm;
      }
    }

    if (form.formhash.isEmpty || form.posttime.isEmpty) {
      final message = _extractAjaxMessage(body);
      final readable = message == '数据加载中' ? '' : message;
      throw StateError(readable.isEmpty ? '未获取到发帖表单，请重试' : readable);
    }
    _rememberFormhash(form.formhash);
    return form;
  }

  Future<PostAttachmentUploadResult> uploadPostImage({
    required PostEditorForm form,
    required List<int> bytes,
    required String fileName,
  }) async {
    if (!isLoggedIn) {
      return const PostAttachmentUploadResult(
        success: false,
        message: '请先登录',
      );
    }
    if (!form.canUploadImages) {
      return const PostAttachmentUploadResult(
        success: false,
        message: '当前发帖页未提供附件上传凭证，请重新打开编辑器',
      );
    }
    if (bytes.isEmpty) {
      return const PostAttachmentUploadResult(
        success: false,
        message: '图片文件为空',
      );
    }
    if (bytes.length > form.maxUploadSizeKb * 1024) {
      return PostAttachmentUploadResult(
        success: false,
        message: '图片超过 ${form.maxUploadSizeKb}KB 限制',
      );
    }

    final response = await _dio.post<String>(
      '/misc.php',
      queryParameters: const {
        'mod': 'swfupload',
        'operation': 'upload',
        'type': 'image',
        'inajax': 'yes',
        'infloat': 'yes',
        'simple': 2,
      },
      data: FormData.fromMap({
        'Filedata': MultipartFile.fromBytes(bytes, filename: fileName),
        'uid': form.uploadUid,
        'hash': form.uploadHash,
      }),
      options: Options(
        headers: {
          'X-Requested-With': 'XMLHttpRequest',
          'Referer': _postEditorReferer(form),
        },
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );

    return _parser.parsePostAttachmentUploadResponse(response.data ?? '');
  }

  Future<bool> deletePostAttachment({
    required PostEditorForm form,
    required String aid,
  }) async {
    if (!isLoggedIn || aid.trim().isEmpty) return false;

    final hash = form.formhash.isNotEmpty ? form.formhash : await getFormhash();
    final response = await _dio.get<String>(
      '/forum.php',
      queryParameters: {
        'mod': 'ajax',
        'action': 'deleteattach',
        'inajax': 'yes',
        'formhash': hash,
        'aids[]': aid.trim(),
      },
      options: Options(
        headers: {
          'X-Requested-With': 'XMLHttpRequest',
          'Referer': _postEditorReferer(form),
        },
        responseType: ResponseType.plain,
        followRedirects: true,
        validateStatus: (status) => status != null && status < 400,
      ),
    );

    final body = response.data ?? '';
    final message = _extractAjaxMessage(body);
    final lower = message.toLowerCase();
    final explicitFailure = message.contains('无权') ||
        message.contains('失败') ||
        message.contains('不存在') ||
        message.contains('错误') ||
        lower.contains('error');
    return !explicitFailure;
  }

  String _postEditorReferer(PostEditorForm form) {
    if (form.tid.isNotEmpty && form.pid.isNotEmpty) {
      return '$baseUrl/forum.php?mod=post&action=edit'
          '&fid=${form.fid}&tid=${form.tid}&pid=${form.pid}&page=${form.page}';
    }
    return '$baseUrl/forum.php?mod=post&action=newthread&fid=${form.fid}';
  }

  Future<ThreadSubmitResult> submitNewThread({
    required PostEditorForm form,
    required String subject,
    required String message,
    bool? allowNoticeAuthor,
    bool? useSig,
  }) async {
    if (!isLoggedIn) {
      return const ThreadSubmitResult(success: false, message: '请先登录');
    }

    final title = subject.trim();
    final content = message.trim();
    if (title.isEmpty) {
      return const ThreadSubmitResult(success: false, message: '请输入帖子标题');
    }
    if (content.isEmpty) {
      return const ThreadSubmitResult(success: false, message: '请输入帖子正文');
    }

    final response = await _dio.post<String>(
      '/forum.php',
      queryParameters: {
        'mod': 'post',
        'action': 'newthread',
        'fid': form.fid,
        'extra': '',
        'topicsubmit': 'yes',
        'mobile': 2,
        'handlekey': 'postform',
        'inajax': 1,
      },
      data: {
        'formhash': form.formhash,
        'posttime': form.posttime,
        'delete': form.deleteValue,
        'topicsubmit': 'yes',
        'subject': title,
        'message': content,
        if (allowNoticeAuthor ?? (form.allowNoticeAuthor != '0'))
          'allownoticeauthor': '1',
        if (useSig ?? (form.useSig != '0')) 'usesig': '1',
        'save': '',
      },
      options: Options(
        contentType: 'application/x-www-form-urlencoded; charset=UTF-8',
        headers: {
          'X-Requested-With': 'XMLHttpRequest',
          'Referer':
              '$baseUrl/forum.php?mod=post&action=newthread&fid=${form.fid}',
        },
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );

    final body = response.data ?? '';
    final success = body.contains('主题已发布');
    final tid = RegExp(r'''thread-(\d+)-''').firstMatch(body)?.group(1) ??
        RegExp(r'''['"]tid['"]\s*:\s*['"](\d+)['"]''')
            .firstMatch(body)
            ?.group(1);
    final pid = RegExp(r'''['"]pid['"]\s*:\s*['"](\d+)['"]''')
        .firstMatch(body)
        ?.group(1);
    final fid = RegExp(r'''['"]fid['"]\s*:\s*['"](\d+)['"]''')
            .firstMatch(body)
            ?.group(1) ??
        form.fid;

    if (success) {
      return ThreadSubmitResult(
        success: true,
        message: '主题发布成功',
        tid: tid,
        pid: pid,
        fid: fid,
      );
    }

    final readable = _extractAjaxMessage(body);
    return ThreadSubmitResult(
      success: false,
      message: readable.isEmpty ? '发帖失败' : readable,
    );
  }

  Future<PostEditorForm> getEditPostForm({
    required String fid,
    required String tid,
    required String pid,
    required int page,
  }) async {
    if (!isLoggedIn) {
      throw StateError('请先登录');
    }

    final viewReferer =
        '$baseUrl/forum.php?mod=viewthread&tid=$tid&page=$page&mobile=2';

    PostEditorForm parseForm(String body) {
      return _parser.parsePostEditorForm(
        body,
        fallbackFid: fid,
        fallbackTid: tid,
        fallbackPid: pid,
        fallbackPage: page,
      );
    }

    bool hasRealEditor(String body, PostEditorForm form) {
      if (form.formhash.isEmpty || form.posttime.isEmpty) return false;

      // 编辑帖子必须存在正文 textarea。旧逻辑只检查 formhash/posttime，
      // 因此服务器若因为 fid/page 等定位不准确返回了一个通用表单壳，App 仍会
      // 当成“编辑表单成功”，最终给用户一个空编辑器。
      final document = html_parser.parse(body);
      final textarea = document.querySelector('textarea[name="message"]');
      return textarea != null && form.message.trim().isNotEmpty;
    }

    Future<String> requestEdit(
      String path, {
      Map<String, dynamic>? queryParameters,
      String? referer,
    }) async {
      final response = await _dio.get<String>(
        path,
        queryParameters: queryParameters,
        options: Options(
          headers: {
            'Referer': referer ?? viewReferer,
            'Cache-Control': 'no-cache',
          },
          responseType: ResponseType.plain,
          followRedirects: true,
          validateStatus: (status) => status != null && status < 400,
        ),
      );
      return response.data ?? '';
    }

    var body = await requestEdit(
      '/forum.php',
      queryParameters: {
        'mod': 'post',
        'action': 'edit',
        'fid': fid,
        'tid': tid,
        'pid': pid,
        'page': page,
        'mobile': 2,
      },
    );
    var form = parseForm(body);

    if (!hasRealEditor(body, form)) {
      // 不猜 fid/page。直接回到真实帖子页面，寻找服务器自己输出的该 PID
      // 编辑链接，再按这个 URL 重试。这样即使客户端楼层页码或 fid 过期，
      // 也以 Discuz 当前页面给出的真实定位为准。
      try {
        final threadBody = await requestEdit(
          '/forum.php',
          queryParameters: {
            'mod': 'viewthread',
            'tid': tid,
            'page': page,
            'mobile': 2,
          },
          referer: '$baseUrl/thread-$tid-$page-1.html',
        );
        final document = html_parser.parse(threadBody);
        Uri? actualEditUri;

        for (final anchor in document.querySelectorAll(
          'a[href*="action=edit"]',
        )) {
          final rawHref = (anchor.attributes['href'] ?? '')
              .replaceAll('&amp;', '&')
              .trim();
          if (rawHref.isEmpty) continue;

          final resolved = Uri.parse(baseUrl).resolve(rawHref);
          if (resolved.queryParameters['pid'] == pid) {
            actualEditUri = resolved;
            break;
          }
        }

        if (actualEditUri != null) {
          final actualBody = await requestEdit(
            actualEditUri.toString(),
            referer: viewReferer,
          );
          final actualForm = parseForm(actualBody);
          if (hasRealEditor(actualBody, actualForm)) {
            body = actualBody;
            form = actualForm;
          }
        }
      } catch (_) {
        // 继续使用下面的不带 mobile 参数兜底，不把辅助定位失败直接暴露给 UI。
      }
    }

    if (!hasRealEditor(body, form)) {
      // 实测带/不带 mobile=2 的编辑页都可能正常返回。最后再用桌面/自动模板
      // 请求一次，兼容某些旧帖在移动模板下只返回表单壳的情况。
      try {
        final fallbackBody = await requestEdit(
          '/forum.php',
          queryParameters: {
            'mod': 'post',
            'action': 'edit',
            'fid': fid,
            'tid': tid,
            'pid': pid,
            'page': page,
          },
        );
        final fallbackForm = parseForm(fallbackBody);
        if (hasRealEditor(fallbackBody, fallbackForm)) {
          body = fallbackBody;
          form = fallbackForm;
        }
      } catch (_) {}
    }

    if (!hasRealEditor(body, form)) {
      final message = _extractAjaxMessage(body);
      if (message.isNotEmpty) {
        throw StateError(message);
      }
      if (form.formhash.isNotEmpty && form.posttime.isNotEmpty) {
        throw StateError('编辑页未返回原帖正文（tid=$tid pid=$pid page=$page fid=$fid）');
      }
      throw StateError('未获取到编辑表单');
    }

    _rememberFormhash(form.formhash);
    return form;
  }

  Future<ThreadSubmitResult> submitEditPost({
    required PostEditorForm form,
    required String subject,
    required String message,
    bool? allowNoticeAuthor,
    bool? useSig,
  }) async {
    if (!isLoggedIn) {
      return const ThreadSubmitResult(success: false, message: '请先登录');
    }

    final content = message.trim();
    if (content.isEmpty) {
      return const ThreadSubmitResult(success: false, message: '帖子正文不能为空');
    }

    final response = await _dio.post<String>(
      '/forum.php',
      queryParameters: const {
        'mod': 'post',
        'action': 'edit',
        'extra': '',
        'editsubmit': 'yes',
        'mobile': 2,
        'handlekey': 'postform',
        'inajax': 1,
      },
      data: {
        'formhash': form.formhash,
        'posttime': form.posttime,
        'delete': form.deleteValue,
        'fid': form.fid,
        'tid': form.tid,
        'pid': form.pid,
        'page': form.page,
        'editsubmit': 'yes',
        'subject': subject.trim(),
        'message': content,
        if (allowNoticeAuthor ?? (form.allowNoticeAuthor != '0'))
          'allownoticeauthor': '1',
        if (useSig ?? (form.useSig != '0')) 'usesig': '1',
        'save': '',
      },
      options: Options(
        contentType: 'application/x-www-form-urlencoded; charset=UTF-8',
        headers: {
          'X-Requested-With': 'XMLHttpRequest',
          'Referer': '$baseUrl/forum.php?mod=post&action=edit'
              '&fid=${form.fid}&tid=${form.tid}&pid=${form.pid}&page=${form.page}',
        },
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );

    final body = response.data ?? '';
    final success = body.contains('帖子编辑成功');
    if (success) {
      return ThreadSubmitResult(
        success: true,
        message: '帖子编辑成功',
        tid: form.tid,
        pid: form.pid,
        fid: form.fid,
      );
    }

    final readable = _extractAjaxMessage(body);
    return ThreadSubmitResult(
      success: false,
      message: readable.isEmpty ? '编辑失败' : readable,
      tid: form.tid,
      pid: form.pid,
      fid: form.fid,
    );
  }

  Future<ReplyResult> replyThread({
    required String tid,
    required String fid,
    required String noticeauthor,
    required String message,
    String? repquotePid,
  }) async {
    if (!isLoggedIn) {
      return const ReplyResult(success: false, message: '请先登录');
    }

    // Discuz 的“回复指定楼层”不是简单在最终 POST 上带 repquote。
    // 正确流程是先 GET action=reply&repquote=目标PID，让服务端生成
    // noticeauthor / noticetrimstr / noticeauthormsg / reppid / reppost 等
    // 隐藏字段，再把这些字段随表单一起 POST。跳过这一步时，服务端会把
    // 回复保存成普通回帖，客户端刷新后自然无法判断“回复了谁”。
    final data = <String, dynamic>{
      'formhash': await getFormhash(),
      'noticeauthor': noticeauthor,
      'message': message,
    };

    var postQuery = <String, dynamic>{
      'mod': 'post',
      'action': 'reply',
      'fid': fid,
      'tid': tid,
      'extra': 'page=1',
      'replysubmit': 'yes',
      'mobile': 2,
      'handlekey': 'fastpost',
      'loc': 1,
      'inajax': 1,
    };

    if (repquotePid != null && repquotePid.trim().isNotEmpty) {
      final targetPid = repquotePid.trim();
      final formResponse = await _dio.get<String>(
        '/forum.php',
        queryParameters: {
          'mod': 'post',
          'action': 'reply',
          'fid': fid,
          'tid': tid,
          'repquote': targetPid,
          'extra': 'page=1',
          'page': 1,
          'mobile': 2,
        },
        options: Options(
          headers: {
            'Referer': '$baseUrl/thread-$tid-1-1.html',
          },
          responseType: ResponseType.plain,
          followRedirects: true,
        ),
      );

      final formBody = formResponse.data ?? '';
      final document = html_parser.parse(formBody);
      final form = document.querySelector(
        'form#postform, form[action*="mod=post"][action*="action=reply"]',
      );
      if (form == null) {
        final readable = _extractAjaxMessage(formBody);
        return ReplyResult(
          success: false,
          message: readable.isEmpty
              ? '未获取到指定楼层的回复表单，请刷新帖子后重试'
              : readable,
        );
      }

      for (final input in form.querySelectorAll('input[name]')) {
        final name = input.attributes['name']?.trim() ?? '';
        if (name.isEmpty) continue;
        final type = (input.attributes['type'] ?? '').toLowerCase();
        if (type == 'submit' || type == 'button' || type == 'file') continue;
        data[name] = input.attributes['value'] ?? '';
      }
      data['message'] = message;
      data['replysubmit'] = 'yes';

      final action = (form.attributes['action'] ?? '')
          .replaceAll('&amp;', '&')
          .trim();
      if (action.isNotEmpty) {
        final uri = Uri.parse(baseUrl).resolve(action);
        postQuery = Map<String, dynamic>.from(uri.queryParameters);
        // 保持客户端 AJAX 提交方式，只改变 Discuz 表单要求的真实字段。
        postQuery.putIfAbsent('inajax', () => 1);
        postQuery.putIfAbsent('handlekey', () => 'fastpost');
      }
    }

    final response = await _dio.post<String>(
      '/forum.php',
      queryParameters: postQuery,
      data: data,
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: {
          'X-Requested-With': 'XMLHttpRequest',
          'Referer': '$baseUrl/thread-$tid-1-1.html',
        },
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );

    final body = response.data ?? '';
    final success = body.contains('成功') || body.contains('succeedhandle');
    final newPid = RegExp(r'pid=(\d+)').firstMatch(body)?.group(1);

    if (success) {
      return ReplyResult(success: true, newPid: newPid, message: '回复成功');
    }

    return ReplyResult(
      success: false,
      message: _extractMessage(body) ?? '回复失败',
    );
  }

  Future<List<SearchResult>> search(String keyword, {int page = 1}) async {
    final hash = await getFormhash();

    final start = await _dio.post<String>(
      '/search.php',
      queryParameters: const {'mod': 'forum'},
      data: {
        'formhash': hash,
        'searchsubmit': 'yes',
        'mod': 'forum',
        'srchtxt': keyword,
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        responseType: ResponseType.plain,
        followRedirects: false,
        validateStatus: (status) => status != null && status < 400,
      ),
    );

    final location = start.headers.value('location') ?? '';
    var searchId = RegExp(r'searchid=(\d+)').firstMatch(location)?.group(1);
    searchId ??=
        RegExp(r'searchid=(\d+)').firstMatch(start.data ?? '')?.group(1);
    if (searchId == null) return const [];

    final response = await _dio.get<String>(
      '/search.php',
      queryParameters: {
        'mod': 'forum',
        'searchid': searchId,
        'orderby': 'lastpost',
        'ascdesc': 'desc',
        'searchsubmit': 'yes',
        'kw': keyword,
        'page': page,
        'mobile': 2,
      },
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );

    final threads = _parser.parseThreadList(
      response.data ?? '',
      baseUrl: baseUrl,
    );
    return threads
        .map((thread) => SearchResult(
              tid: thread.tid,
              title: thread.title,
              authorUid: thread.authorUid,
              authorName: thread.authorName,
              avatarUrl: thread.avatarUrl,
              forumName: thread.forumName,
              postTime: thread.lastReplyTime,
              excerpt: thread.excerpt,
              replyCount: thread.replyCount,
              viewCount: thread.viewCount,
              thumbnails: thread.thumbnails,
              hasHiddenContent: thread.hasHiddenContent,
            ))
        .toList();
  }

  Future<UserProfile> getProfile() async {
    final response = await _dio.get<String>(
      '/home.php',
      queryParameters: const {'mod': 'space', 'do': 'profile', 'mobile': 2},
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );

    final body = response.data ?? '';
    final document = html_parser.parse(body);
    final uid = RegExp(r"discuz_uid\s*=\s*'?(\d+)")
            .firstMatch(body)
            ?.group(1) ??
        _currentUid ??
        '0';
    if (uid != '0') _currentUid = uid;

    // 先沿用旧链路读取当前页上一直稳定的基础字段，避免模板差异导致回归。
    var fallbackUsername =
        document.querySelector('.comiis_uinfo_a, .vh')?.text.trim();
    fallbackUsername ??= document.querySelector('h2')?.text.trim();
    final fallbackAvatar = _absoluteUrl(
      document.querySelector('img[src*="avatar"]')?.attributes['src'],
    );

    int? fallbackCredits;
    int? fallbackGold;
    final matches = RegExp(r'<em[^>]*>(\d+)</em>\s*<p[^>]*>([^<]+)')
        .allMatches(body);
    for (final match in matches) {
      final value = int.tryParse(match.group(1) ?? '');
      final label = match.group(2)?.trim() ?? '';
      if (value == null) continue;
      if (label.contains('积分')) fallbackCredits = value;
      if (label.contains('金币')) fallbackGold = value;
    }

    // “我的”与用户主页共享同一套真实 DOM 统计解析。之前这里只解析基础字段，
    // 导致帖子、回复、好友一直为 null，UI 再把 null 错误显示成了 0。
    var parsed = _userCenterParser.parseCurrentProfile(
      body,
      uid: uid,
      baseUrl: baseUrl,
    );

    // 某些 Comiis 模板在“不带 uid 的自己的资料页”会省略统计栏。只在三个
    // 核心统计都缺失时，再请求一次明确 uid 的真实用户主页，避免每次多打一请求。
    if (uid != '0' &&
        parsed.threads == null &&
        parsed.posts == null &&
        parsed.friends == null) {
      try {
        final statsResponse = await _dio.get<String>(
          '/home.php',
          queryParameters: {
            'mod': 'space',
            'uid': uid,
            'do': 'profile',
            'mobile': 2,
          },
          options: Options(
            responseType: ResponseType.plain,
            followRedirects: true,
          ),
        );
        parsed = _userCenterParser.parseCurrentProfile(
          statsResponse.data ?? '',
          uid: uid,
          baseUrl: baseUrl,
        );
      } catch (_) {
        // 统计补充失败不影响“我的”基础资料；UI 用“—”表示未知，而不是伪造 0。
      }
    }

    final parsedUsername = parsed.username?.trim() ?? "";
    final parsedUsernameUsable = parsedUsername.isNotEmpty &&
        parsedUsername != 'UID $uid' &&
        parsedUsername != '未知用户';

    return UserProfile(
      uid: uid,
      username: parsedUsernameUsable
          ? parsedUsername
          : (fallbackUsername?.isNotEmpty == true
              ? fallbackUsername
              : '未知用户'),
      avatarUrl: parsed.avatarUrl ?? fallbackAvatar,
      userGroup: parsed.userGroup,
      credits: parsed.credits ?? fallbackCredits,
      gold: parsed.gold ?? fallbackGold,
      contribution: parsed.contribution,
      threads: parsed.threads,
      posts: parsed.posts,
      friends: parsed.friends,
      regDate: parsed.regDate,
      lastVisit: parsed.lastVisit,
    );
  }

  Future<bool> recommend(String tid, {bool cancel = false}) async {
    if (!isLoggedIn) return false;
    final hash = await getFormhash();
    try {
      final response = await _dio.get<String>(
        '/forum.php',
        queryParameters: {
          'mod': 'misc',
          'action': 'recommend',
          'handlekey': 'recommend_add',
          'do': cancel ? 'sub' : 'add',
          'tid': tid,
          'hash': hash,
        },
        options: Options(
          headers: {'Referer': '$baseUrl/thread-$tid-1-1.html'},
          responseType: ResponseType.plain,
          followRedirects: true,
        ),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// 收藏接口不是 Check.md 的主链内容，保留旧能力但独立封装，失败直接返回 false。
  Future<bool> favorite(String tid, {bool cancel = false}) async {
    if (!isLoggedIn) return false;
    final hash = await getFormhash();
    try {
      final query = <String, dynamic>{
        'mod': 'spacecp',
        'ac': 'favorite',
        'type': 'thread',
        'id': tid,
        'formhash': hash,
        'mobile': 2,
      };
      if (cancel) {
        query['op'] = 'delete';
        query['favid'] = '';
      }
      final response = await _dio.get<String>(
        '/home.php',
        queryParameters: query,
        options: Options(
          headers: {
            'X-Requested-With': 'XMLHttpRequest',
            'Referer': '$baseUrl/thread-$tid-1-1.html',
          },
          responseType: ResponseType.plain,
          followRedirects: true,
        ),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// 读取签到页当前状态，同时顺便刷新页面里可能存在的 formhash。
  Future<bool> isSignedToday() async {
    if (!isLoggedIn) {
      return false;
    }

    try {
      final response = await _dio.get<String>(
        '/k_misign-sign.html',
        options: Options(
          headers: {
            'Referer':
                '$baseUrl/home.php?mod=space&do=profile&mycenter=1',
          },
          responseType: ResponseType.plain,
          followRedirects: true,
          validateStatus: (status) => status != null && status < 400,
        ),
      );

      final body = response.data ?? '';
      final hash = _extractFormhash(body);
      if (hash != null && hash.isNotEmpty) {
        _rememberFormhash(hash);
      }

      final text = html_parser.parse(body).body?.text ?? '';
      final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();

      if (normalized.contains('今日已签到') ||
          normalized.contains('已签到')) {
        return true;
      }

      if (normalized.contains('尚未签到') ||
          normalized.contains('还未签到') ||
          normalized.contains('立即签到')) {
        return false;
      }

      return false;
    } catch (_) {
      return false;
    }
  }

  /// 获取签到使用的 formhash。
  ///
  /// 已登录状态下优先复用当前有效 formhash。k_misign 的签到页在“当天已签到”
  /// 等状态下不一定继续输出 formhash，因此不能把签到页作为唯一来源。
  Future<String> getSignFormhash() async {
    if (!isLoggedIn) {
      throw StateError('请先登录');
    }

    final current = _formhash;
    if (current != null && current.isNotEmpty) {
      return current;
    }

    try {
      final response = await _dio.get<String>(
        '/k_misign-sign.html',
        options: Options(
          headers: {
            'Referer':
                '$baseUrl/home.php?mod=space&do=profile&mycenter=1',
          },
          responseType: ResponseType.plain,
          followRedirects: true,
          validateStatus: (status) => status != null && status < 400,
        ),
      );

      final hash = _extractFormhash(response.data ?? '');
      if (hash != null && hash.isNotEmpty) {
        _rememberFormhash(hash);
        return hash;
      }
    } catch (_) {
      // 继续使用通用页面兜底。
    }

    return refreshFormhash();
  }

  Future<SignResult> signIn() async {
    if (!isLoggedIn) {
      return const SignResult(
        success: false,
        message: '请先登录',
      );
    }

    try {
      final hash = await getSignFormhash();
      var result = await _requestSign(hash);

      // 如果服务器明确提示凭证失效，刷新 formhash 后只重试一次。
      if (!result.success &&
          (result.message.contains('formhash') ||
              result.message.contains('非法') ||
              result.message.contains('请求错误'))) {
        _formhash = null;
        final freshHash = await refreshFormhash();
        result = await _requestSign(freshHash);
      }

      return result;
    } catch (e) {
      return SignResult(
        success: false,
        message: '签到失败：$e',
      );
    }
  }

  Future<SignResult> _requestSign(String hash) async {
    final response = await _dio.get<String>(
      '/plugin.php',
      queryParameters: {
        'id': 'k_misign:sign',
        'operation': 'qiandao',
        'format': 'text',
        'formhash': hash,
      },
      options: Options(
        headers: {
          'X-Requested-With': 'XMLHttpRequest',
          'Referer': '$baseUrl/k_misign-sign.html',
        },
        responseType: ResponseType.plain,
        followRedirects: true,
        validateStatus: (status) => status != null && status < 400,
      ),
    );

    return _signParser.parseSignResponse(response.data ?? '');
  }

  Future<List<SignRecord>> getSignRank(
    String type, {
    int page = 1,
  }) async {
    final response = await _dio.get<String>(
      '/plugin.php',
      queryParameters: {
        'id': 'k_misign:sign',
        'operation': 'list',
        'op': type,
        'page': page,
      },
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );

    return _signParser.parseRank(
      response.data ?? '',
      baseUrl: baseUrl,
    );
  }

  Future<List<Thread>> getMyThreads({
    String type = 'thread',
    int page = 1,
  }) async {
    if (!isLoggedIn) {
      throw StateError('请先登录');
    }

    final response = await _dio.get<String>(
      '/home.php',
      queryParameters: {
        'mod': 'space',
        'do': 'thread',
        'view': 'me',
        'type': type,
        'page': page,
      },
      options: Options(
        headers: {
          'Referer':
              '$baseUrl/home.php?mod=space&do=profile&mycenter=1',
        },
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );

    return _accountParser.parseMyThreads(
      response.data ?? '',
      baseUrl: baseUrl,
    );
  }

  Future<List<Thread>> getUserThreads({
    required String uid,
    String type = 'thread',
    int page = 1,
  }) async {
    final response = await _dio.get<String>(
      '/home.php',
      queryParameters: {
        'mod': 'space',
        'uid': uid,
        'do': 'thread',
        'view': 'me',
        'type': type,
        'from': 'space',
        'page': page,
      },
      options: Options(
        headers: {
          'Referer': '$baseUrl/home.php?mod=space&uid=$uid&do=profile&mobile=2',
        },
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );

    return _accountParser.parseMyThreads(
      response.data ?? '',
      baseUrl: baseUrl,
    );
  }

  Future<List<FavoriteItem>> getMyFavorites({
    String type = 'all',
    int page = 1,
  }) async {
    if (!isLoggedIn) {
      throw StateError('请先登录');
    }

    final response = await _dio.get<String>(
      '/home.php',
      queryParameters: {
        'mod': 'space',
        'do': 'favorite',
        'view': 'me',
        'type': type,
        'page': page,
      },
      options: Options(
        headers: {
          'Referer':
              '$baseUrl/home.php?mod=space&do=profile&mycenter=1',
        },
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );

    return _accountParser.parseFavorites(response.data ?? '');
  }

  Future<List<FriendItem>> getMyFriends({
    int page = 1,
  }) async {
    if (!isLoggedIn) {
      throw StateError('请先登录');
    }

    final response = await _dio.get<String>(
      '/home.php',
      queryParameters: {
        'mod': 'space',
        'do': 'friend',
        'page': page,
      },
      options: Options(
        headers: {
          'Referer':
              '$baseUrl/home.php?mod=space&do=profile&mycenter=1',
        },
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );

    return _accountParser.parseFriends(
      response.data ?? '',
      baseUrl: baseUrl,
    );
  }

  Future<BasicProfileForm> getBasicProfileForm() async {
    if (!isLoggedIn) {
      throw StateError('请先登录');
    }

    final response = await _dio.get<String>(
      '/home.php',
      queryParameters: const {
        'mod': 'spacecp',
        'ac': 'profile',
        'op': 'base',
      },
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );

    return _userCenterParser.parseBasicProfile(
      response.data ?? '',
    );
  }

  Future<OperationResult> updateBasicProfile(
    BasicProfileForm form,
  ) async {
    if (!isLoggedIn) {
      return const OperationResult(
        success: false,
        message: '请先登录',
      );
    }

    try {
      // 先打开编辑页，让页面本身的 formhash 进入全局缓存。
      await getBasicProfileForm();
      final hash = await getFormhash();

      final response = await _dio.post<String>(
        '/home.php',
        queryParameters: const {
          'mod': 'spacecp',
          'ac': 'profile',
          'op': 'base',
        },
        data: FormData.fromMap({
          'formhash': hash,
          'realname': form.realname,
          'privacy[realname]': form.privacyRealname,
          'gender': form.gender,
          'privacy[gender]': form.privacyGender,
          'birthyear': form.birthyear,
          'birthmonth': form.birthmonth,
          'birthday': form.birthday,
          'privacy[birthday]': form.privacyBirthday,
          'resideprovince': form.resideProvince,
          'privacy[residecity]': form.privacyResideCity,
          'occupation': form.occupation,
          'privacy[occupation]': form.privacyOccupation,
          'profilesubmit': 'true',
          'profilesubmitbtn': 'true',
        }),
        options: Options(
          headers: {
            'Referer':
                '$baseUrl/home.php?mod=spacecp&ac=profile&op=base',
          },
          responseType: ResponseType.plain,
          followRedirects: true,
        ),
      );

      final body = response.data ?? '';
      final success = body.contains('parent.show_success') ||
          body.contains('show_success');

      return OperationResult(
        success: success,
        message: success ? '资料已保存' : '保存失败，请检查服务器返回',
      );
    } catch (e) {
      return OperationResult(
        success: false,
        message: '保存失败：$e',
      );
    }
  }

  Future<CreditSummary> getCreditSummary() async {
    if (!isLoggedIn) {
      throw StateError('请先登录');
    }

    final response = await _dio.get<String>(
      '/home.php',
      queryParameters: const {
        'mod': 'spacecp',
        'ac': 'credit',
      },
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );

    return _userCenterParser.parseCreditSummary(
      response.data ?? '',
    );
  }

  Future<RemoteTextPageData> getCreditSection(
    String op,
  ) async {
    if (!isLoggedIn) {
      throw StateError('请先登录');
    }

    final query = <String, dynamic>{
      'mod': 'spacecp',
      'ac': 'credit',
      'op': op,
    };

    if (op == 'log') {
      query['inajax'] = 1;
    }

    final response = await _dio.get<String>(
      '/home.php',
      queryParameters: query,
      options: Options(
        headers: op == 'log'
            ? const {'X-Requested-With': 'XMLHttpRequest'}
            : null,
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );

    return _userCenterParser.parseTextPage(
      response.data ?? '',
      fallbackTitle: op == 'log' ? '积分记录' : '积分明细',
    );
  }

  Future<SpaceUserProfile> getSpaceUserProfile(
    String uid,
  ) async {
    final response = await _dio.get<String>(
      '/home.php',
      queryParameters: {
        'mod': 'space',
        'uid': uid,
        'do': 'profile',
      },
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );

    return _userCenterParser.parseSpaceProfile(
      response.data ?? '',
      uid: uid,
      baseUrl: baseUrl,
    );
  }

  Future<List<SocialUser>> getSocialUsers({
    required String type,
    required String uid,
    int page = 1,
  }) async {
    if (!isLoggedIn &&
        (type == 'visitor' || type == 'trace' || type == 'blacklist')) {
      throw StateError('请先登录');
    }

    late final Map<String, dynamic> query;

    switch (type) {
      case 'friend':
        query = {
          'mod': 'space',
          'uid': uid,
          'do': 'friend',
          'view': 'me',
          'from': 'space',
          'page': page,
        };
        break;
      case 'following':
        query = {
          'mod': 'follow',
          'do': 'following',
          'uid': uid,
          'page': page,
        };
        break;
      case 'follower':
        query = {
          'mod': 'follow',
          'do': 'follower',
          'uid': uid,
          'page': page,
        };
        break;
      case 'visitor':
        query = {
          'mod': 'space',
          'do': 'friend',
          'view': 'visitor',
          'page': page,
        };
        break;
      case 'trace':
        query = {
          'mod': 'space',
          'do': 'friend',
          'view': 'trace',
          'page': page,
        };
        break;
      case 'blacklist':
        query = {
          'mod': 'space',
          'do': 'friend',
          'view': 'blacklist',
          'page': page,
        };
        break;
      default:
        throw ArgumentError.value(type, 'type');
    }

    final response = await _dio.get<String>(
      '/home.php',
      queryParameters: query,
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );

    return _userCenterParser.parseSocialUsers(
      response.data ?? '',
      baseUrl: baseUrl,
    );
  }

  Future<bool> isUserBlocked(String uid) async {
    if (!isLoggedIn || uid.isEmpty) return false;

    // 黑名单没有稳定的单用户状态接口，直接以真实黑名单列表为准。
    // 通常只有一页；这里继续翻页，避免用户较多时只检查到第一页。
    final seen = <String>{};
    for (var page = 1; page <= 20; page++) {
      final users = await getSocialUsers(
        type: 'blacklist',
        uid: currentUid ?? '',
        page: page,
      );
      if (users.any((user) => user.uid == uid)) return true;
      if (users.isEmpty) break;

      final before = seen.length;
      seen.addAll(users.map((user) => user.uid));
      if (seen.length == before) break;
    }
    return false;
  }

  Future<List<FriendRequestItem>> getFriendRequests() async {
    if (!isLoggedIn) {
      throw StateError('请先登录');
    }

    final response = await _dio.get<String>(
      '/home.php',
      queryParameters: const {
        'mod': 'spacecp',
        'ac': 'friend',
        'op': 'request',
        'inajax': 1,
      },
      options: Options(
        headers: {
          'X-Requested-With': 'XMLHttpRequest',
          'Referer':
              '$baseUrl/home.php?mod=space&do=friend&view=trace',
        },
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );

    return _userCenterParser.parseFriendRequests(
      response.data ?? '',
      baseUrl: baseUrl,
    );
  }

  Future<OperationResult> followUser(String uid) async {
    if (!isLoggedIn) {
      return const OperationResult(success: false, message: '请先登录');
    }

    try {
      final hash = await getFormhash();

      final response = await _dio.get<String>(
        '/home.php',
        queryParameters: {
          'mod': 'spacecp',
          'ac': 'follow',
          'op': 'add',
          'fuid': uid,
          'hash': hash,
          'from': 'a_followmod_$uid',
          'handlekey': 'followmod',
          'inajax': 1,
        },
        options: Options(
          headers: {
            'X-Requested-With': 'XMLHttpRequest',
            'Referer': '$baseUrl/home.php?mod=space&do=friend',
          },
          responseType: ResponseType.plain,
          followRedirects: true,
        ),
      );

      final message = _extractAjaxMessage(response.data ?? '');
      final success = message.contains('成功收听') ||
          message.contains('关注成功') ||
          message.contains('已经关注') ||
          message.contains('已关注');

      return OperationResult(
        success: success,
        message: success
            ? (message.isEmpty ? '关注成功' : message)
            : (message.isEmpty ? '关注失败' : message),
      );
    } catch (e) {
      return OperationResult(
        success: false,
        message: '关注失败：$e',
      );
    }
  }

  Future<OperationResult> unfollowUser(
    String uid, {
    String? ownUid,
  }) async {
    if (!isLoggedIn) {
      return const OperationResult(success: false, message: '请先登录');
    }

    try {
      final response = await _dio.get<String>(
        '/home.php',
        queryParameters: {
          'mod': 'spacecp',
          'ac': 'follow',
          'op': 'del',
          'fuid': uid,
          'handlekey': 'following',
          'inajax': 1,
        },
        options: Options(
          headers: {
            'X-Requested-With': 'XMLHttpRequest',
            if (ownUid != null && ownUid.isNotEmpty)
              'Referer':
                  '$baseUrl/home.php?mod=follow&do=following&uid=$ownUid',
          },
          responseType: ResponseType.plain,
          followRedirects: true,
        ),
      );

      final message = _extractAjaxMessage(response.data ?? '');
      final success = message.contains('取消成功');

      return OperationResult(
        success: success,
        message: success
            ? '取消关注成功'
            : (message.isEmpty ? '取消关注失败' : message),
      );
    } catch (e) {
      return OperationResult(
        success: false,
        message: '取消关注失败：$e',
      );
    }
  }

  Future<PokePageData> getPokePage(String uid) async {
    if (!isLoggedIn) throw StateError('请先登录');

    final response = await _dio.get<String>(
      '/home.php',
      queryParameters: {
        'mod': 'spacecp',
        'ac': 'poke',
        'op': 'send',
        'uid': uid,
        'handlekey': 'propokehk_$uid',
      },
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );

    final data = _userCenterParser.parsePokePage(
      response.data ?? '',
      baseUrl: baseUrl,
    );
    if (data.formhash.isNotEmpty) {
      _rememberFormhash(data.formhash);
    }
    return data;
  }

  Future<OperationResult> sendPoke({
    required String uid,
    required int iconId,
    String note = '',
  }) async {
    if (!isLoggedIn) {
      return const OperationResult(success: false, message: '请先登录');
    }

    try {
      final hash = await getFormhash();
      final referer =
          '$baseUrl/home.php?mod=spacecp&ac=poke&op=send&uid=$uid&handlekey=propokehk_$uid';

      final response = await _dio.post<String>(
        '/home.php',
        queryParameters: {
          'mod': 'spacecp',
          'ac': 'poke',
          'op': 'send',
          'uid': uid,
        },
        data: {
          'referer': '$baseUrl/home.php?mod=space&uid=$uid&do=profile',
          'pokesubmit': 'true',
          'formhash': hash,
          'from': '',
          'iconid': iconId,
          'note': note.trim(),
          'pokesubmit_btn': 'true',
        },
        options: Options(
          headers: {'Referer': referer},
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.plain,
          followRedirects: true,
        ),
      );

      final body = response.data ?? '';
      final message = _extractAjaxMessage(body);
      final success = body.contains('已发送') || message.contains('已发送');
      return OperationResult(
        success: success,
        message: success ? '招呼已发送' : (message.isEmpty ? '发送失败' : message),
      );
    } catch (e) {
      return OperationResult(success: false, message: '发送失败：$e');
    }
  }

  Future<OperationResult> respondFriendRequest(
    String? actionUrl,
  ) async {
    if (!isLoggedIn || actionUrl == null || actionUrl.isEmpty) {
      return const OperationResult(
        success: false,
        message: '好友请求操作地址无效',
      );
    }

    try {
      final uri = Uri.parse(actionUrl);
      final query = Map<String, dynamic>.from(uri.queryParameters);
      query['inajax'] = 1;

      final response = await _dio.get<String>(
        uri.path,
        queryParameters: query,
        options: Options(
          headers: const {
            'X-Requested-With': 'XMLHttpRequest',
          },
          responseType: ResponseType.plain,
          followRedirects: true,
        ),
      );

      final text = _extractAjaxMessage(response.data ?? '');

      final failed = text.contains('失败') ||
          text.contains('错误') ||
          text.contains('不存在');

      return OperationResult(
        success: !failed,
        message: text.isEmpty
            ? (!failed ? '操作成功' : '操作失败')
            : text,
      );
    } catch (e) {
      return OperationResult(
        success: false,
        message: '操作失败：$e',
      );
    }
  }

  /// 主动加好友（发送好友请求）。
  Future<OperationResult> addFriend({
    required String uid,
    String note = '',
  }) async {
    if (!isLoggedIn) {
      return const OperationResult(success: false, message: '请先登录');
    }
    try {
      final formhash = await getFormhash();
      final response = await _dio.post<String>(
        '/home.php',
        queryParameters: {
          'mod': 'spacecp',
          'ac': 'friend',
          'op': 'add',
          'uid': uid,
          'inajax': 1,
        },
        data: {
          'formhash': formhash,
          'referer': '$baseUrl/home.php?mod=space&uid=$uid&do=profile',
          'addsubmit': 'true',
          'note': note,
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {
            'X-Requested-With': 'XMLHttpRequest',
            'Referer':
                '$baseUrl/home.php?mod=spacecp&ac=friend&op=add&uid=$uid&mobile=2',
          },
          responseType: ResponseType.plain,
        ),
      );

      final text = _extractAjaxMessage(response.data ?? '');
      final success = text.contains('好友请求已发送') ||
          text.contains('succeedhandle') ||
          text.contains('已经') && text.contains('好友');
      return OperationResult(
        success: success,
        message: text.isEmpty ? (success ? '好友请求已发送' : '操作失败') : text,
      );
    } catch (e) {
      return OperationResult(success: false, message: '操作失败：$e');
    }
  }

  /// 拉黑用户（加入黑名单）。
  Future<OperationResult> blockUser({
    required String uid,
    required String username,
  }) async {
    if (!isLoggedIn) {
      return const OperationResult(success: false, message: '请先登录');
    }
    try {
      final formhash = await getFormhash();
      final response = await _dio.post<String>(
        '/home.php',
        queryParameters: {
          'mod': 'spacecp',
          'ac': 'friend',
          'op': 'blacklist',
          'start': '',
          'inajax': 1,
        },
        data: {
          'blacklistsubmit': 'true',
          'formhash': formhash,
          'username': username,
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {
            'X-Requested-With': 'XMLHttpRequest',
            'Referer':
                '$baseUrl/home.php?mod=space&uid=$uid&do=profile&mobile=2',
          },
          responseType: ResponseType.plain,
        ),
      );

      final text = _extractAjaxMessage(response.data ?? '');
      final success = text.contains('成功') || text.contains('succeedhandle');
      return OperationResult(
        success: success,
        message: text.isEmpty ? (success ? '已加入黑名单' : '操作失败') : text,
      );
    } catch (e) {
      return OperationResult(success: false, message: '操作失败：$e');
    }
  }

  /// 取消拉黑（移出黑名单）。
  Future<OperationResult> unblockUser({required String uid}) async {
    if (!isLoggedIn) {
      return const OperationResult(success: false, message: '请先登录');
    }
    try {
      final response = await _dio.get<String>(
        '/home.php',
        queryParameters: {
          'mod': 'spacecp',
          'ac': 'friend',
          'op': 'blacklist',
          'subop': 'delete',
          'uid': uid,
          'start': '',
          'inajax': 1,
        },
        options: Options(
          headers: {
            'X-Requested-With': 'XMLHttpRequest',
            'Referer':
                '$baseUrl/home.php?mod=space&do=friend&view=blacklist&mobile=2',
          },
          responseType: ResponseType.plain,
        ),
      );

      final text = _extractAjaxMessage(response.data ?? '');
      final success = text.contains('成功') || text.contains('succeedhandle');
      return OperationResult(
        success: success,
        message: text.isEmpty ? (success ? '已移出黑名单' : '操作失败') : text,
      );
    } catch (e) {
      return OperationResult(success: false, message: '操作失败：$e');
    }
  }

  Future<SignatureProfileForm> getSignatureProfile() async {
    if (!isLoggedIn) throw StateError('请先登录');

    final response = await _dio.get<String>(
      '/home.php',
      queryParameters: const {
        'mod': 'spacecp',
        'ac': 'profile',
        'op': 'info',
      },
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );

    return _userCenterParser.parseSignatureProfile(response.data ?? '');
  }

  Future<OperationResult> updateSignatureProfile(
    SignatureProfileForm form,
  ) async {
    if (!isLoggedIn) {
      return const OperationResult(success: false, message: '请先登录');
    }

    try {
      await getSignatureProfile();
      final hash = await getFormhash();

      final response = await _dio.post<String>(
        '/home.php',
        queryParameters: const {
          'mod': 'spacecp',
          'ac': 'profile',
          'op': 'info',
        },
        data: FormData.fromMap({
          'formhash': hash,
          'privacy[bio]': form.privacyBio,
          'bio': form.bio,
          'sightml': form.signature,
          'profilesubmit': 'true',
          'profilesubmitbtn': 'true',
        }),
        options: Options(
          headers: {
            'Referer':
                '$baseUrl/home.php?mod=spacecp&ac=profile&op=info',
          },
          responseType: ResponseType.plain,
          followRedirects: true,
        ),
      );

      final success = (response.data ?? '').contains('show_success');
      return OperationResult(
        success: success,
        message: success ? '简介与签名已保存' : '保存失败',
      );
    } catch (e) {
      return OperationResult(
        success: false,
        message: '保存失败：$e',
      );
    }
  }

  Future<PasswordSecurityData> getPasswordSecurity() async {
    if (!isLoggedIn) throw StateError('请先登录');

    final response = await _dio.get<String>(
      '/home.php',
      queryParameters: const {
        'mod': 'spacecp',
        'ac': 'profile',
        'op': 'password',
        'from': 'contact',
      },
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );

    return _userCenterParser.parsePasswordSecurity(response.data ?? '');
  }

  Future<OperationResult> resendVerificationEmail() async {
    if (!isLoggedIn) {
      return const OperationResult(success: false, message: '请先登录');
    }

    try {
      final page = await getPasswordSecurity();
      final hash = page.formhash.isNotEmpty
          ? page.formhash
          : await getFormhash();

      final response = await _dio.get<String>(
        '/home.php',
        queryParameters: {
          'mod': 'spacecp',
          'ac': 'profile',
          'op': 'password',
          'resend': 1,
          'formhash': hash,
          'inajax': 1,
        },
        options: Options(
          headers: {
            'X-Requested-With': 'XMLHttpRequest',
            'Referer':
                '$baseUrl/home.php?mod=spacecp&ac=profile&op=password&from=contact',
          },
          responseType: ResponseType.plain,
          followRedirects: true,
        ),
      );

      final message = _extractAjaxMessage(response.data ?? '');
      final success = message.contains('邮件已发送');

      return OperationResult(
        success: success,
        message: success
            ? '验证邮件已发送，请稍后查收'
            : (message.isEmpty ? '发送失败' : message),
      );
    } catch (e) {
      return OperationResult(success: false, message: '发送失败：$e');
    }
  }

  Future<OperationResult> updatePasswordSecurity(
    PasswordSecurityUpdate update,
  ) async {
    if (!isLoggedIn) {
      return const OperationResult(success: false, message: '请先登录');
    }
    if (update.oldPassword.isEmpty) {
      return const OperationResult(success: false, message: '请输入原密码');
    }
    if (update.newPassword != update.newPasswordConfirm) {
      return const OperationResult(success: false, message: '两次输入的新密码不一致');
    }

    try {
      final page = await getPasswordSecurity();
      final hash = page.formhash.isNotEmpty ? page.formhash : await getFormhash();

      final response = await _dio.post<String>(
        '/home.php',
        queryParameters: const {
          'mod': 'spacecp',
          'ac': 'profile',
          'handlekey': 'undefined',
          'inajax': 1,
        },
        data: {
          'formhash': hash,
          'oldpassword': update.oldPassword,
          'newpassword': update.newPassword,
          'newpassword2': update.newPasswordConfirm,
          'emailnew': update.email,
          'secmobiccnew': update.mobileCountryCode,
          'secmobilenew': update.mobile,
          'questionidnew': update.questionId,
          'answernew': update.answer,
          'passwordsubmit': 'true',
        },
        options: Options(
          headers: {
            'X-Requested-With': 'XMLHttpRequest',
            'Referer':
                '$baseUrl/home.php?mod=spacecp&ac=profile&op=password&from=contact',
          },
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.plain,
          followRedirects: true,
        ),
      );

      final body = response.data ?? '';
      final message = _extractAjaxMessage(body);
      final success = body.contains('个人资料保存成功') ||
          message.contains('个人资料保存成功');
      return OperationResult(
        success: success,
        message: success ? '安全设置保存成功' : (message.isEmpty ? '保存失败' : message),
      );
    } catch (e) {
      return OperationResult(success: false, message: '保存失败：$e');
    }
  }

  Future<ContactProfileForm> getContactProfile() async {
    if (!isLoggedIn) throw StateError('请先登录');

    final response = await _dio.get<String>(
      '/home.php',
      queryParameters: const {
        'mod': 'spacecp',
        'ac': 'profile',
        'op': 'contact',
      },
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );

    return _userCenterParser.parseContactProfile(response.data ?? '');
  }

  Future<OperationResult> updateContactProfile(
    ContactProfileForm form,
  ) async {
    if (!isLoggedIn) {
      return const OperationResult(success: false, message: '请先登录');
    }

    try {
      final hash = await getFormhash();
      final response = await _dio.post<String>(
        '/home.php',
        queryParameters: const {
          'mod': 'spacecp',
          'ac': 'profile',
          'op': 'contact',
        },
        data: FormData.fromMap({
          'formhash': hash,
          'qq': form.qq,
          'privacy[qq]': form.privacyQq,
          'mobile': form.mobile,
          'privacy[mobile]': form.privacyMobile,
          'profilesubmit': 'true',
          'profilesubmitbtn': 'true',
        }),
        options: Options(
          headers: {
            'Referer': '$baseUrl/home.php?mod=spacecp&ac=profile&op=contact',
          },
          responseType: ResponseType.plain,
          followRedirects: true,
        ),
      );

      final success = (response.data ?? '').contains('show_success');
      return OperationResult(
        success: success,
        message: success ? '联系方式已保存' : '保存失败',
      );
    } catch (e) {
      return OperationResult(success: false, message: '保存失败：$e');
    }
  }

  Future<SmsBindingData> getSmsBinding() async {
    if (!isLoggedIn) throw StateError('请先登录');

    final response = await _dio.get<String>(
      '/home.php',
      queryParameters: const {
        'mod': 'spacecp',
        'ac': 'plugin',
        'id': 'comiis_sms:comiis_setup',
      },
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );

    return _userCenterParser.parseSmsBinding(response.data ?? '');
  }

  Future<SmsCodeResult> requestSmsCode({
    required String action,
    required String phone,
  }) async {
    if (!isLoggedIn) {
      return const SmsCodeResult(success: false, message: '请先登录');
    }
    final normalizedAction = action == 'Unbundling' ? 'Unbundling' : 'binding';

    try {
      final response = await _dio.get<String>(
        '/plugin.php',
        queryParameters: {
          'id': 'comiis_sms',
          'action': normalizedAction,
          'comiis_tel': phone.trim(),
          'inajax': 1,
        },
        options: Options(
          headers: {
            'X-Requested-With': 'XMLHttpRequest',
            'Referer':
                '$baseUrl/home.php?mod=spacecp&ac=plugin&id=comiis_sms:comiis_setup',
          },
          responseType: ResponseType.plain,
          followRedirects: true,
        ),
      );

      final body = response.data ?? '';
      final match = RegExp(r'comiis_mob_reg\|(\d+)\|(\d+)').firstMatch(body);
      final success = match?.group(1) == '1';
      final cooldown = int.tryParse(match?.group(2) ?? '') ?? 0;
      return SmsCodeResult(
        success: success,
        message: success ? '验证码已发送' : '验证码发送失败',
        cooldownSeconds: cooldown,
      );
    } catch (e) {
      return SmsCodeResult(success: false, message: '验证码发送失败：$e');
    }
  }

  Future<OperationResult> confirmSmsBinding({
    required String action,
    required String phone,
    required String code,
  }) async {
    if (!isLoggedIn) {
      return const OperationResult(success: false, message: '请先登录');
    }

    final normalizedAction = action == 'Unbundling' ? 'Unbundling' : 'binding';
    try {
      final hash = await getFormhash();
      final headerReferer = normalizedAction == 'Unbundling'
          ? '$baseUrl/home.php?mod=spacecp&ac=plugin&id=comiis_sms:comiis_setup'
          : '$baseUrl/home.php?mod=spacecp&ac=plugin&id=comiis_sms:comiis_setup&mobile=2';
      final bodyReferer = normalizedAction == 'Unbundling'
          ? '$baseUrl/home.php?mod=spacecp&ac=plugin&id=comiis_sms:comiis_setup&mods=rename'
          : '$baseUrl/plugin.php?id=comiis_sms:comiis_sms_post&action=Unbundling';

      final response = await _dio.post<String>(
        '/plugin.php',
        queryParameters: {
          'id': 'comiis_sms:comiis_sms_post',
          'action': normalizedAction,
        },
        data: FormData.fromMap({
          'formhash': hash,
          'comiis_mobile_bindingsubmit': 'true',
          'referer': bodyReferer,
          'comiis_tel': phone.trim(),
          'code': code.trim(),
        }),
        options: Options(
          headers: {'Referer': headerReferer},
          responseType: ResponseType.plain,
          followRedirects: true,
        ),
      );

      final body = response.data ?? '';
      final success = normalizedAction == 'Unbundling'
          ? body.contains('解除绑定成功')
          : body.contains('绑定成功');
      return OperationResult(
        success: success,
        message: success
            ? (normalizedAction == 'Unbundling' ? '解除绑定成功' : '绑定成功')
            : (_extractAjaxMessage(body).isEmpty
                ? '操作失败，请检查验证码'
                : _extractAjaxMessage(body)),
      );
    } catch (e) {
      return OperationResult(success: false, message: '操作失败：$e');
    }
  }

  Future<OperationResult> uploadAvatarJpeg(List<int> jpegBytes) async {
    if (!isLoggedIn) {
      return const OperationResult(success: false, message: '请先登录');
    }
    if (jpegBytes.isEmpty) {
      return const OperationResult(success: false, message: '图片数据为空');
    }

    try {
      final hash = await getFormhash();
      final dataUrl = 'data:image/jpeg;base64,${base64Encode(jpegBytes)}';
      final response = await _dio.post<String>(
        '/plugin.php',
        queryParameters: const {
          'id': 'comiis_app_avatar',
          'inajax': 1,
          'mobile': 2,
        },
        data: {
          'str': dataUrl,
          'formhash': hash,
          'comiis_submit': 'yes',
        },
        options: Options(
          headers: {
            'X-Requested-With': 'XMLHttpRequest',
            'Referer':
                '$baseUrl/home.php?mod=space&do=profile&set=comiis&mycenter=1',
          },
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.plain,
          followRedirects: true,
        ),
      );

      final success = response.statusCode == 200;
      return OperationResult(
        success: success,
        message: success ? '头像更新成功' : '头像更新失败',
      );
    } catch (e) {
      return OperationResult(success: false, message: '头像更新失败：$e');
    }
  }

  Future<InviteStatusData> getInviteStatus() async {
    if (!isLoggedIn) throw StateError('请先登录');

    final response = await _dio.get<String>(
      '/home.php',
      queryParameters: const {
        'mod': 'spacecp',
        'ac': 'invite',
      },
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );
    return _userCenterParser.parseInviteStatus(response.data ?? '');
  }

  Future<PromotionData> getPromotion() async {
    if (!isLoggedIn) throw StateError('请先登录');

    final response = await _dio.get<String>(
      '/home.php',
      queryParameters: const {
        'mod': 'spacecp',
        'ac': 'promotion',
      },
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );

    return _userCenterParser.parsePromotion(
      response.data ?? '',
      baseUrl: baseUrl,
    );
  }

  Future<List<CreditRecord>> getCreditRecords(String op) async {
    if (!isLoggedIn) throw StateError('请先登录');

    final query = <String, dynamic>{
      'mod': 'spacecp',
      'ac': 'credit',
      'op': op,
    };
    if (op == 'log') query['inajax'] = 1;

    final response = await _dio.get<String>(
      '/home.php',
      queryParameters: query,
      options: Options(
        headers: op == 'log'
            ? const {'X-Requested-With': 'XMLHttpRequest'}
            : null,
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );

    return _userCenterParser.parseCreditRecords(response.data ?? '');
  }

  Future<List<PmConversationSummary>> getPmConversations() async {
    if (!isLoggedIn) throw StateError('请先登录');

    final response = await _dio.get<String>(
      '/home.php',
      queryParameters: const {
        'mod': 'space',
        'do': 'pm',
      },
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );

    return _userCenterParser.parsePmList(
      response.data ?? '',
      baseUrl: baseUrl,
    );
  }

  Future<PmConversationData> getPmConversation(String touid) async {
    if (!isLoggedIn) throw StateError('请先登录');

    // 历史私信的左右方向依赖当前账号 UID。首次进入私信时如果还没从
    // 其它页面响应中缓存到 discuz_uid，先从自己的资料页补齐一次。
    if (_currentUid == null || _currentUid!.isEmpty) {
      try {
        await getProfile();
      } catch (_) {
        // 对话 HTML 自身仍会再尝试解析 discuz_uid，不因这个辅助请求失败阻断。
      }
    }

    final response = await _dio.get<String>(
      '/home.php',
      queryParameters: {
        'mod': 'space',
        'do': 'pm',
        'subop': 'view',
        'touid': touid,
      },
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );

    final data = _userCenterParser.parsePmConversation(
      response.data ?? '',
      touid: touid,
      baseUrl: baseUrl,
      myUid: _currentUid,
    );

    if (data.formhash.isNotEmpty) {
      _rememberFormhash(data.formhash);
    }

    return data;
  }

  Future<OperationResult> sendPrivateMessage({
    required String touid,
    required String pmid,
    required String message,
  }) async {
    if (!isLoggedIn) {
      return const OperationResult(success: false, message: '请先登录');
    }

    final text = message.trim();
    if (text.isEmpty) {
      return const OperationResult(success: false, message: '消息不能为空');
    }

    try {
      final hash = await getFormhash();

      final response = await _dio.post<String>(
        '/home.php',
        queryParameters: {
          'mod': 'spacecp',
          'ac': 'pm',
          'op': 'send',
          'pmid': pmid,
          'daterange': 2,
          'pmsubmit': 'yes',
          'mobile': 2,
          'handlekey': 'pmform',
          'inajax': 1,
        },
        data: {
          'formhash': hash,
          'touid': touid,
          'message': text,
        },
        options: Options(
          headers: {
            'X-Requested-With': 'XMLHttpRequest',
            'Referer':
                '$baseUrl/home.php?mod=space&do=pm&subop=view&touid=$touid',
          },
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.plain,
          followRedirects: true,
        ),
      );

      final responseMessage = _extractAjaxMessage(response.data ?? '');
      final success = responseMessage.contains('操作成功');

      return OperationResult(
        success: success,
        message: success
            ? '发送成功'
            : (responseMessage.isEmpty ? '发送失败' : responseMessage),
      );
    } catch (e) {
      return OperationResult(success: false, message: '发送失败：$e');
    }
  }

  Future<List<PmMessage>> pollPrivateMessages({
    required String touid,
    required String pmid,
    required int endTimestamp,
  }) async {
    if (!isLoggedIn) return const [];

    final response = await _dio.get<String>(
      '/home.php',
      queryParameters: {
        'mod': 'spacecp',
        'ac': 'pm',
        'op': 'showmsg',
        'msgonly': 1,
        'touid': touid,
        'pmid': pmid,
        'inajax': 1,
        'daterange': 1,
        'comiis_msg_endtime': endTimestamp,
      },
      options: Options(
        headers: const {
          'X-Requested-With': 'XMLHttpRequest',
        },
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );

    return _userCenterParser.parsePmMessageFragment(
      response.data ?? '',
      myUid: _currentUid,
      peerUid: touid,
    );
  }


  /// 获取消息中心未读汇总。
  ///
  /// 私信/论坛通知优先从普通论坛页的全局 `newpm/newprompt` 状态读取，
  /// 不主动打开通知中心，避免“为了查未读数反而把提醒标成已读”。
  /// 好友申请使用真实待处理请求列表计数。
  Future<MessageUnreadSummary> getMessageUnreadSummary() async {
    if (!isLoggedIn) return const MessageUnreadSummary.empty();

    var global = const MessageUnreadSummary.empty();
    try {
      final response = await _dio.get<String>(
        '/forum.php',
        queryParameters: const {'mobile': 2},
        options: Options(
          responseType: ResponseType.plain,
          followRedirects: true,
        ),
      );
      global = _userCenterParser.parseGlobalMessageUnread(response.data ?? '');
    } catch (_) {
      // 全局未读探测失败不影响其它两项。
    }

    var pm = global.privateMessages;
    if (!pm.isVisible) {
      try {
        if (await checkNewPrivateMessage()) {
          pm = const UnreadBadgeInfo(count: null, hasUnread: true);
        }
      } catch (_) {}
    }

    var friendRequests = const UnreadBadgeInfo.none();
    try {
      final requests = await getFriendRequests();
      friendRequests = UnreadBadgeInfo(
        count: requests.length,
        hasUnread: requests.isNotEmpty,
      );
    } catch (_) {
      // 好友申请探测失败时不伪造数量。
    }

    return MessageUnreadSummary(
      privateMessages: pm,
      notices: global.notices,
      friendRequests: friendRequests,
    );
  }

  Future<bool> checkNewPrivateMessage() async {
    if (!isLoggedIn) return false;

    try {
      final response = await _dio.get<String>(
        '/home.php',
        queryParameters: {
          'mod': 'spacecp',
          'ac': 'pm',
          'op': 'checknewpm',
          'rand': DateTime.now().millisecondsSinceEpoch,
        },
        options: Options(
          responseType: ResponseType.plain,
          followRedirects: true,
        ),
      );

      return (response.data ?? '').trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<List<WallComment>> getWallComments(String uid) async {
    final targetUid = uid.trim();
    if (targetUid.isEmpty) return const [];

    final response = await _dio.get<String>(
      '/home.php',
      queryParameters: {
        'mod': 'space',
        'uid': targetUid,
        'do': 'wall',
        'mobile': 2,
      },
      options: Options(
        headers: {
          'Referer': '$baseUrl/home.php?mod=space&uid=$targetUid&do=profile',
        },
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );

    return _userCenterParser.parseWallComments(
      response.data ?? '',
      baseUrl: baseUrl,
    );
  }

  Future<OperationResult> postWallComment({
    required String uid,
    required String message,
  }) async {
    if (!isLoggedIn) {
      return const OperationResult(success: false, message: '请先登录');
    }

    final targetUid = uid.trim();
    final text = message.trim();
    if (targetUid.isEmpty) {
      return const OperationResult(success: false, message: '目标用户无效');
    }
    if (text.isEmpty) {
      return const OperationResult(success: false, message: '留言内容不能为空');
    }

    try {
      final hash = await getFormhash();
      final wallPath = 'home.php?mod=space&uid=$targetUid&do=wall';
      final response = await _dio.post<String>(
        '/home.php',
        queryParameters: const {
          'mod': 'spacecp',
          'ac': 'comment',
          'inajax': 1,
        },
        data: {
          'formhash': hash,
          'referer': wallPath,
          'id': targetUid,
          'idtype': 'uid',
          'handlekey': 'qcwall_$targetUid',
          'commentsubmit': 'true',
          'quickcomment': 'true',
          'message': text,
        },
        options: Options(
          headers: {
            'X-Requested-With': 'XMLHttpRequest',
            'Referer': '$baseUrl/$wallPath',
          },
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.plain,
          followRedirects: true,
        ),
      );

      final body = response.data ?? '';
      final responseMessage = _extractAjaxMessage(body);
      final success = body.contains('操作成功') ||
          responseMessage.contains('操作成功') ||
          responseMessage.contains('留言成功');

      return OperationResult(
        success: success,
        message: success
            ? '留言成功'
            : (responseMessage.isEmpty ? '留言失败' : responseMessage),
      );
    } catch (e) {
      return OperationResult(success: false, message: '留言失败：$e');
    }
  }

  Future<OperationResult> deleteWallComment({
    required String uid,
    required String cid,
  }) async {
    if (!isLoggedIn) {
      return const OperationResult(success: false, message: '请先登录');
    }

    final targetUid = uid.trim();
    final commentId = cid.trim();
    if (targetUid.isEmpty || commentId.isEmpty) {
      return const OperationResult(success: false, message: '留言参数无效');
    }

    try {
      final hash = await getFormhash();
      final wallPath = 'home.php?mod=space&uid=$targetUid&do=wall';
      final response = await _dio.post<String>(
        '/home.php',
        queryParameters: {
          'mod': 'spacecp',
          'ac': 'comment',
          'op': 'delete',
          'cid': commentId,
          'inajax': 1,
        },
        data: {
          'formhash': hash,
          'referer': wallPath,
          'deletesubmit': 'true',
        },
        options: Options(
          headers: {
            'X-Requested-With': 'XMLHttpRequest',
            'Referer': '$baseUrl/$wallPath',
          },
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.plain,
          followRedirects: true,
        ),
      );

      final body = response.data ?? '';
      final responseMessage = _extractAjaxMessage(body);
      final success = body.contains('操作成功') ||
          responseMessage.contains('操作成功') ||
          responseMessage.contains('删除成功');

      return OperationResult(
        success: success,
        message: success
            ? '留言已删除'
            : (responseMessage.isEmpty ? '删除失败' : responseMessage),
      );
    } catch (e) {
      return OperationResult(success: false, message: '删除失败：$e');
    }
  }

  Future<UserGroupData> getUserGroupData() async {
    if (!isLoggedIn) {
      throw StateError('请先登录');
    }

    final response = await _dio.get<String>(
      '/home.php',
      queryParameters: const {
        'mod': 'spacecp',
        'ac': 'usergroup',
        'mobile': 2,
      },
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );

    return _accountParser.parseUserGroup(response.data ?? '');
  }

  Future<List<NoticeItem>> getNotices({
    required String view,
    String? type,
    int page = 1,
  }) async {
    final data = await getNoticePage(
      view: view,
      type: type,
      page: page,
    );
    return data.items;
  }

  Future<NoticePageData> getNoticePage({
    required String view,
    String? type,
    int page = 1,
  }) async {
    if (!isLoggedIn) throw StateError('请先登录');

    final safePage = page < 1 ? 1 : page;
    final query = <String, dynamic>{
      'mod': 'space',
      'do': 'notice',
      'view': view,
      'mobile': 2,
    };
    final noticeType = type?.trim() ?? '';
    if (noticeType.isNotEmpty) query['type'] = noticeType;
    if (safePage > 1) query['page'] = safePage;

    final response = await _dio.get<String>(
      '/home.php',
      queryParameters: query,
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );

    return _userCenterParser.parseNoticePage(
      response.data ?? '',
      baseUrl: baseUrl,
      currentPage: safePage,
    );
  }

  Future<OperationResult> ignoreNotice(String? actionUrl) async {
    if (!isLoggedIn) {
      return const OperationResult(success: false, message: '请先登录');
    }
    if (actionUrl == null || actionUrl.trim().isEmpty) {
      return const OperationResult(success: false, message: '屏蔽地址无效');
    }

    try {
      final uri = Uri.parse(actionUrl.replaceAll('&amp;', '&'));
      final getQuery = Map<String, dynamic>.from(uri.queryParameters)
        ..['inajax'] = 1;

      final confirm = await _dio.get<String>(
        uri.path.isEmpty ? '/home.php' : uri.path,
        queryParameters: getQuery,
        options: Options(
          headers: {
            'X-Requested-With': 'XMLHttpRequest',
            'Referer': '$baseUrl/home.php?mod=space&do=notice&mobile=2',
          },
          responseType: ResponseType.plain,
          followRedirects: true,
        ),
      );

      var confirmBody = confirm.data ?? '';
      final cdata = RegExp(
        r'<!\[CDATA\[(.*?)\]\]>',
        dotAll: true,
        caseSensitive: false,
      ).firstMatch(confirmBody);
      if (cdata != null) confirmBody = cdata.group(1) ?? confirmBody;

      final document = html_parser.parseFragment(confirmBody);
      final form = document.querySelector('form');
      if (form == null) {
        final message = _extractAjaxMessage(confirmBody);
        return OperationResult(
          success: false,
          message: message.isEmpty ? '未获取到屏蔽确认表单' : message,
        );
      }

      final data = <String, dynamic>{};
      for (final input in form.querySelectorAll('input[name]')) {
        final name = input.attributes['name']?.trim() ?? '';
        if (name.isEmpty) continue;
        final type = (input.attributes['type'] ?? '').toLowerCase();
        if ((type == 'checkbox' || type == 'radio') &&
            !input.attributes.containsKey('checked')) {
          continue;
        }
        data[name] = input.attributes['value'] ?? '';
      }
      for (final button in form.querySelectorAll('button[name]')) {
        final name = button.attributes['name']?.trim() ?? '';
        if (name.isEmpty) continue;
        data.putIfAbsent(name, () => button.attributes['value'] ?? 'true');
      }
      data.putIfAbsent('formhash', () => _formhash ?? '');
      if ((data['formhash'] as String?)?.isEmpty ?? true) {
        data['formhash'] = await getFormhash();
      }
      data.putIfAbsent('ignoresubmit', () => 'true');

      final actionRaw =
          (form.attributes['action'] ?? actionUrl).replaceAll('&amp;', '&');
      final actionUri = Uri.parse(Uri.parse(baseUrl).resolve(actionRaw).toString());
      final postQuery = Map<String, dynamic>.from(actionUri.queryParameters)
        ..['inajax'] = 1;

      final response = await _dio.post<String>(
        actionUri.path.isEmpty ? '/home.php' : actionUri.path,
        queryParameters: postQuery,
        data: data,
        options: Options(
          headers: {
            'X-Requested-With': 'XMLHttpRequest',
            'Referer': actionUrl,
          },
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.plain,
          followRedirects: true,
        ),
      );

      final body = response.data ?? '';
      final message = _extractAjaxMessage(body);
      final failed = body.contains('操作失败') ||
          body.contains('错误') ||
          message.contains('失败') ||
          message.contains('错误');
      final success = !failed &&
          (body.contains('操作成功') ||
              body.contains('设置成功') ||
              body.contains('屏蔽成功') ||
              body.contains('succeedhandle_') ||
              message.contains('成功'));

      return OperationResult(
        success: success,
        message: success
            ? (message.isEmpty ? '已屏蔽此来源的通知' : message)
            : (message.isEmpty ? '屏蔽失败' : message),
      );
    } catch (e) {
      return OperationResult(success: false, message: '屏蔽失败：$e');
    }
  }

  Future<RenameStatusData> getRenameStatus() async {
    if (!isLoggedIn) throw StateError('请先登录');

    final response = await _dio.get<String>(
      '/plugin.php',
      queryParameters: const {
        'id': 'nimba_rename',
        'mobile': 2,
      },
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );

    return _userCenterParser.parseRenameStatus(response.data ?? '');
  }

  Future<RemoteTextPageData> getAccountToolPage(
    String key, {
    String? uid,
  }) async {
    if (!isLoggedIn) {
      throw StateError('请先登录');
    }

    late final String path;
    late final Map<String, dynamic> query;
    late final String fallbackTitle;

    switch (key) {
      case 'profile_info':
        path = '/home.php';
        query = {
          'mod': 'spacecp',
          'ac': 'profile',
          'op': 'info',
        };
        fallbackTitle = '详细资料';
        break;
      case 'contact':
        path = '/home.php';
        query = {
          'mod': 'spacecp',
          'ac': 'profile',
          'op': 'contact',
        };
        fallbackTitle = '联系方式';
        break;
      case 'password':
        path = '/home.php';
        query = {
          'mod': 'spacecp',
          'ac': 'profile',
          'op': 'password',
          'from': 'contact',
        };
        fallbackTitle = '修改密码';
        break;
      case 'invite':
        path = '/home.php';
        query = {
          'mod': 'spacecp',
          'ac': 'invite',
        };
        fallbackTitle = '邀请';
        break;
      case 'promotion':
        path = '/home.php';
        query = {
          'mod': 'spacecp',
          'ac': 'promotion',
        };
        fallbackTitle = '访问推广';
        break;
      case 'sms':
        path = '/home.php';
        query = {
          'mod': 'spacecp',
          'ac': 'plugin',
          'id': 'comiis_sms:comiis_setup',
        };
        fallbackTitle = '短信设置';
        break;
      case 'profile_view':
        path = '/home.php';
        query = {
          'mod': 'space',
          'do': 'profile',
          'view': 'me',
          'from': 'space',
        };
        fallbackTitle = '我的资料';
        break;
      default:
        throw ArgumentError.value(key, 'key');
    }

    final response = await _dio.get<String>(
      path,
      queryParameters: query,
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );

    return _userCenterParser.parseTextPage(
      response.data ?? '',
      fallbackTitle: fallbackTitle,
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

  Future<List<MallItem>> getMallItems({
    int page = 1,
  }) async {
    final response = await _dio.get<String>(
      '/keke_integralmall-keke_integralmall.html',
      queryParameters: {
        'page': page,
      },
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );

    return _portalParser.parseMallList(
      response.data ?? '',
      baseUrl: baseUrl,
    );
  }

  Future<MallDetail> getMallDetail(String tid) async {
    final response = await _dio.get<String>(
      '/keke_integralmall-view.html',
      queryParameters: {
        'tid': tid,
      },
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );

    return _portalParser.parseMallDetail(
      response.data ?? '',
      tid: tid,
      baseUrl: baseUrl,
    );
  }

  /// 获取论坛排行榜。
  /// view: credit(积分) / post(发帖) / onlinetime(活跃) / beauty(美女) / handsome(帅哥)
  Future<List<RankItem>> getRanklist({
    String view = 'credit',
  }) async {
    final response = await _dio.get<String>(
      '/misc.php',
      queryParameters: {
        'mod': 'ranklist',
        'type': 'member',
        'view': view,
        if (view == 'onlinetime') 'orderby': 'all',
        'mobile': 2,
      },
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
        validateStatus: (status) => status != null && status < 400,
      ),
    );

    return _portalParser.parseRanklist(
      response.data ?? '',
      baseUrl: baseUrl,
    );
  }

  Future<MallExchangeResult> exchangeMallItem({
    required String tid,
    String address = '',
  }) async {
    if (!isLoggedIn) {
      return const MallExchangeResult(
        success: false,
        message: '请先登录后再兑换',
      );
    }

    try {
      final hash = await getFormhash();

      final popupPath =
          '/plugin.php?id=keke_integralmall:show_win'
          '&tid=$tid&ac=xd&formhash=$hash&mobile=2';

      // 保留论坛原本的确认弹窗请求流程，同时让后续 POST Referer 完全一致。
      await _dio.get<String>(
        popupPath,
        options: Options(
          headers: const {
            'X-Requested-With': 'XMLHttpRequest',
          },
          responseType: ResponseType.plain,
          followRedirects: true,
        ),
      );

      final response = await _dio.post<String>(
        '/plugin.php',
        queryParameters: const {
          'id': 'keke_integralmall:actions',
        },
        data: {
          'formhash': hash,
          'ac': 'xd',
          'tid': tid,
          'addr': address,
        },
        options: Options(
          headers: {
            'X-Requested-With': 'XMLHttpRequest',
            'Referer': '$baseUrl$popupPath',
          },
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.plain,
          followRedirects: true,
        ),
      );

      final decoded = jsonDecode(response.data ?? '{}');
      if (decoded is! Map) {
        return const MallExchangeResult(
          success: false,
          message: '兑换响应格式异常',
        );
      }

      final err = int.tryParse('${decoded['err'] ?? 1}') ?? 1;
      final message = '${decoded['msg'] ?? ''}'.trim();
      final url = '${decoded['url'] ?? ''}'.trim();

      return MallExchangeResult(
        success: err == 0,
        message: message.isEmpty
            ? (err == 0 ? '兑换成功' : '兑换失败')
            : message,
        url: url.isEmpty ? null : url,
      );
    } catch (e) {
      return MallExchangeResult(
        success: false,
        message: '兑换失败：$e',
      );
    }
  }

  Future<String> getMallCardStatus(String tid) async {
    if (!isLoggedIn) {
      throw StateError('请先登录');
    }

    final hash = await getFormhash();
    final response = await _dio.get<String>(
      '/plugin.php',
      queryParameters: {
        'id': 'keke_integralmall:show_win',
        'tid': tid,
        'ac': 'km',
        'formhash': hash,
        'mobile': 2,
      },
      options: Options(
        headers: const {
          'X-Requested-With': 'XMLHttpRequest',
        },
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );

    return _portalParser.parsePopupText(response.data ?? '');
  }

  Future<List<ForumGroup>> getForumGroups() async {
    try {
      final response = await _dio.get<String>(
        '/forum.php',
        queryParameters: const {
          'forumlist': 1,
        },
        options: Options(
          responseType: ResponseType.plain,
          followRedirects: true,
        ),
      );

      final groups = _portalParser.parseForumGroups(
        response.data ?? '',
        baseUrl: baseUrl,
      );

      if (groups.isNotEmpty) {
        return groups;
      }
    } catch (_) {
      // 社区列表有稳定 fid 清单，网络模板异常时直接回退。
    }

    return PortalParser.defaultForumGroups();
  }

  Future<List<Thread>> getForumThreads({
    required String fid,
    String? forumName,
    int page = 1,
  }) async {
    final response = await _dio.get<String>(
      '/forum-$fid-$page.html',
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );

    final items = _parser.parseThreadList(
      response.data ?? '',
      baseUrl: baseUrl,
    );

    // 板块列表页本身通常不会在每一条帖子里重复输出“来自 xx 板块”，
    // 但首页门户会输出。统一在数据层补齐当前板块上下文，这样首页、
    // 搜索、板块等页面使用同一个 ThreadCard 时信息层级完全一致。
    final normalizedForumName = forumName?.trim() ?? '';
    return items.map((thread) {
      final hasForumName = thread.forumName?.trim().isNotEmpty == true;
      final hasForumId = thread.forumId?.trim().isNotEmpty == true;
      if ((hasForumName || normalizedForumName.isEmpty) && hasForumId) {
        return thread;
      }
      return thread.copyWith(
        forumName: hasForumName ? thread.forumName : normalizedForumName,
        forumId: hasForumId ? thread.forumId : fid,
      );
    }).toList(growable: false);
  }

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
        'referer': '$baseUrl/forum.php',
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
          'Referer': '$baseUrl/member.php?mod=logging&action=login&mobile=2',
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

    // CookieManager 已经处理了所有 Set-Cookie/重定向 Cookie。
    // 必须从 CookieJar 读取最终值，而不是只看最终响应头。
    final cookies = await _cookieJar.loadForRequest(Uri.parse(baseUrl));
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

  String? buildAvatarUrl(String? uid) {
    if (uid == null || uid.isEmpty) return null;
    return '$baseUrl/uc_server/avatar.php?uid=$uid&size=middle';
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
    return byValueFirst?.group(1);
  }

  String? _extractMessage(String body) {
    final document = html_parser.parse(body);
    final paragraph = document.querySelector('p')?.text.trim();
    if (paragraph != null && paragraph.isNotEmpty) return paragraph;
    final text = document.body?.text.trim();
    return text?.isNotEmpty == true ? text : null;
  }

  String? _absoluteUrl(String? raw) {
    if (raw == null) return null;
    final value = raw.trim();
    if (value.isEmpty) return null;
    if (value.startsWith('//')) return 'https:$value';
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    if (value.startsWith('/')) return '$baseUrl$value';
    return '$baseUrl/$value';
  }
}
