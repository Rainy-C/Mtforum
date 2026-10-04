part of '../forum_parser.dart';

extension ForumParserThreadListParserPart on ForumParser {
  String unwrapAjax(String body) {
    final match = RegExp(r'<!\[CDATA\[(.*?)\]\]>', dotAll: true)
        .firstMatch(body);
    return match?.group(1) ?? body;
  }

  List<Thread> parseThreadList(String body, {required String baseUrl}) {
    final html = unwrapAjax(body);
    final document = html_parser.parse(html);
    final items = document.querySelectorAll('li.forumlist_li');

    final result = <Thread>[];
    for (final el in items) {
      html_dom.Element? titleLink = el.querySelector(
        '.mmlist_li_box h2 a[href*="thread-"], '
        'h2 a[href*="thread-"], '
        '.mmlist_li_box .list_body a[href*="thread-"], '
        '.mmlist_li_box > a[href*="thread-"]',
      );

      // 无标题帖、动态式帖子以及部分登录模板不会输出标题 h2。
      // 此时不再依赖 DOM 层级，直接从卡片内寻找第一个带可读文本的
      // 主题链接；搜索与首页因此使用完全一致的兜底规则。
      if (titleLink == null) {
        for (final anchor in el.querySelectorAll('a[href]')) {
          final candidate = anchor.attributes['href'] ?? '';
          final isThreadLink =
              RegExp(r'thread-\d+-?').hasMatch(candidate) ||
                  RegExp(r'(?:[?&]|&amp;)tid=\d+').hasMatch(candidate);
          if (isThreadLink && _cleanInline(anchor.text).isNotEmpty) {
            titleLink = anchor;
            break;
          }
        }
      }
      final href = titleLink?.attributes['href'] ?? '';
      final tid = RegExp(r'thread-(\d+)-?').firstMatch(href)?.group(1) ??
          RegExp(r'(?:[?&]|&amp;)tid=(\d+)').firstMatch(href)?.group(1);
      if (tid == null || tid.isEmpty) continue;

      final authorEl = el.querySelector('.top_user');
      final authorHref = authorEl?.attributes['href'] ?? '';
      final authorUid =
          RegExp(r'uid=(\d+)').firstMatch(authorHref)?.group(1);

      final forumEl = el.querySelector('a[href*="forum-"]');
      final forumHref = forumEl?.attributes['href'] ?? '';
      final forumId = RegExp(r'forum-(\d+)').firstMatch(forumHref)?.group(1);

      final typeEl = el.querySelector('a[href*="typeid="]');
      final typeHref = typeEl?.attributes['href'] ?? '';
      final typeId = RegExp(r'(?:[?&]|&amp;)typeid=(\d+)')
          .firstMatch(typeHref)
          ?.group(1);
      String? typeName = _nullableText(typeEl?.text);
      if (typeId == '59') {
        typeName = '求助问答';
      } else if (typeId == '58') {
        typeName = '已解决';
      }

      // Comiis 的完整统计区真实结构是
      // .comiis_xznalist_bottom .comiis_tm，通常顺序为：点赞 / 回复 / 浏览。
      // 部分页面会把点赞拆成 .num-all_{tid}，或只留下带中文标签的文本。
      // 这里先读结构化节点，再回退标签文本，保证首页、板块、搜索使用
      // 同一个 ThreadCard 时都能拿到同一组三项统计。
      final statNodes = el.querySelectorAll(
        '.comiis_xznalist_bottom .comiis_tm, '
        '.comiis_znalist_bottom .comiis_tm',
      );
      final statValues = statNodes
          .map((node) => _extractStatValue(node.text))
          .whereType<String>()
          .toList();

      final statText = <String>[
        el.querySelector('.comiis_xznalist_bottom')?.text ?? '',
        el.querySelector('.comiis_znalist_bottom')?.text ?? '',
        el.querySelector('.forumlist_li_info')?.text ?? '',
        el.querySelector('.comiis_list_bottom')?.text ?? '',
        el.querySelector('.comiis_forumlist_bottom')?.text ?? '',
        el.querySelector('.list_info')?.text ?? '',
        el.text,
      ].join(' ');

      String? likeCount = _extractStatValue(
        el.querySelector('.num-all_$tid')?.text,
      );
      likeCount ??= _extractThreadCount(
        statText,
        labels: const ['点赞', '推荐'],
      );
      String? replyCount = _extractThreadCount(
        statText,
        labels: const ['评论', '回复'],
      );
      String? viewCount = _extractThreadCount(
        statText,
        labels: const ['阅读', '浏览', '查看'],
      );

      if (statValues.length >= 3) {
        likeCount ??= statValues[0];
        replyCount ??= statValues[1];
        viewCount ??= statValues[2];
      } else if (statValues.length >= 2 && likeCount != null) {
        // 有些模板把点赞独立放在 .num-all_{tid}，底部只保留回复/浏览。
        replyCount ??= statValues[0];
        viewCount ??= statValues[1];
      }

      String? avatarUrl;
      final avatarEl = el.querySelector('img.top_tximg, .top_tximg img');
      avatarUrl = _absoluteUrl(
        avatarEl?.attributes['src'] ?? avatarEl?.attributes['data-src'],
        baseUrl,
      );

      final timeEl = el.querySelector('.forumlist_li_time .f_d, span.f_d');

      // 缩略图：取前三张（comiis_pyqlist_img 容器内的图片）。
      final thumbnails = <String>[];
      for (final img in el.querySelectorAll(
        '.comiis_pyqlist_img img, .comiis_pyqlist_imgs img, .list_img img, .comiis_list_img img',
      )) {
        final src = img.attributes['file'] ??
            img.attributes['data-src'] ??
            img.attributes['data-original'] ??
            img.attributes['src'];
        final url = _absoluteUrl(src, baseUrl);
        if (url != null &&
            !SmileyCatalog.isForumSmileyUrl(url) &&
            !url.contains('/static/image/') &&
            !thumbnails.contains(url)) {
          thumbnails.add(url);
          if (thumbnails.length >= 3) break;
        }
      }

      // 隐藏内容标记：兼容文字提示以及模板中 showhide/replyhide
      // 等隐藏区域标识。列表页只做“存在隐藏内容”的标记，不读取隐藏正文。
      final itemText = _cleanInline(el.text);
      final itemHtml = el.innerHtml.toLowerCase();
      final hasHidden = itemText.contains('本内容被作者隐藏') ||
          itemText.contains('回复后可见') ||
          itemText.contains('回复可见') ||
          itemText.contains('查看隐藏内容') ||
          itemText.contains('隐藏内容') ||
          itemHtml.contains('showhide') ||
          itemHtml.contains('replyhide') ||
          itemHtml.contains('hidecontent');

      result.add(Thread(
        tid: tid,
        title: _cleanInline(titleLink?.text ?? '').isEmpty
            ? '未知标题'
            : _cleanInline(titleLink!.text),
        authorUid: authorUid,
        authorName: _nullableText(authorEl?.text),
        avatarUrl: avatarUrl,
        forumName: _nullableText(
          (forumEl?.text ?? '')
              .replaceFirst('来自', '')
              .replaceAll(
                RegExp(r'[\uE000-\uF8FF\uFFFD\u25A1]'),
                '',
              )
              .trim(),
        ),
        forumId: forumId,
        replyCount: replyCount,
        viewCount: viewCount,
        likeCount: likeCount,
        lastReplyTime: _nullableText(timeEl?.text),
        excerpt: _cleanThreadExcerpt(el.querySelector('.list_body a')?.text),
        thumbnails: thumbnails,
        hasHiddenContent: hasHidden,
        typeId: typeId,
        typeName: typeName,
      ));
    }

    return result;
  }
}
