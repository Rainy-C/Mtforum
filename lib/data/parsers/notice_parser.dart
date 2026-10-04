part of '../user_center_parser.dart';

extension _UserCenterParserNoticeParserPart on UserCenterParser {
  List<NoticeItem> parseNotices(
    String raw, {
    String baseUrl = 'https://bbs.binmt.cc',
  }) {
    return parseNoticePage(raw, baseUrl: baseUrl).items;
  }

  NoticePageData parseNoticePage(
    String raw, {
    String baseUrl = 'https://bbs.binmt.cc',
    int currentPage = 1,
  }) {
    final document = html_parser.parse(_unwrapCdata(raw));
    final result = <NoticeItem>[];

    var noticeNodes = document.querySelectorAll('.comiis_notice_list li');
    if (noticeNodes.isEmpty) {
      // 某些主题模板不会保留 comiis_notice_list 外层，仍以 ntc_body
      // 作为真正的通知项标记，避免误解析页面上的普通导航 li。
      noticeNodes = document
          .querySelectorAll('li')
          .where((node) => node.querySelector('.ntc_body') != null)
          .toList();
    }

    for (final item in noticeNodes) {
      final body = item.querySelector('.ntc_body');
      if (body == null) continue;

      final avatarLink = item.querySelector('a.notice_img');
      final avatar = avatarLink?.querySelector('img');
      final systemIcon = item.querySelector('.notice_imgs');
      final bodyLinks = body.querySelectorAll('a[href]');
      final firstLink = bodyLinks.isEmpty ? null : bodyLinks.first;

      final firstHref =
          (firstLink?.attributes['href'] ?? '').replaceAll('&amp;', '&');
      final firstIsUserLink = RegExp(
        r'(?:[?&]uid=\d+|space-uid-\d+)',
        caseSensitive: false,
      ).hasMatch(firstHref);
      var username = firstIsUserLink
          ? _sanitizeUsername(firstLink?.text ?? '')
          : '';
      final authorHref = avatarLink?.attributes['href'] ??
          (firstIsUserLink ? firstHref : '');
      final avatarSrc = avatar?.attributes['src'] ?? '';

      String uidFrom(String value) {
        final normalized = value.replaceAll('&amp;', '&');
        return RegExp(r'(?:^|[?&])uid=(\d+)')
                .firstMatch(normalized)
                ?.group(1) ??
            RegExp(r'space-uid-(\d+)', caseSensitive: false)
                .firstMatch(normalized)
                ?.group(1) ??
            '';
      }

      final uidFromAuthor = uidFrom(authorHref);
      final authorUid = uidFromAuthor.isNotEmpty
          ? uidFromAuthor
          : uidFrom(avatarSrc);

      html_dom.Element? targetLink;
      html_dom.Element? titleTarget;
      html_dom.Element? pidTarget;
      html_dom.Element? fallbackTarget;
      final noticeTargets = <html_dom.Element>[];

      for (final link in bodyLinks) {
        final href = (link.attributes['href'] ?? '').replaceAll('&amp;', '&');
        if (!_looksLikeNoticeTarget(href)) continue;

        noticeTargets.add(link);
        fallbackTarget ??= link;

        if (pidTarget == null &&
            RegExp(
              r'(?:^|[?&])pid=\d+',
              caseSensitive: false,
            ).hasMatch(href)) {
          pidTarget = link;
        }

        final label = _sanitizeVisibleText(link.text);
        if (titleTarget == null &&
            label.isNotEmpty &&
            label != '查看' &&
            label != '详情') {
          titleTarget = link;
        }
      }

      // “回复了我”类通知经常同时包含帖子标题链接和 goto=findpost 链接。
      // 优先保留带 pid 的链接用于精确定位，但标题仍从可读链接取，避免 UI 退化。
      targetLink = pidTarget ?? titleTarget ?? fallbackTarget;

      final targetHref =
          (targetLink?.attributes['href'] ?? '').replaceAll('&amp;', '&');
      var targetUrl = _absoluteUrl(targetHref, baseUrl);
      final targetTitleSource = titleTarget ?? targetLink;
      final targetTitleRaw =
          _sanitizeVisibleText(targetTitleSource?.text ?? '');
      final targetTitle = targetTitleRaw.isEmpty ||
              targetTitleRaw == '查看' ||
              targetTitleRaw == '详情'
          ? null
          : targetTitleRaw;

      String? tidFrom(String href) {
        final normalized = href.replaceAll('&amp;', '&');
        return RegExp(r'(?:^|[?&])(?:ptid|tid)=(\d+)')
                .firstMatch(normalized)
                ?.group(1) ??
            RegExp(r'thread-(\d+)-', caseSensitive: false)
                .firstMatch(normalized)
                ?.group(1);
      }

      String? pidFrom(String href) {
        final normalized = href.replaceAll('&amp;', '&');
        return RegExp(r'(?:^|[?&])pid=(\d+)')
            .firstMatch(normalized)
            ?.group(1);
      }

      var tid = tidFrom(targetHref);
      var pid = pidFrom(targetHref);

      // 某些模板把 tid 放在标题链接、pid 放在“查看”链接里。
      // 两者分别从全部候选链接补齐，避免选中其中一个后丢失另一个参数。
      if (tid == null || pid == null) {
        for (final link in noticeTargets) {
          final href =
              (link.attributes['href'] ?? '').replaceAll('&amp;', '&');
          tid ??= tidFrom(href);
          pid ??= pidFrom(href);
          if (tid != null && pid != null) break;
        }
      }

      // 少数通知模板把 findpost 参数藏在 onclick/data-* 或未被 DOM
      // 识别为链接的片段中，再从整条通知源码兜底提取。
      final itemSource = item.innerHtml.replaceAll('&amp;', '&');
      tid ??= tidFrom(itemSource);
      pid ??= pidFrom(itemSource);
      if (tid != null && pid != null) {
        // 标题链接往往只有 tid。统一构造 findpost 地址，确保预览请求和点击
        // 跳转都由论坛定位到 pid 所在页。
        targetUrl = _absoluteUrl(
          'forum.php?mod=redirect&goto=findpost&ptid=$tid&pid=$pid&mobile=2',
          baseUrl,
        );
      }

      final content = _sanitizeVisibleText(body.text);
      var actionText = content;
      if (username.isNotEmpty) {
        actionText = actionText.replaceFirst(username, '').trim();
      }
      if (targetTitle != null && targetTitle.isNotEmpty) {
        actionText = actionText.replaceFirst(targetTitle, '').trim();
      }
      actionText = actionText
          .replaceFirst(RegExp(r'^[：:]\s*'), '')
          .replaceAll(
            RegExp(
              r'(?:\s*[|丨]?\s*(?:查看|详情|回打招呼|忽略|屏蔽)\s*[|丨]?)+\s*$',
            ),
            '',
          )
          .replaceAll(RegExp(r'^[\s|丨·•]+|[\s|丨·•]+$'), '')
          .trim();
      if (actionText.isEmpty) actionText = content;

      final timeNode = item.querySelector('h2.f_d, .f_d');
      final time = _sanitizeVisibleText(timeNode?.text ?? '')
          .replaceAll('屏蔽', '')
          .replaceAll('忽略', '')
          .replaceAll(RegExp(r'^[\s|丨·•]+|[\s|丨·•]+$'), '')
          .trim();
      var ignoreLink = item.querySelector(
        'h2 a[href*="op=ignore"], a[href*="ac=common"][href*="op=ignore"]',
      );
      if (ignoreLink == null) {
        for (final link in item.querySelectorAll('a[href]')) {
          final label = _sanitizeVisibleText(
            '${link.text} ${link.attributes['title'] ?? ''}',
          );
          if (label.contains('忽略') || label.contains('屏蔽')) {
            ignoreLink = link;
            break;
          }
        }
      }
      final ignoreHref =
          (ignoreLink?.attributes['href'] ?? '').replaceAll('&amp;', '&');
      final ignoreUrl = _absoluteUrl(ignoreHref, baseUrl);
      final ignoreUri = Uri.tryParse(ignoreHref);
      final type = ignoreUri?.queryParameters['type'] ?? '';
      final idAttr = ignoreLink?.attributes['id'] ?? '';
      final noticeId = RegExp(r'(?:^|_)note_(\d+)$', caseSensitive: false)
              .firstMatch(idAttr)
              ?.group(1) ??
          RegExp(r'(\d+)$').firstMatch(idAttr)?.group(1) ??
          '';

      final isSystem = systemIcon != null ||
          type == 'system' ||
          (authorUid.isEmpty && avatarLink == null);
      if (username.isEmpty && authorUid.isNotEmpty && !isSystem) {
        username = 'UID $authorUid';
      }

      result.add(
        NoticeItem(
          id: noticeId,
          type: type,
          authorUid: authorUid,
          username: username,
          avatarUrl: _absoluteUrl(avatarSrc, baseUrl),
          content: content,
          actionText: actionText,
          time: time,
          targetTitle: targetTitle,
          targetUrl: targetUrl,
          tid: tid,
          pid: pid,
          ignoreUrl: ignoreUrl,
          isSystem: isSystem,
          // 通知 HTML 没有可靠的单项已读标记，新提醒由客户端对比通知 ID。
          isUnread: false,
        ),
      );
    }

    var hasMore = false;
    var totalPages = currentPage < 1 ? 1 : currentPage;

    // Comiis 通知页的移动模板主要用 #dumppage <select>
    // 表示分页，不一定输出 .comiis_page 的下一页链接。
    // 旧解析只查链接，因此第 1 页会被误判为最后一页。
    final pageOptions = document.querySelectorAll('#dumppage option');
    if (pageOptions.isNotEmpty) {
      var totalPage = pageOptions.length;
      for (final option in pageOptions) {
        final value = (option.attributes['value'] ?? '').replaceAll('&amp;', '&');
        final valueUri = Uri.tryParse(value);
        final queryPage =
            int.tryParse(valueUri?.queryParameters['page'] ?? '');
        int? textPage;
        for (final match in RegExp(r'\d+').allMatches(option.text)) {
          final candidate = int.tryParse(match.group(0) ?? '');
          if (candidate != null && candidate > (textPage ?? 0)) {
            textPage = candidate;
          }
        }
        final parsedPage = queryPage ?? textPage;
        if (parsedPage != null && parsedPage > totalPage) {
          totalPage = parsedPage;
        }
      }
      totalPages = totalPage > totalPages ? totalPage : totalPages;
      hasMore = currentPage < totalPage;
    }

    for (final link in document.querySelectorAll(
      '.comiis_page a[href*="page="], .pg a[href*="page="], '
      'a.nxt[href], a[rel="next"][href]',
    )) {
      final href = (link.attributes['href'] ?? '').replaceAll('&amp;', '&');
      final uri = Uri.tryParse(href);
      final page = int.tryParse(uri?.queryParameters['page'] ?? '') ??
          int.tryParse(
            RegExp(r'(?:[?&]|&amp;)page=(\d+)')
                    .firstMatch(href)
                    ?.group(1) ??
                '',
          );
      if (page != null && page > totalPages) totalPages = page;
      if ((page != null && page > currentPage) ||
          link.classes.contains('nxt') ||
          link.attributes['rel'] == 'next') {
        hasMore = true;
        if (totalPages <= currentPage) totalPages = currentPage + 1;
        break;
      }
    }

    return NoticePageData(
      items: result,
      hasMore: hasMore,
      totalPages: totalPages,
    );
  }


  /// 从不会清空提醒状态的普通论坛页面中提取 Discuz 全局未读标记。
  ///
  /// 标准 Discuz 模板会通过 `#pm_ntc` 的 `new` class 表示新私信，
  /// 通过 `#myprompt` 展示 `newprompt`。部分 Comiis 模板会直接输出数字，
  /// 也有模板只输出“new/unread”状态；后者保留为 count=null。

  bool _looksLikeNoticeTarget(String href) {
    if (href.isEmpty) return false;
    final value = href.toLowerCase();
    return value.contains('ptid=') ||
        value.contains('pid=') ||
        value.contains('tid=') ||
        value.contains('thread-') ||
        value.contains('ac=usergroup') ||
        value.contains('op=usergroup');
  }
}
