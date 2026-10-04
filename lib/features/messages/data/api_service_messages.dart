part of '../../../services/api_service.dart';

extension _ApiServiceMessagesPart on ApiService {
  Future<List<PmConversationSummary>> getPmConversations() async {
    if (!isLoggedIn) throw StateError('请先登录');

    final response = await _dio.get<String>(
      '/home.php',
      queryParameters: const {
        'mod': 'space',
        'do': 'pm',
        'mobile': 2,
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
        'mobile': 2,
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
      baseUrl: baseUrl,
    );
  }
  /// 获取消息中心未读汇总。
  ///
  /// 私信以真实私信列表中的 `span.kmnums` 为准。`checknewpm` 在用户打开
  /// 过私信列表后会清零，因此只在列表页请求失败时作为降级信号。
  /// 论坛通知仍读取普通论坛页的全局状态，好友申请读取真实待处理列表。
  Future<MessageUnreadSummary> getMessageUnreadSummary({
    List<PmConversationSummary>? pmConversations,
  }) async {
    if (!isLoggedIn) return const MessageUnreadSummary.empty();

    var conversations = pmConversations;
    if (conversations == null) {
      try {
        conversations = await getPmConversations();
      } catch (_) {
        // 私信列表失败时才回退到旧信号，不把网络失败误判成“全部已读”。
      }
    }

    UnreadBadgeInfo pm;
    if (conversations != null) {
      final unreadCount = conversations.where((item) => item.hasUnread).length;
      pm = unreadCount == 0
          ? const UnreadBadgeInfo.none()
          : UnreadBadgeInfo(count: unreadCount, hasUnread: true);
    } else {
      pm = const UnreadBadgeInfo.none();
      if (!pm.isVisible) {
        try {
          if (await checkNewPrivateMessage()) {
            pm = const UnreadBadgeInfo(count: null, hasUnread: true);
          }
        } catch (_) {}
      }
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
      // 论坛没有服务端通知未读标记，由 MessageBadgeService 对比通知 ID。
      notices: const UnreadBadgeInfo.none(),
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
    if (safePage > 1) {
      query['page'] = safePage;
      query['inajax'] = 1;
    }

    final response = await _dio.get<String>(
      '/home.php',
      queryParameters: query,
      options: Options(
        headers: {
          if (safePage > 1) 'X-Requested-With': 'XMLHttpRequest',
          'Referer': '$baseUrl/home.php?mod=space&do=notice'
              '&view=$view&mobile=2',
        },
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
}
