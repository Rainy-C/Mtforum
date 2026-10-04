part of '../../../services/api_service.dart';

extension ApiServiceThreadPart on ApiService {
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
      baseUrl: ApiService.baseUrl,
    );

    if (detail.formhash.isNotEmpty) {
      _rememberFormhash(detail.formhash);
    }
    return detail;
  }
  /// 通过通知中的 goto=findpost 地址让论坛定位 pid 所在页，再解析该楼层。
  Future<ThreadDetail> getThreadDetailAtPost({
    required String tid,
    required String pid,
    required String targetUrl,
  }) async {
    final uri = Uri.tryParse(targetUrl);
    if (uri == null || pid.trim().isEmpty) {
      return getThreadDetail(tid);
    }
    final redirectResponse = await _dio.getUri<String>(
      uri,
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: false,
        validateStatus: (status) =>
            status != null && status >= 200 && status < 400,
      ),
    );
    final redirectStatus = redirectResponse.statusCode ?? 0;
    final location = redirectResponse.headers.value('location');
    final resolvedTarget = ApiService.resolveFindPostLocation(uri, location);

    if (redirectStatus >= 300 && redirectStatus < 400) {
      if (resolvedTarget == null) {
        throw StateError('楼层定位失败：重定向缺少 Location');
      }
      final pageUri = resolvedTarget.replace(fragment: '');
      final cacheKey = pageUri.toString();
      final cachedAt = _findPostPageCacheTimes[cacheKey];
      final cached = _findPostPageCache[cacheKey];
      if (cached != null &&
          cachedAt != null &&
          DateTime.now().difference(cachedAt) < ApiService._findPostPageCacheTtl) {
        if (cached.posts.any((post) => post.pid == pid)) return cached;
        _findPostPageCache.remove(cacheKey);
        _findPostPageCacheTimes.remove(cacheKey);
      }
      var request = _findPostPageRequests[cacheKey];
      if (request == null) {
        request = _loadFindPostPage(pageUri, tid);
        _findPostPageRequests[cacheKey] = request;
      }
      late final ThreadDetail detail;
      try {
        detail = await request;
      } finally {
        if (identical(_findPostPageRequests[cacheKey], request)) {
          _findPostPageRequests.remove(cacheKey);
        }
      }
      _findPostPageCache[cacheKey] = detail;
      _findPostPageCacheTimes[cacheKey] = DateTime.now();
      if (!detail.posts.any((post) => post.pid == pid)) {
        throw StateError(
          '目标楼层未出现在论坛返回的第 ${detail.page} 页（PID $pid）',
        );
      }
      return detail;
    }

    final detail = _parser.parseThreadDetail(
      redirectResponse.data ?? '',
      tid: tid,
      page: 1,
      baseUrl: ApiService.baseUrl,
    );
    if (!detail.posts.any((post) => post.pid == pid)) {
      throw StateError('论坛未返回 findpost 重定向，且当前页面找不到 PID $pid');
    }
    return detail;
  }
  Future<ThreadDetail> _loadFindPostPage(Uri pageUri, String tid) async {
    final response = await _dio.getUri<String>(
      pageUri,
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
        validateStatus: (status) => status != null && status < 500,
      ),
    );
    final status = response.statusCode ?? 0;
    if (status >= 400 || status == 0) {
      throw StateError('楼层页面加载失败（HTTP $status）');
    }
    final page = int.tryParse(pageUri.queryParameters['page'] ?? '') ?? 1;
    return _parser.parseThreadDetail(
      response.data ?? '',
      tid: tid,
      page: page,
      baseUrl: ApiService.baseUrl,
    );
  }
  Future<Post?> getNoticeReplyPreview(NoticeItem item) async {
    final tid = item.tid?.trim() ?? '';
    final pid = item.pid?.trim() ?? '';
    final targetUrl = item.targetUrl?.trim() ?? '';
    if (tid.isEmpty || pid.isEmpty || targetUrl.isEmpty) return null;
    final detail = await getThreadDetailAtPost(
      tid: tid,
      pid: pid,
      targetUrl: targetUrl,
    );
    for (final post in detail.posts) {
      if (post.pid == pid) return post;
    }
    return null;
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
            'Referer': '${ApiService.baseUrl}/forum-$fid-1.html',
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
        form = _preserveThreadTypes(retryForm, fallback: form);
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
  PostEditorForm _preserveThreadTypes(
    PostEditorForm form, {
    required PostEditorForm fallback,
  }) {
    if (form.threadTypes.isNotEmpty || fallback.threadTypes.isEmpty) {
      return form;
    }

    return PostEditorForm(
      formhash: form.formhash,
      posttime: form.posttime,
      fid: form.fid,
      tid: form.tid,
      pid: form.pid,
      page: form.page,
      subject: form.subject,
      message: form.message,
      deleteValue: form.deleteValue,
      allowNoticeAuthor: form.allowNoticeAuthor,
      useSig: form.useSig,
      uploadUid: form.uploadUid,
      uploadHash: form.uploadHash,
      maxUploadSizeKb: form.maxUploadSizeKb,
      attachmentAids: form.attachmentAids,
      threadTypes: fallback.threadTypes,
      selectedTypeId: fallback.selectedTypeId,
    );
  }
  Future<PostAttachmentUploadResult> uploadPostImage({
    required PostEditorForm form,
    required List<int> bytes,
    required String fileName,
    String? referer,
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
          'Referer': referer ?? _postEditorReferer(form),
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
      return '${ApiService.baseUrl}/forum.php?mod=post&action=edit'
          '&fid=${form.fid}&tid=${form.tid}&pid=${form.pid}&page=${form.page}';
    }
    return '${ApiService.baseUrl}/forum.php?mod=post&action=newthread&fid=${form.fid}';
  }
  void _addAttachmentBindings(
    Map<String, dynamic> data,
    Iterable<String> aids, {
    bool includePermissions = false,
  }) {
    for (final rawAid in aids) {
      final aid = rawAid.trim();
      if (aid.isEmpty || !RegExp(r'^\d+$').hasMatch(aid)) continue;
      data['attachnew[$aid][description]'] = '';
      if (includePermissions) {
        data['attachnew[$aid][readperm]'] = '';
        data['attachnew[$aid][price]'] = '';
      }
    }
  }
  Future<ThreadSubmitResult> submitNewThread({
    required PostEditorForm form,
    required String subject,
    required String message,
    bool? allowNoticeAuthor,
    bool? useSig,
    String? typeId,
    Iterable<String> uploadedAttachmentAids = const [],
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

    final data = <String, dynamic>{
      'formhash': form.formhash,
      'posttime': form.posttime,
      'delete': form.deleteValue,
      'topicsubmit': 'yes',
      'htmlon': '0',
      'subject': title,
      'message': content,
      if (typeId?.trim().isNotEmpty == true) 'typeid': typeId!.trim(),
      if (allowNoticeAuthor ?? (form.allowNoticeAuthor != '0'))
        'allownoticeauthor': '1',
      if (useSig ?? (form.useSig != '0')) 'usesig': '1',
      'save': '',
    };
    _addAttachmentBindings(data, uploadedAttachmentAids);

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
      data: data,
      options: Options(
        contentType: 'application/x-www-form-urlencoded; charset=UTF-8',
        headers: {
          'X-Requested-With': 'XMLHttpRequest',
          'Referer':
              '${ApiService.baseUrl}/forum.php?mod=post&action=newthread&fid=${form.fid}',
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
        '${ApiService.baseUrl}/forum.php?mod=viewthread&tid=$tid&page=$page&mobile=2';

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
          referer: '${ApiService.baseUrl}/thread-$tid-$page-1.html',
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

          final resolved = Uri.parse(ApiService.baseUrl).resolve(rawHref);
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
    String? typeId,
    Iterable<String> uploadedAttachmentAids = const [],
  }) async {
    if (!isLoggedIn) {
      return const ThreadSubmitResult(success: false, message: '请先登录');
    }

    final content = message.trim();
    if (content.isEmpty) {
      return const ThreadSubmitResult(success: false, message: '帖子正文不能为空');
    }

    final data = <String, dynamic>{
      'formhash': form.formhash,
      'posttime': form.posttime,
      'delete': form.deleteValue,
      'htmlon': '0',
      'fid': form.fid,
      'tid': form.tid,
      'pid': form.pid,
      'page': form.page,
      'editsubmit': 'yes',
      'subject': subject.trim(),
      'message': content,
      if (typeId?.trim().isNotEmpty == true) 'typeid': typeId!.trim(),
      if (allowNoticeAuthor ?? (form.allowNoticeAuthor != '0'))
        'allownoticeauthor': '1',
      if (useSig ?? (form.useSig != '0')) 'usesig': '1',
      'save': '',
    };
    _addAttachmentBindings(
      data,
      form.attachmentAids,
      includePermissions: true,
    );
    _addAttachmentBindings(data, uploadedAttachmentAids);

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
      data: data,
      options: Options(
        contentType: 'application/x-www-form-urlencoded; charset=UTF-8',
        headers: {
          'X-Requested-With': 'XMLHttpRequest',
          'Referer': '${ApiService.baseUrl}/forum.php?mod=post&action=edit'
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
  Future<PostEditorForm> getReplyPostForm({
    required String tid,
    required String fid,
    String? repquotePid,
  }) async {
    if (!isLoggedIn) throw StateError('请先登录');

    final targetPid = repquotePid?.trim() ?? '';
    final response = await _dio.get<String>(
      '/forum.php',
      queryParameters: {
        'mod': 'post',
        'action': 'reply',
        'fid': fid,
        'tid': tid,
        if (targetPid.isNotEmpty) 'repquote': targetPid,
        'extra': '',
        'mobile': 2,
      },
      options: Options(
        headers: {'Referer': '${ApiService.baseUrl}/thread-$tid-1-1.html'},
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );

    final body = response.data ?? '';
    final form = _parser.parsePostEditorForm(
      body,
      fallbackFid: fid,
      fallbackTid: tid,
      fallbackPid: targetPid,
    );
    if (form.formhash.isEmpty ||
        form.posttime.isEmpty ||
        !form.canUploadImages) {
      final readable = _extractAjaxMessage(body);
      throw StateError(
        readable.isEmpty ? '未获取到回复图片上传凭证，请重试' : readable,
      );
    }
    _rememberFormhash(form.formhash);
    return form;
  }
  Future<ReplyResult> replyThread({
    required String tid,
    required String fid,
    required String noticeauthor,
    required String message,
    String? repquotePid,
    PostEditorForm? replyForm,
    Iterable<String> uploadedAttachmentAids = const [],
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
      'formhash': replyForm?.formhash ?? await getFormhash(),
      if (replyForm?.posttime.isNotEmpty == true)
        'posttime': replyForm!.posttime,
      'delete': '0',
      'htmlon': '0',
      'save': '',
      'replysubmit': 'yes',
      'noticeauthor': noticeauthor,
      'noticetrimstr': '',
      'noticeauthormsg': '',
      'message': message,
    };
    _addAttachmentBindings(data, uploadedAttachmentAids);

    var postQuery = <String, dynamic>{
      'mod': 'post',
      'action': 'reply',
      'fid': fid,
      'tid': tid,
      'extra': '',
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
            'Referer': '${ApiService.baseUrl}/thread-$tid-1-1.html',
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
      _addAttachmentBindings(data, uploadedAttachmentAids);

      final action = (form.attributes['action'] ?? '')
          .replaceAll('&amp;', '&')
          .trim();
      if (action.isNotEmpty) {
        final uri = Uri.parse(ApiService.baseUrl).resolve(action);
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
          'Referer': '${ApiService.baseUrl}/thread-$tid-1-1.html',
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
}
