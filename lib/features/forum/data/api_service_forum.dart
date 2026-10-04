part of '../../../services/api_service.dart';

extension _ApiServiceForumPart on ApiService {
  /// 解析论坛页面自身展示的在线人数（例如“总计 123 人在线”）。
  ///
  /// 官方客户端的 HomeParserUtils 使用：
  /// `总计\s*(\d+)\s*人在线`。
  /// 这里请求桌面版论坛首页并先取 DOM 文本，再使用同一规则解析；
  /// 避免移动模板不输出在线会员区域，导致首页人数一直为空。
  Future<int?> getForumOnlineCount() async {
    final pattern = RegExp(r'总计(?:\s|<[^>]+>)*(\d+)(?:\s|<[^>]+>)*人在线');
    final urls = <String>[
      '$baseUrl/forum.php',
      '$baseUrl/',
    ];

    for (final url in urls) {
      try {
        final response = await _desktopDio.get<String>(
          url,
          options: Options(
            responseType: ResponseType.plain,
            followRedirects: true,
          ),
        );
        final html = response.data ?? '';
        if (html.isEmpty) continue;

        // 官方正则针对页面可见文本。先去掉 HTML 标签后匹配，
        // 同时保留 raw HTML 回退，兼容模板直接输出纯文本的情况。
        final visibleText = html_parser.parse(html).text ?? '';
        final match = pattern.firstMatch(visibleText) ?? pattern.firstMatch(html);
        final value = int.tryParse(match?.group(1) ?? '');
        if (value != null) return value;
      } catch (_) {
        // 在线人数只用于标题展示，一个入口失败时继续尝试回退地址。
      }
    }
    return null;
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
              likeCount: thread.likeCount,
              thumbnails: thread.thumbnails,
              hasHiddenContent: thread.hasHiddenContent,
              typeId: thread.typeId,
              typeName: thread.typeName,
            ))
        .toList();
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

    final items = _accountParser.parseFavorites(
      response.data ?? '',
      baseUrl: baseUrl,
    );
    return _enrichFavoriteAuthors(items);
  }
  /// 使用收藏列表为每一项返回的专属删除地址取消收藏。
  ///
  /// Discuz 的删除动作依赖 favid/formhash，不能只拿 tid 调通用收藏接口。
  Future<bool> cancelFavoriteItem(FavoriteItem item) async {
    if (!isLoggedIn) return false;
    final rawUrl = item.deleteUrl?.trim() ?? '';
    final uri = Uri.tryParse(rawUrl);
    final forumHost = Uri.parse(baseUrl).host;
    if (uri == null ||
        rawUrl.isEmpty ||
        (uri.hasAuthority && uri.host != forumHost)) {
      return false;
    }

    try {
      final target = uri.hasAuthority
          ? uri
          : Uri.parse(baseUrl).resolveUri(uri);
      final dialogUri = target.replace(
        queryParameters: {
          ...target.queryParameters,
          'mobile': '2',
          'infloat': 'yes',
          'handlekey': 'favorite',
        },
      );
      final referer =
          '$baseUrl/home.php?mod=space&do=favorite&view=me&type=${item.type}';
      final dialog = await _dio.getUri<String>(
        dialogUri,
        options: Options(
          headers: {
            'X-Requested-With': 'XMLHttpRequest',
            'Referer': referer,
          },
          responseType: ResponseType.plain,
          followRedirects: true,
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      if ((dialog.statusCode ?? 0) < 200 ||
          (dialog.statusCode ?? 0) >= 400) {
        return false;
      }
      final hash = _extractFormhash(dialog.data ?? '') ?? await getFormhash();
      if (hash.isEmpty) return false;

      final submitUri = target.replace(
        queryParameters: {
          ...target.queryParameters,
          'mobile': '2',
        },
      );
      final response = await _dio.postUri<String>(
        submitUri,
        data: {
          'referer': '$baseUrl/./',
          'deletesubmit': 'true',
          'formhash': hash,
          'handlekey': 'comiis',
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {
            'X-Requested-With': 'XMLHttpRequest',
            'Referer': referer,
          },
          responseType: ResponseType.plain,
          followRedirects: true,
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      final status = response.statusCode ?? 0;
      final body = response.data ?? '';
      if (status < 200 || status >= 400) return false;
      if (body.contains('请先登录') ||
          body.contains('抱歉，您尚未登录') ||
          body.contains('无权进行当前操作') ||
          body.contains('非法请求')) {
        return false;
      }
      return !body.contains('favid=${item.favid}');
    } catch (_) {
      return false;
    }
  }
  Future<List<FavoriteItem>> _enrichFavoriteAuthors(
    List<FavoriteItem> items,
  ) async {
    final result = List<FavoriteItem>.from(items);
    final missingIndexes = <int>[
      for (var index = 0; index < result.length; index++)
        if (result[index].isThread &&
            ((result[index].thread?.authorName?.trim().isEmpty ?? true) ||
                (result[index].thread?.likeCount?.trim().isEmpty ?? true) ||
                (result[index].thread?.replyCount?.trim().isEmpty ?? true)))
          index,
    ];

    // 收藏页只有标题。按每批 3 个请求 PC 详情，一次补齐作者、点赞、
    // 回复和阅读，同时限制并发避免收藏较多时瞬间发出过多请求。
    for (var start = 0; start < missingIndexes.length; start += 3) {
      final end = (start + 3).clamp(0, missingIndexes.length).toInt();
      final batch = missingIndexes.sublist(start, end);
      final details = await Future.wait(
        batch.map((index) => _getFavoriteDetail(result[index].tid!)),
      );

      for (var offset = 0; offset < batch.length; offset++) {
        final index = batch[offset];
        final data = details[offset];
        if (data == null) continue;
        final detail = data.detail;
        final author = detail.posts.isEmpty
            ? null
            : detail.posts.firstWhere(
                (post) => post.isOp,
                orElse: () => detail.posts.first,
              );
        final item = result[index];
        final thread = item.thread ?? Thread(tid: item.tid!, title: item.title);
        result[index] = FavoriteItem(
          favid: item.favid,
          title: item.title,
          type: item.type,
          href: item.href,
          deleteUrl: item.deleteUrl,
          tid: item.tid,
          thread: thread.copyWith(
            authorUid: author?.authorUid,
            authorName: author?.authorName,
            avatarUrl: author?.avatarUrl,
            likeCount: detail.likeCount,
            replyCount: data.replyCount ?? detail.replyCount,
            viewCount: data.viewCount,
          ),
        );
      }
    }
    return result;
  }
  Future<_FavoriteDetailData?> _getFavoriteDetail(String tid) {
    return _favoriteDetailRequests.putIfAbsent(tid, () async {
      try {
        return await _getDesktopFavoriteDetail(tid);
      } catch (_) {
        return null;
      }
    });
  }
  Future<_FavoriteDetailData?> _getDesktopFavoriteDetail(String tid) async {
    try {
      // 独立 Dio 不挂 CookieManager：PC UA 且不带 mobile 参数，避免论坛
      // 已有移动模板 Cookie 让服务端继续返回不含阅读量的 mobile=2 页面。
      final cookie = <String>[
        if (_auth?.isNotEmpty == true) 'cQWy_2132_auth=$_auth',
        if (_saltkey?.isNotEmpty == true) 'cQWy_2132_saltkey=$_saltkey',
      ].join('; ');
      final response = await _desktopDio.get<String>(
        '$baseUrl/thread-$tid-1-1.html',
        options: Options(
          headers: {
            if (cookie.isNotEmpty) 'Cookie': cookie,
          },
          responseType: ResponseType.plain,
          followRedirects: true,
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      if ((response.statusCode ?? 0) < 200 ||
          (response.statusCode ?? 0) >= 400) {
        return null;
      }
      final body = response.data ?? '';
      final document = html_parser.parse(body);
      final reply = document
          .querySelector('div.bm_h.comiis_snvbt span.comiis_hfs > strong')
          ?.text
          .trim();
      final view = document
          .querySelector('div.bm_h.comiis_snvbt span.comiis_cks > strong')
          ?.text
          .trim();
      return _FavoriteDetailData(
        detail: _parser.parseThreadDetail(
          body,
          tid: tid,
          page: 1,
          baseUrl: baseUrl,
        ),
        replyCount:
            RegExp(r'^\d+$').hasMatch(reply ?? '') ? reply : null,
        viewCount: RegExp(r'^\d+$').hasMatch(view ?? '') ? view : null,
      );
    } catch (_) {
      return null;
    }
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
  String? buildAvatarUrl(String? uid) {
    if (uid == null || uid.isEmpty) return null;
    return '$baseUrl/uc_server/avatar.php?uid=$uid&size=middle';
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

/// 收藏详情页的中间聚合结果（列表页 + 桌面模板详情补充的统计值）。
class _FavoriteDetailData {
  final ThreadDetail detail;
  final String? replyCount;
  final String? viewCount;

  const _FavoriteDetailData({
    required this.detail,
    this.replyCount,
    this.viewCount,
  });
}
