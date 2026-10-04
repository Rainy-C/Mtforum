part of '../forum_parser.dart';

extension ForumParserThreadDetailParserPart on ForumParser {
  ThreadDetail parseThreadDetail(
    String body, {
    required String tid,
    required int page,
    required String baseUrl,
  }) {
    final document = html_parser.parse(body);
    var title = _cleanInline(document.querySelector('title')?.text ?? '');
    title = title.replaceAll(RegExp(r'\s*-\s*MT论坛.*$'), '').trim();
    if (title.isEmpty) title = '未知标题';

    final formhash = _extractFormhash(body) ?? '';
    final noticeauthor = RegExp(
          r'''noticeauthor[^>]*value\s*=\s*['"]([^'"]+)['"]''',
          caseSensitive: false,
        ).firstMatch(body)?.group(1) ??
        '';
    final fid = RegExp(
          r'forum-viewforum-fid-(\d+)',
          caseSensitive: false,
        ).firstMatch(body)?.group(1) ??
        '';

    final currentUid = RegExp(
          r'''discuz_uid\s*=\s*['"]?(\d+)''',
          caseSensitive: false,
        ).firstMatch(body)?.group(1) ??
        '';

    final posts = _parsePostsFromRawHtml(
      body,
      page: page,
      baseUrl: baseUrl,
    );
    final likeCount = _extractStatValue(
      document
          .querySelector(
            '#comiis_recommend_num, em.comiis_recommend_num',
          )
          ?.text,
    );
    final replyCount = _extractStatValue(
      document
          .querySelector('a.comiis_position_key span.comiis_kmvnum')
          ?.text,
    );

    return ThreadDetail(
      tid: tid,
      title: title,
      posts: posts,
      replyCount: replyCount,
      likeCount: likeCount,
      formhash: formhash,
      noticeauthor: noticeauthor,
      fid: fid,
      page: page,
      currentUid: currentUid,
    );
  }

  List<Post> _parsePostsFromRawHtml(
    String body, {
    required int page,
    required String baseUrl,
  }) {
    // Check.md: 每个楼层由 <div id="pidXXX"> 开始。
    final pidPattern = RegExp(
      r'''<div\b[^>]*\bid\s*=\s*['"]pid(\d+)['"][^>]*>''',
      caseSensitive: false,
    );
    final starts = pidPattern.allMatches(body).toList();

    // 兼容属性顺序/标签名出现变化，但仍严格要求 id=pid数字。
    final fallbackStarts = starts.isNotEmpty
        ? starts
        : RegExp(
            r'''<[^>]+\bid\s*=\s*['"]pid(\d+)['"][^>]*>''',
            caseSensitive: false,
          ).allMatches(body).toList();

    final posts = <Post>[];
    final seenPids = <String>{};

    for (var i = 0; i < fallbackStarts.length; i++) {
      final pid = fallbackStarts[i].group(1)!;
      if (!seenPids.add(pid)) continue;

      final start = fallbackStarts[i].start;
      var end = body.length;
      for (var j = i + 1; j < fallbackStarts.length; j++) {
        if (fallbackStarts[j].group(1) != pid) {
          end = fallbackStarts[j].start;
          break;
        }
      }
      if (end <= start) continue;

      final block = body.substring(start, end);
      final fragment = html_parser.parseFragment(block);

      final authorEl = fragment.querySelector('.top_user');
      final authorHref = authorEl?.attributes['href'] ?? '';
      final authorUid =
          RegExp(r'uid=(\d+)').firstMatch(authorHref)?.group(1);

      final avatarEl = fragment.querySelector(
        'img.top_tximg, .top_tximg img, .top_tximg',
      );
      final avatarUrl = _absoluteUrl(
        avatarEl?.attributes['src'] ?? avatarEl?.attributes['data-src'],
        baseUrl,
      );

      final rawMessage = _extractMessageRegion(block);
      final parsedMessage = _parseMessageRegion(rawMessage, baseUrl: baseUrl);

      // 真实 Comiis 页面会把部分帖子图片放在正文容器之外，例如：
      // <ul class="comiis_img_list"><img ...></ul>。
      // _extractMessageRegion() 只保留正文区，因此必须再从完整 pid 楼层块
      // 补抓一次，而不是拿列表页缩略图冒充正文图片。
      final postImages = <String>[...parsedMessage.images];
      for (final image in _extractContentImagesFromFloor(block, baseUrl)) {
        if (!postImages.contains(image)) postImages.add(image);
      }

      final isOp = page == 1 && posts.isEmpty;
      final floorText = _cleanInline(
        fragment.querySelector('.f_d.y')?.text ?? '',
      );
      final explicitFloor =
          RegExp(r'(\d+)\s*#').firstMatch(floorText)?.group(1);
      final floor = explicitFloor ??
          (isOp ? '1' : '${(page - 1) * 10 + posts.length + 1}');

      final replyRelation = _extractReplyRelation(rawMessage);
      String? replyToName = replyRelation.name;
      if ((replyToName == null || replyToName.isEmpty) &&
          replyRelation.pid != null) {
        for (final previous in posts.reversed) {
          if (previous.pid == replyRelation.pid) {
            replyToName = previous.authorName;
            break;
          }
        }
      }

      posts.add(Post(
        pid: pid,
        authorUid: authorUid,
        authorName: _nullableText(authorEl?.text),
        authorLevel: _nullableText(fragment.querySelector('.top_lev')?.text),
        avatarUrl: avatarUrl,
        content: parsedMessage.text,
        floor: floor,
        postTime: _extractPostTime(block),
        lastEditTime: parsedMessage.lastEditTime,
        lastEditor: parsedMessage.lastEditor,
        isOp: isOp,
        images: postImages,
        richContent: parsedMessage.contents,
        repquotePid: replyRelation.pid,
        replyToName: replyToName,
        replyToTime: replyRelation.time,
        replyQuoteText: replyRelation.quotedText,
        hiddenHint: parsedMessage.hiddenHint,
        page: page,
      ));
    }

    return posts;
  }

  /// 从“单楼层原始 HTML”中截出正文区域。
  ///
  /// 不依赖 </div> 配对，因为 Comiis 模板的嵌套可能被 HTML parser 修复。
  /// 起点严格使用 comiis_message_table，终点使用该楼层后续固定区域。

  /// 从“单楼层原始 HTML”中截出正文区域。
  ///
  /// 不依赖 </div> 配对，因为 Comiis 模板的嵌套可能被 HTML parser 修复。
  /// 起点严格使用 comiis_message_table，终点使用该楼层后续固定区域。
  String _extractMessageRegion(String block) {
    final open = RegExp(
      r'''<[^>]+class\s*=\s*['"][^'"]*\bcomiis_message_table\b[^'"]*['"][^>]*>''',
      caseSensitive: false,
    ).firstMatch(block);
    if (open == null) return '';

    var end = block.length;
    final tail = block.substring(open.end);

    final stopPatterns = <RegExp>[
      RegExp(
        r'''<[^>]+class\s*=\s*['"][^'"]*\bcomiis_rate\b''',
        caseSensitive: false,
      ),
      RegExp(
        r'''<[^>]+class\s*=\s*['"][^'"]*\bcomiis_postli_bottom\b''',
        caseSensitive: false,
      ),
      RegExp(
        r'''<a\b[^>]*href\s*=\s*['"][^'"]*action=reply[^'"]*repquote=''',
        caseSensitive: false,
      ),
    ];

    for (final pattern in stopPatterns) {
      final match = pattern.firstMatch(tail);
      if (match != null) {
        final absolute = open.end + match.start;
        if (absolute < end) end = absolute;
      }
    }

    return block.substring(open.start, end);
  }

  _ParsedMessage _parseMessageRegion(
    String raw, {
    required String baseUrl,
  }) {
    if (raw.isEmpty) {
      return const _ParsedMessage(text: '');
    }

    final fragment = html_parser.parseFragment(raw);
    final message = fragment.querySelector('.comiis_message_table') ??
        fragment.querySelector('[class*="comiis_message_table"]') ??
        fragment.querySelector('.comiis_message') ??
        fragment.querySelector('[class*="comiis_message"]') ??
        fragment.querySelector('.t_f') ??
        fragment.querySelector('[id^="postmessage"]');

    if (message == null) {
      // 最后回退：取整个片段的纯文本，避免正文完全空白。
    // 最后回退：取整个片段的纯文本，避免正文完全空白。
      final fallbackText = _stripHtmlFallback(raw);
      final anyText = fallbackText.isNotEmpty
          ? fallbackText
          : _cleanMultiline(fragment.text ?? '');
      return _ParsedMessage(
        text: anyText,
        images: _extractImagesFromRaw(raw, baseUrl),
        contents: _promoteCommandSnippets(
          _parseBbCodeText(
            anyText,
            baseUrl: baseUrl,
          ),
        ),
      );
    }

    final images = <String>[];
    for (final image in message.querySelectorAll('.comiis_postimg img, img')) {
      final candidate = HtmlText.imageSourceOf(image);
      final normalized = _absoluteUrl(candidate, baseUrl);
      if (normalized == null ||
          SmileyCatalog.isForumSmileyUrl(normalized)) {
        continue;
      }

      if (_isPostContentImage(normalized, image) &&
          !images.contains(normalized)) {
        images.add(normalized);
      }
    }

    // Comiis/Discuz 部分模板会把附件图片节点放到正文容器之外，或者只把
    // 真正的大图地址写在 zoomfile / data-original 上。列表页仍能拿到预览图，
    // 但详情页只扫描 comiis_message_table 就会出现“外显有图，点进去没图”。
    // 因此先从正文截取片段补抓一次；完整 pid 楼层中的正文外图片会在
    // _parsePosts() 中再补抓，避免这里误把非正文区域全部纳入富文本解析。
    for (final image in _extractContentImagesFromFloor(raw, baseUrl)) {
      if (!images.contains(image)) {
        images.add(image);
      }
    }

    String? hiddenHint;
    // Discuz/Comiis 的“回复可见”提示并不总是放在 .comiis_quote。
    // 不同主题会使用 showhide / replyhide / hidecontent / locked 等容器。
    // 只移除明确属于“隐藏提示”的节点；若用户已经有权限看到真实隐藏正文，
    // 容器内容会继续交给富文本解析器渲染，避免误删真实内容。
    for (final node in message.querySelectorAll('*').toList()) {
      final classes = node.classes
          .map((value) => value.toLowerCase())
          .toList(growable: false);
      final mayBeHiddenContainer = classes.any(
        (value) =>
            value == 'comiis_quote' ||
            value.contains('showhide') ||
            value.contains('replyhide') ||
            value.contains('hidecontent') ||
            value == 'locked' ||
            value.contains('hide_notice'),
      );
      if (!mayBeHiddenContainer) {
        continue;
      }

      final text = _cleanInline(node.text);
      if (_isHiddenPrompt(text)) {
        hiddenHint ??= text;
        node.remove();
      }
    }

    String? lastEditTime;
    String? lastEditor;
    for (final node in message.querySelectorAll('i.pstatus').toList()) {
      final text = _cleanInline(node.text);
      final match = RegExp(
        r'本帖最后由\s+(.+?)\s+于\s+'
        r'(\d{4}-\d{1,2}-\d{1,2}\s+\d{1,2}:\d{2}(?::\d{2})?)'
        r'\s+编辑',
      ).firstMatch(text);
      if (match != null && lastEditTime == null) {
        lastEditor = match.group(1)?.trim();
        lastEditTime = match.group(2)?.trim();
      }
      // pstatus 位于正文容器内，提取后必须移除，
      // 避免“本帖最后由…编辑”混入帖子正文。
      node.remove();
    }

    for (final node in message.querySelectorAll('script, style').toList()) {
      node.remove();
    }

    final contents = _parseRichContent(
      message,
      baseUrl: baseUrl,
    );

    // 部分移动模板把普通附件列表放在 comiis_message_table 之后。
    // 与图片相同，再从当前楼层范围补抓一次，并按 URL 去重。
    final attachmentUrls = contents
        .where((item) => item.type == PostContentType.attachment)
        .map((item) => item.url)
        .whereType<String>()
        .toSet();
    for (final attachment in _extractAttachmentsFromFloor(raw, baseUrl)) {
      if (attachment.url == null || !attachmentUrls.contains(attachment.url)) {
        contents.add(attachment);
        if (attachment.url != null) {
          attachmentUrls.add(attachment.url!);
        }
      }
    }

    var cleanedHtml = message.innerHtml
        .replaceAll(
          RegExp(
            r'<br\s*/?>[ \t]*(?:\r?\n)?',
            caseSensitive: false,
          ),
          '\n',
        )
        .replaceAll(
          RegExp(
            r'</(?:div|p|li|ol|ul|blockquote|pre)>[ \t]*(?:\r?\n)?',
            caseSensitive: false,
          ),
          '\n',
        )
        .replaceAll(RegExp(r'<[^>]+>'), ' ');

    var text = _cleanMultiline(_stripBbCodeRemains(cleanedHtml));
    if (text.isEmpty) {
      text = _stripHtmlFallback(raw);
    }

    return _ParsedMessage(
      text: text,
      hiddenHint: hiddenHint,
      lastEditTime: lastEditTime,
      lastEditor: lastEditor,
      images: images,
      contents: contents,
    );
  }

  /// 将 Discuz / Comiis 已经渲染后的 HTML 转成 App 内富文本模型。
  ///
  /// 同一个解析器用于楼主和所有评论，所以评论中的代码、引用、链接、媒体
  /// 也会按相同规则渲染。

  _ReplyRelation _extractReplyRelation(String rawMessage) {
    if (rawMessage.trim().isEmpty) {
      return const _ReplyRelation();
    }

    final fragment = html_parser.parseFragment(rawMessage);
    final candidates = <html_dom.Element>[
      ...fragment.querySelectorAll('.comiis_quote'),
      ...fragment.querySelectorAll('blockquote'),
      ...fragment.querySelectorAll('.quote'),
    ];

    for (final quote in candidates) {
      final quoteText = _cleanInline(quote.text);
      if (quoteText.isEmpty) continue;

      String? pid;
      for (final anchor in quote.querySelectorAll('a[href]')) {
        final href = (anchor.attributes['href'] ?? '')
            .replaceAll('&amp;', '&');
        if (!href.contains('goto=findpost') && !href.contains('pid=')) {
          continue;
        }
        final match = RegExp(r'(?:[?&]|^)pid=(\d+)').firstMatch(href);
        if (match != null) {
          pid = match.group(1);
          break;
        }
      }

      String? name;
      String? time;
      String? quotedText;

      // 真实移动模板把“用户名 发表于 时间”和被引用正文分别放在
      // font[color=#999999] 中，不提供父 PID。保留这两个字段，交给评论
      // 窗口在已加载楼层内做唯一匹配；匹配不唯一时继续平铺。
      final quoteFonts = quote.querySelectorAll('font');
      var headerIndex = -1;
      for (var index = 0; index < quoteFonts.length; index++) {
        final value = _cleanInline(quoteFonts[index].text);
        final header = RegExp(r'^(.+?)\s+发表于\s+(.+)$').firstMatch(value);
        if (header == null) continue;
        name = _cleanInline(header.group(1) ?? '');
        time = _cleanInline(header.group(2) ?? '');
        headerIndex = index;
        break;
      }
      if (headerIndex >= 0 && headerIndex + 1 < quoteFonts.length) {
        final values = <String>[];
        for (var index = headerIndex + 1;
            index < quoteFonts.length;
            index++) {
          final value = _cleanMultiline(quoteFonts[index].text);
          if (value.isNotEmpty) values.add(value);
        }
        final value = _cleanMultiline(values.join('\n'));
        if (value.isNotEmpty) quotedText = value;
      }

      final patterns = <RegExp>[
        RegExp(r'(?:^|\s)回复\s+(.+?)\s+(?:的帖子|发表于)'),
        RegExp(r'(?:^|\s)([^\s].*?)\s+发表于\s+\d{4}[-/.年]'),
        RegExp(r'(?:^|\s)([^\s].*?)\s+发表于\s+(?:今天|昨天|前天|\d+\s*小时前)'),
      ];
      for (final pattern in patterns) {
        if (name?.isNotEmpty == true) break;
        final match = pattern.firstMatch(quoteText);
        if (match != null) {
          final value = _cleanInline(match.group(1) ?? '');
          if (value.isNotEmpty &&
              !value.contains('本帖隐藏') &&
              !value.contains('隐藏的内容')) {
            name = value;
            break;
          }
        }
      }

      if (quotedText == null && name?.isNotEmpty == true) {
        var remainder = quoteText;
        remainder = remainder.replaceFirst(RegExp(r'^\s*回复\s*'), '');
        final headerText = time?.isNotEmpty == true
            ? '$name 发表于 $time'
            : null;
        if (headerText != null) {
          remainder = remainder.replaceFirst(headerText, '');
        }
        remainder = _cleanMultiline(remainder);
        if (remainder.isNotEmpty) quotedText = remainder;
      }

      if (pid != null || name != null) {
        return _ReplyRelation(
          pid: pid,
          name: name,
          time: time,
          quotedText: quotedText,
        );
      }
    }

    // 桌面/部分模板会把被回复楼层写成 redirect/findpost 链接，
    // 即使 HTML parser 修复了 DOM，也可以从原始正文中回退提取父 PID。
    final rawPid = RegExp(
      r'''(?:goto=findpost[^"'<>]*?[?&]|[?&])pid=(\d+)''',
      caseSensitive: false,
    ).firstMatch(rawMessage)?.group(1);

    final plain = _cleanInline(fragment.text ?? '');
    String? rawName;
    for (final pattern in <RegExp>[
      RegExp(r'(?:^|\s)回复\s+(.+?)\s+(?:的帖子|发表于)'),
      RegExp(r'(?:^|\s)([^\s].*?)\s+发表于\s+\d{4}[-/.年]'),
    ]) {
      final match = pattern.firstMatch(plain);
      if (match != null) {
        final value = _cleanInline(match.group(1) ?? '');
        if (value.isNotEmpty) {
          rawName = value;
          break;
        }
      }
    }

    return _ReplyRelation(pid: rawPid, name: rawName);
  }

  String? _extractPostTime(String block) {
    // Comiis 同一个帖子页面里存在两套真实时间结构：
    // 1. 楼主/普通楼层头部：.comiis_postli_time .kmtime
    // 2. 部分回复楼层底部：.comiis_postli_times .comiis_tm
    //
    // 先在完整 pid 楼层块里按 DOM 精确查找；如果移动模板的残缺标签
    // 被 HTML parser 修复后导致节点位置变化，再从原始楼层 HTML 直接
    // 提取 span 内容兜底。这样时间解析不再依赖正文区域的 DOM 完整性。
    final fragment = html_parser.parseFragment(block);
    final candidates = <html_dom.Element?>[
      fragment.querySelector('.comiis_postli_time .kmtime'),
      fragment.querySelector('.kmtime'),
      fragment.querySelector('.comiis_postli_times span.comiis_tm'),
      fragment.querySelector('.comiis_postli_times .comiis_tm'),
    ];

    for (final element in candidates) {
      if (element == null) continue;
      final timeText = _cleanPostTimeText(
        element.text,
        localityText: element.querySelector('.comiis_iplocality')?.text,
      );
      if (timeText != null) return timeText;
    }

    // 原始 HTML 兜底。真实抓包中楼主是 span.kmtime，评论是
    // span.f_d.comiis_tm；只匹配 span，避免命中用户资料区的
    // p.comiis_tm 等无关节点。
    final rawPatterns = <RegExp>[
      RegExp(
        r'''<span\b[^>]*class\s*=\s*['"][^'"]*\bkmtime\b[^'"]*['"][^>]*>([\s\S]*?)</span>''',
        caseSensitive: false,
      ),
      RegExp(
        r'''<span\b[^>]*class\s*=\s*['"][^'"]*\bcomiis_tm\b[^'"]*['"][^>]*>([\s\S]*?)</span>''',
        caseSensitive: false,
      ),
    ];

    for (final pattern in rawPatterns) {
      final inner = pattern.firstMatch(block)?.group(1);
      if (inner == null || inner.isEmpty) continue;
      final innerFragment = html_parser.parseFragment(inner);
      final timeText = _cleanPostTimeText(
        innerFragment.text ?? '',
        localityText:
            innerFragment.querySelector('.comiis_iplocality')?.text,
      );
      if (timeText != null) return timeText;
    }

    return null;
  }

  String? _cleanPostTimeText(
    String value, {
    String? localityText,
  }) {
    var timeText = _cleanInline(value);
    final locality = _cleanInline(localityText ?? '');
    if (locality.isNotEmpty) {
      timeText = _cleanInline(timeText.replaceFirst(locality, ''));
    }

    // 再兜底清理模板可能扁平化进来的 IP 归属地文本。
    timeText = _cleanInline(
      timeText.replaceFirst(RegExp(r'\s*来自\s+\S+\s*$'), ''),
    );
    return timeText.isEmpty ? null : timeText;
  }

  String? _extractThreadCount(
    String text, {
    required List<String> labels,
  }) {
    final normalized = _cleanInline(text);
    const valuePattern = r'([\d,.]+(?:\.\d+)?\s*[万wWkK]?)';
    for (final label in labels) {
      final valueFirst = RegExp(
        '$valuePattern\\s*${RegExp.escape(label)}',
        caseSensitive: false,
      ).firstMatch(normalized)?.group(1);
      final cleanValueFirst = _extractStatValue(valueFirst);
      if (cleanValueFirst != null) return cleanValueFirst;

      final labelFirst = RegExp(
        '${RegExp.escape(label)}\\s*[:：]?\\s*$valuePattern',
        caseSensitive: false,
      ).firstMatch(normalized)?.group(1);
      final cleanLabelFirst = _extractStatValue(labelFirst);
      if (cleanLabelFirst != null) return cleanLabelFirst;
    }
    return null;
  }

  bool _isHiddenPrompt(String text) {
    final normalized = _cleanInline(text);
    return normalized.contains('如果您要查看本帖隐藏内容请回复') ||
        normalized.contains('回复后可见') ||
        normalized.contains('回复可见') ||
        normalized.contains('回复后才可见') ||
        normalized.contains('回复后才可以查看') ||
        normalized.contains('回复后才可以浏览') ||
        normalized.contains('需要回复才可以查看') ||
        normalized.contains('需要回复才可以浏览') ||
        normalized.contains('需要回复才能看到') ||
        normalized.contains('需要回复才能查看') ||
        normalized.contains('您没有权限查看') ||
        normalized.contains('没有权限查看') ||
        normalized.contains('无权查看') ||
        (normalized.contains('阅读权限') && normalized.contains('不足')) ||
        (normalized.contains('隐藏内容') &&
            (normalized.contains('请回复') || normalized.contains('回复')));
  }

  String? _extractStatValue(String? text) {
    if (text == null) return null;
    final normalized = _cleanInline(text);
    if (normalized.isEmpty) return null;
    final match = RegExp(
      r'[\d,.]+(?:\.\d+)?\s*[万wWkK]?',
      caseSensitive: false,
    ).firstMatch(normalized);
    final value = match?.group(0)?.replaceAll(RegExp(r'\s+'), '') ?? '';
    return value.isEmpty ? null : value;
  }
}
