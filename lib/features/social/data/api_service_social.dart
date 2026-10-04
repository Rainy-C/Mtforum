part of '../../../services/api_service.dart';

extension ApiServiceSocialPart on ApiService {
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
      baseUrl: ApiService.baseUrl,
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
      queryParameters: {
        'mod': 'spacecp',
        'ac': 'friend',
        'op': 'request',
        'mobile': 2,
        '_t': DateTime.now().millisecondsSinceEpoch,
      },
      options: Options(
        headers: {
          'Referer':
              '${ApiService.baseUrl}/home.php?mod=space&do=friend&view=trace',
          'Cache-Control': 'no-cache',
        },
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );

    final primary = _userCenterParser.parseFriendRequests(
      response.data ?? '',
      baseUrl: ApiService.baseUrl,
    );
    if (primary.isNotEmpty) return primary;

    // 部分 Comiis 会让 mobile=2 首次请求只返回页面外壳；旧 AJAX 片段
    // 则直接包含申请列表。主请求为空时再探测一次，真实无申请时仍返回空。
    final fallback = await _dio.get<String>(
      '/home.php',
      queryParameters: {
        'mod': 'spacecp',
        'ac': 'friend',
        'op': 'request',
        'inajax': 1,
        '_t': DateTime.now().millisecondsSinceEpoch,
      },
      options: Options(
        headers: {
          'X-Requested-With': 'XMLHttpRequest',
          'Cache-Control': 'no-cache',
          'Referer':
              '${ApiService.baseUrl}/home.php?mod=space&do=friend&view=trace',
        },
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );
    return _userCenterParser.parseFriendRequests(
      fallback.data ?? '',
      baseUrl: ApiService.baseUrl,
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
            'Referer': '${ApiService.baseUrl}/home.php?mod=space&do=friend',
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
                  '${ApiService.baseUrl}/home.php?mod=follow&do=following&uid=$ownUid',
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
      baseUrl: ApiService.baseUrl,
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
          '${ApiService.baseUrl}/home.php?mod=spacecp&ac=poke&op=send&uid=$uid&handlekey=propokehk_$uid';

      final response = await _dio.post<String>(
        '/home.php',
        queryParameters: {
          'mod': 'spacecp',
          'ac': 'poke',
          'op': 'send',
          'uid': uid,
        },
        data: {
          'referer': '${ApiService.baseUrl}/home.php?mod=space&uid=$uid&do=profile',
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
    String? actionUrl, {
    String group = '1',
  }) async {
    if (!isLoggedIn || actionUrl == null || actionUrl.isEmpty) {
      return const OperationResult(
        success: false,
        message: '好友请求操作地址无效',
      );
    }

    try {
      final uri = Uri.parse(actionUrl.replaceAll('&amp;', '&'));
      final op = uri.queryParameters['op'] ?? '';
      final uid = uri.queryParameters['uid'] ?? '';

      if (op == 'ignore') {
        if (uid.isEmpty) {
          return const OperationResult(
            success: false,
            message: '好友申请 UID 无效',
          );
        }
        // 使用探测文档确认的最小参数，避免列表链接携带的 handlekey 被
        // 模板解释成“删除好友”弹窗而没有真正忽略待处理申请。
        final query = <String, dynamic>{
          'mod': 'spacecp',
          'ac': 'friend',
          'op': 'ignore',
          'uid': uid,
          'confirm': 1,
          'mobile': 2,
          '_t': DateTime.now().millisecondsSinceEpoch,
        };
        final response = await _dio.get<String>(
          '/home.php',
          queryParameters: query,
          options: Options(
            headers: {
              'X-Requested-With': 'XMLHttpRequest',
              'Cache-Control': 'no-cache',
              'Referer':
                  '${ApiService.baseUrl}/home.php?mod=spacecp&ac=friend&op=request&mobile=2',
            },
            responseType: ResponseType.plain,
            followRedirects: true,
          ),
        );
        final text = _extractAjaxMessage(response.data ?? '');
        final failed = text.contains('失败') ||
            text.contains('错误') ||
            text.contains('不存在');
        if (failed) {
          return OperationResult(
            success: false,
            message: text.isEmpty ? '忽略失败' : text,
          );
        }

        var remaining = await getFriendRequests();
        if (remaining.any((item) => item.uid == uid)) {
          // 某些 AJAX 模板只有带 handlekey 时才执行回调，再按页面原始
          // 参数补做一次，但最终仍以待处理列表是否消失作为成功标准。
          final retryQuery = <String, dynamic>{
            ...query,
            'handlekey': uri.queryParameters['handlekey'] ?? 'delfriendhk',
            'inajax': 1,
            '_t': DateTime.now().millisecondsSinceEpoch,
          };
          await _dio.get<String>(
            '/home.php',
            queryParameters: retryQuery,
            options: Options(
              headers: {
                'X-Requested-With': 'XMLHttpRequest',
                'Cache-Control': 'no-cache',
                'Referer':
                    '${ApiService.baseUrl}/home.php?mod=spacecp&ac=friend&op=request&mobile=2',
              },
              responseType: ResponseType.plain,
              followRedirects: true,
            ),
          );
          remaining = await getFriendRequests();
        }
        final success = !remaining.any((item) => item.uid == uid);
        return OperationResult(
          success: success,
          message: success ? '已忽略好友申请' : '论坛未移除该申请，请刷新后重试',
        );
      }

      if (op != 'add' || uid.isEmpty) {
        return const OperationResult(
          success: false,
          message: '不支持的好友请求操作',
        );
      }

      // “通过”链接只是批准表单入口，必须先 GET 取得真实 formhash，
      // 再 POST add2submit/group 才会真正通过好友请求。
      final formQuery = Map<String, dynamic>.from(uri.queryParameters)
        ..['mobile'] = 2;
      final formResponse = await _dio.get<String>(
        uri.path.isEmpty ? '/home.php' : uri.path,
        queryParameters: formQuery,
        options: Options(
          headers: {
            'Referer':
                '${ApiService.baseUrl}/home.php?mod=spacecp&ac=friend&op=request&mobile=2',
          },
          responseType: ResponseType.plain,
          followRedirects: true,
        ),
      );
      final formBody = formResponse.data ?? '';
      final document = html_parser.parse(formBody);
      final form = document.querySelector(
        'form[id^="addratifyform_"], '
        'form[action*="ac=friend"][action*="op=add"]',
      );
      if (form == null) {
        final text = _extractAjaxMessage(formBody);
        return OperationResult(
          success: false,
          message: text.isEmpty ? '未获取到好友批准表单' : text,
        );
      }

      final data = <String, dynamic>{};
      for (final input in form.querySelectorAll('input[name]')) {
        final name = input.attributes['name']?.trim() ?? '';
        if (name.isEmpty) continue;
        final type = (input.attributes['type'] ?? '').toLowerCase();
        if (type == 'submit' || type == 'button' || type == 'radio') continue;
        data[name] = input.attributes['value'] ?? '';
      }
      final safeGroup = RegExp(r'^[0-7]$').hasMatch(group) ? group : '1';
      data['add2submit'] = 'true';
      final formhash = data['formhash']?.toString() ?? '';
      data['formhash'] = formhash.isNotEmpty ? formhash : await getFormhash();
      data['group'] = safeGroup;
      data['from'] = data['from'] ?? '';
      data['referer'] = data['referer'] ?? '${ApiService.baseUrl}/./';
      data['add2submit_btn'] = 'true';

      final actionRaw = (form.attributes['action'] ?? actionUrl)
          .replaceAll('&amp;', '&');
      final actionUri = Uri.parse(ApiService.baseUrl).resolve(actionRaw);
      final response = await _dio.post<String>(
        actionUri.path.isEmpty ? '/home.php' : actionUri.path,
        queryParameters: actionUri.queryParameters,
        data: data,
        options: Options(
          headers: {
            'X-Requested-With': 'XMLHttpRequest',
            'Referer': Uri.parse(ApiService.baseUrl).resolveUri(uri).toString(),
          },
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.plain,
          followRedirects: true,
        ),
      );
      final body = response.data ?? '';
      final text = _extractAjaxMessage(body);
      final failed = text.contains('失败') ||
          text.contains('错误') ||
          text.contains('不存在');
      var success = false;
      if (!failed) {
        try {
          // 不依赖不同模板的成功文案，以真实待处理列表为准。
          final remaining = await getFriendRequests();
          success = !remaining.any((item) => item.uid == uid);
        } catch (_) {
          success = body.contains('succeedhandle') ||
              text.contains('批准') ||
              text.contains('操作成功');
        }
      }
      return OperationResult(
        success: success,
        message: success
            ? '已通过好友申请'
            : (text.isEmpty ? '通过好友申请失败' : text),
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
          'referer': '${ApiService.baseUrl}/home.php?mod=space&uid=$uid&do=profile',
          'addsubmit': 'true',
          'note': note,
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {
            'X-Requested-With': 'XMLHttpRequest',
            'Referer':
                '${ApiService.baseUrl}/home.php?mod=spacecp&ac=friend&op=add&uid=$uid&mobile=2',
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
                '${ApiService.baseUrl}/home.php?mod=space&uid=$uid&do=profile&mobile=2',
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
                '${ApiService.baseUrl}/home.php?mod=space&do=friend&view=blacklist&mobile=2',
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
          'Referer': '${ApiService.baseUrl}/home.php?mod=space&uid=$targetUid&do=profile',
        },
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );

    return _userCenterParser.parseWallComments(
      response.data ?? '',
      baseUrl: ApiService.baseUrl,
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
            'Referer': '${ApiService.baseUrl}/$wallPath',
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
            'Referer': '${ApiService.baseUrl}/$wallPath',
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
}
