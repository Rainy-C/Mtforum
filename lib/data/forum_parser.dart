import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;

import '../models/models.dart';
import 'smiley_catalog.dart';

/// 论坛 HTML 解析器。
///
/// 核心原则：
/// 1. AJAX 响应先剥离 XML/CDATA。
/// 2. 帖子详情不依赖整页 DOM 的父子关系，因为移动模板可能包含非标准嵌套，
///    HTML5 parser 会自动修复 DOM，造成正文被移动到 pid 节点外。
/// 3. 详情页先在“原始 HTML 字符串”中按 pid 起点切楼层，再在每个楼层片段里
///    找 comiis_message_table。这样既遵循 MT 页面结构，又规避 DOM 修复问题。
class ForumParser {
  const ForumParser();

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
      ));
    }

    return result;
  }

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

  PostEditorForm parsePostEditorForm(
    String body, {
    required String fallbackFid,
    String fallbackTid = '',
    String fallbackPid = '',
    int fallbackPage = 1,
  }) {
    final document = html_parser.parse(body);
    final form = document.querySelector('form#postform') ??
        document.querySelector('form[action*="mod=post"]');

    String valueOf(String name) {
      final inForm = form
          ?.querySelector('input[name="$name"]')
          ?.attributes['value']
          ?.trim();
      if (inForm != null && inForm.isNotEmpty) return inForm;

      // 移动模板偶尔会改 form 包裹层，但真实字段仍在页面里。
      return document
              .querySelector('input[name="$name"]')
              ?.attributes['value']
              ?.trim() ??
          '';
    }

    final formhash = valueOf('formhash');
    final posttime = valueOf('posttime');
    final fid = valueOf('fid').isNotEmpty ? valueOf('fid') : fallbackFid;
    final tid = valueOf('tid').isNotEmpty ? valueOf('tid') : fallbackTid;
    final pid = valueOf('pid').isNotEmpty ? valueOf('pid') : fallbackPid;
    final parsedPage = int.tryParse(valueOf('page')) ?? fallbackPage;
    final subject = form?.querySelector('input[name="subject"]')?.attributes['value'] ??
        document.querySelector('input[name="subject"]')?.attributes['value'] ??
        '';
    final message = form?.querySelector('textarea[name="message"]')?.text ??
        document.querySelector('textarea[name="message"]')?.text ??
        '';

    // Discuz 移动端上传组件把 uid/hash 放在 JS 的 uploadformdata 中，
    // 不是普通 input。附件上传必须使用这组页面级凭证，不能拿 formhash 代替。
    final uploadBlock = RegExp(
      r'''uploadformdata\s*:\s*\{([^}]*)\}''',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(body)?.group(1) ?? '';
    final uploadUid = RegExp(
      r'''["']?uid["']?\s*:\s*["']?(\d+)["']?''',
      caseSensitive: false,
    ).firstMatch(uploadBlock)?.group(1) ?? '';
    final uploadHash = RegExp(
      r'''["']?hash["']?\s*:\s*["']([a-fA-F0-9]+)["']''',
      caseSensitive: false,
    ).firstMatch(uploadBlock)?.group(1) ?? '';
    final maxUploadSizeKb = int.tryParse(
          RegExp(
            r'''maxfilesize\s*[:=]\s*["']?(\d+)["']?''',
            caseSensitive: false,
          ).firstMatch(body)?.group(1) ?? '',
        ) ??
        1024;
    final attachmentAids = <String>{};
    for (final input in document.querySelectorAll('input[name]')) {
      final name = input.attributes['name'] ?? '';
      final match = RegExp(
        r'^attachnew\[(\d+)\]\[(?:description|readperm|price)\]$',
        caseSensitive: false,
      ).firstMatch(name);
      final aid = match?.group(1);
      if (aid != null && aid.isNotEmpty) attachmentAids.add(aid);
    }

    return PostEditorForm(
      formhash: formhash,
      posttime: posttime,
      fid: fid,
      tid: tid,
      pid: pid,
      page: parsedPage,
      subject: subject,
      message: message,
      deleteValue: valueOf('delete').isEmpty ? '0' : valueOf('delete'),
      allowNoticeAuthor:
          valueOf('allownoticeauthor').isEmpty ? '1' : valueOf('allownoticeauthor'),
      useSig: valueOf('usesig').isEmpty ? '1' : valueOf('usesig'),
      uploadUid: uploadUid,
      uploadHash: uploadHash,
      maxUploadSizeKb: maxUploadSizeKb,
      attachmentAids: attachmentAids.toList(growable: false),
    );
  }

  PostAttachmentUploadResult parsePostAttachmentUploadResponse(String body) {
    final raw = unwrapAjax(body).trim();
    final markerIndex = raw.indexOf('DISCUZUPLOAD|');
    if (markerIndex < 0) {
      final text = html_parser.parseFragment(raw).text?.trim() ?? '';
      return PostAttachmentUploadResult(
        success: false,
        message: text.isEmpty ? '附件上传失败' : text,
      );
    }

    final payload = raw.substring(markerIndex).split(RegExp(r'[\r\n<]')).first;
    final parts = payload.split('|');
    if (parts.length < 4 || parts.first != 'DISCUZUPLOAD') {
      return const PostAttachmentUploadResult(
        success: false,
        message: '附件上传响应格式异常',
      );
    }

    final status = parts.length > 2 ? parts[2].trim() : '';
    final aid = parts.length > 3 ? parts[3].trim() : '';
    final relativePath = parts.length > 5 ? parts[5].trim() : '';
    final fileName = parts.length > 6 ? parts[6].trim() : '';
    final limitInfo = parts.length > 7 ? parts[7].trim() : '';

    if (status != '0' || aid.isEmpty) {
      final statusReason = switch (status) {
        '1' => '服务器写入失败',
        '2' => '图片超过论坛大小限制',
        '3' => '论坛不支持该图片格式',
        '9' => '图片无效或尺寸过小',
        _ => '服务器拒绝了附件',
      };
      final reason = limitInfo.isNotEmpty && limitInfo != '0'
          ? limitInfo
          : statusReason;
      return PostAttachmentUploadResult(
        success: false,
        message: '上传失败：$reason',
        limitInfo: limitInfo,
      );
    }

    final url = relativePath.isEmpty
        ? ''
        : 'https://cdn.binmt.cc/data/attachment/forum/$relativePath';
    return PostAttachmentUploadResult(
      success: true,
      message: '上传成功',
      aid: aid,
      relativePath: relativePath,
      fileName: fileName,
      url: url,
      limitInfo: limitInfo,
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
      final candidate = image.attributes['zoomfile'] ??
          image.attributes['file'] ??
          image.attributes['data-original'] ??
          image.attributes['data-src'] ??
          image.attributes['src'];
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
  List<PostContent> _parseRichContent(
    html_dom.Element root, {
    required String baseUrl,
  }) {
    final contents = <PostContent>[];
    final textBuffer = StringBuffer();

    void flushText() {
      if (textBuffer.isEmpty) {
        return;
      }

      // 这里不能 trim：<br> 可能正好位于普通文字与 color/size 等
      // 样式节点之间。若 flush 时删掉首尾换行，预览里正常的分段在
      // 帖子详情中就会粘成一行。
      final value = _normalizeMultiline(textBuffer.toString());
      textBuffer.clear();

      if (value.isEmpty) {
        return;
      }

      contents.addAll(
        _parseBbCodeText(
          value,
          baseUrl: baseUrl,
        ),
      );
    }

    String codeText(html_dom.Element element) {
      final lines = element.querySelectorAll('ol > li');
      if (lines.isNotEmpty) {
        return lines.map((line) => line.text).join('\n').trim();
      }

      return element.text
          .replaceAll('\r\n', '\n')
          .replaceAll('\r', '\n')
          .trim();
    }

    String? mediaUrl(html_dom.Element element) {
      final direct = element.attributes['src'] ??
          element.attributes['data'] ??
          element.attributes['file'];
      if (direct != null && direct.trim().isNotEmpty) {
        return _absoluteUrl(direct, baseUrl);
      }

      final source = element.querySelector('source');
      return _absoluteUrl(
        source?.attributes['src'],
        baseUrl,
      );
    }

    bool isAttachmentHref(String? href) {
      if (href == null || href.trim().isEmpty) return false;
      final lower = href.toLowerCase();
      return lower.contains('mod=attachment') ||
          lower.contains('attachment.php') ||
          RegExp(r'(?:[?&]|&amp;)aid=').hasMatch(lower);
    }

    String attachmentName(html_dom.Element anchor) {
      final downloadName = anchor.attributes['download']?.trim();
      if (downloadName != null && downloadName.isNotEmpty) {
        return downloadName;
      }
      final label = _cleanInline(anchor.text);
      if (label.isNotEmpty && label != '下载附件' && label != '下载') {
        return label;
      }
      final title = anchor.attributes['title']?.trim();
      if (title != null && title.isNotEmpty) {
        return title;
      }
      return '附件';
    }

    bool isRenderableInlineImage(html_dom.Element image) {
      final candidate = image.attributes['zoomfile'] ??
          image.attributes['file'] ??
          image.attributes['data-original'] ??
          image.attributes['data-src'] ??
          image.attributes['src'];
      final url = _absoluteUrl(candidate, baseUrl);
      if (url == null) return false;
      final lower = url.toLowerCase();
      final isEmoji = image.attributes['smilieid'] != null ||
          image.classes.any(
            (value) => value.toLowerCase().contains('smilie'),
          ) ||
          SmileyCatalog.isForumSmileyUrl(lower);
      return isEmoji || _isPostContentImage(url, image);
    }

    List<List<String>> tableRows(html_dom.Element table) {
      final rows = <List<String>>[];
      for (final tr in table.querySelectorAll('tr')) {
        html_dom.Element? owner = tr.parent;
        while (owner != null &&
            (owner.localName ?? '').toLowerCase() != 'table') {
          owner = owner.parent;
        }
        if (!identical(owner, table)) {
          continue;
        }
        final cells = tr.children
            .where((cell) {
              final tag = (cell.localName ?? '').toLowerCase();
              return tag == 'th' || tag == 'td';
            })
            .map((cell) {
              final value = cell.innerHtml
                  .replaceAll(
                    RegExp(r'<br\s*/?>', caseSensitive: false),
                    '\n',
                  )
                  .replaceAll(
                    RegExp(r'</(?:p|div)>', caseSensitive: false),
                    '\n',
                  );
              return _cleanMultiline(
                html_parser.parseFragment(value).text ?? cell.text,
              );
            })
            .toList(growable: false);
        if (cells.isNotEmpty) {
          rows.add(cells);
        }
      }
      return rows;
    }

    List<PostContent> quoteInlineContents(html_dom.Element quote) {
      final result = <PostContent>[];
      final buffer = StringBuffer();

      void flushQuoteText() {
        if (buffer.isEmpty) return;
        final value = _cleanMultiline(buffer.toString());
        buffer.clear();
        if (value.isEmpty) return;
        result.addAll(_parseBbCodeText(value, baseUrl: baseUrl));
      }

      void walk(html_dom.Node child) {
        if (child is html_dom.Text) {
          buffer.write(child.text);
          return;
        }
        if (child is! html_dom.Element) return;

        final tag = (child.localName ?? '').toLowerCase();
        switch (tag) {
          case 'br':
            buffer.write('\n');
            return;
          case 'h1':
          case 'h2':
          case 'h3':
          case 'h4':
          case 'strong':
          case 'b':
            flushQuoteText();
            final label = _cleanInline(child.text);
            if (label.isNotEmpty) {
              result.add(PostContent.bold(label));
              // Comiis 的隐藏内容标题通常是块级 h2，链接应显示在下一行。
              if (tag.startsWith('h')) {
                result.add(PostContent.text('\n'));
              }
            }
            return;
          case 'a':
            final rawHref = child.attributes['href'];
            final href = _absoluteUrl(rawHref, baseUrl);
            final label = _cleanInline(child.text);
            if (href != null &&
                href.isNotEmpty &&
                !href.toLowerCase().startsWith('javascript:')) {
              flushQuoteText();
              result.add(PostContent.link(label.isEmpty ? href : label, href));
            } else {
              buffer.write(child.text);
            }
            return;
          case 'span':
          case 'p':
          case 'div':
            for (final nested in child.nodes) {
              walk(nested);
            }
            if (tag == 'p' || tag == 'div') buffer.write('\n');
            return;
          default:
            for (final nested in child.nodes) {
              walk(nested);
            }
        }
      }

      for (final child in quote.nodes) {
        walk(child);
      }
      flushQuoteText();

      // 去掉标题块产生的末尾纯换行，避免卡片底部多出空行。
      while (result.isNotEmpty &&
          result.last.type == PostContentType.text &&
          result.last.text.trim().isEmpty) {
        result.removeLast();
      }
      return result;
    }

    int tableHeaderRows(html_dom.Element table) {
      var count = 0;
      for (final tr in table.querySelectorAll('tr')) {
        html_dom.Element? owner = tr.parent;
        while (owner != null &&
            (owner.localName ?? '').toLowerCase() != 'table') {
          owner = owner.parent;
        }
        if (!identical(owner, table)) {
          continue;
        }
        final directCells = tr.children.where((cell) {
          final tag = (cell.localName ?? '').toLowerCase();
          return tag == 'th' || tag == 'td';
        }).toList(growable: false);
        if (directCells.isEmpty) continue;
        if (directCells.any((cell) =>
            (cell.localName ?? '').toLowerCase() == 'th')) {
          count++;
        } else {
          break;
        }
      }
      return count;
    }

    late void Function(html_dom.Node node) processNode;

    void appendStyledNode(
      html_dom.Node child,
      _InlineStyle style, {
      String? linkUrl,
    }) {
      if (child is html_dom.Text) {
        final rawText = child.text
            .replaceAll('\u00a0', ' ')
            .replaceAll('\r\n', '\n')
            .replaceAll('\r', '\n');
        if (rawText.trim().isEmpty && rawText.contains('\n')) return;
        var value = rawText.replaceAll(RegExp(r'[ \t\n]+'), ' ');
        if (RegExp(r'^[ \t]*\n').hasMatch(rawText)) {
          value = value.trimLeft();
        }
        if (RegExp(r'\n[ \t]*$').hasMatch(rawText)) {
          value = value.trimRight();
        }
        if (value.isNotEmpty) {
          contents.add(
            PostContent.inline(
              value,
              url: linkUrl,
              bold: style.bold,
              italic: style.italic,
              underline: style.underline,
              strikethrough: style.strikethrough,
              color: style.color,
              backgroundColor: style.backgroundColor,
              fontFamily: style.fontFamily,
              fontSizeScale: style.fontSizeScale,
            ),
          );
        }
        return;
      }
      if (child is! html_dom.Element) return;

      final childTag = (child.localName ?? '').toLowerCase();
      if (childTag == 'br') {
        contents.add(PostContent.inline('\n', url: linkUrl));
        return;
      }
      if (childTag == 'img' ||
          childTag == 'audio' ||
          childTag == 'video' ||
          childTag == 'embed' ||
          childTag == 'object') {
        processNode(child);
        return;
      }

      var nextStyle = style;
      var nextLink = linkUrl;
      switch (childTag) {
        case 'strong':
        case 'b':
          nextStyle = nextStyle.copyWith(bold: true);
          break;
        case 'i':
        case 'em':
          nextStyle = nextStyle.copyWith(italic: true);
          break;
        case 'u':
          nextStyle = nextStyle.copyWith(underline: true);
          break;
        case 's':
        case 'strike':
        case 'del':
          nextStyle = nextStyle.copyWith(strikethrough: true);
          break;
        case 'a':
          final href = _absoluteUrl(child.attributes['href'], baseUrl);
          if (href != null &&
              href.isNotEmpty &&
              !href.toLowerCase().startsWith('javascript:')) {
            nextLink = href;
          }
          break;
        case 'font':
          final css = child.attributes['style'];
          nextStyle = nextStyle.copyWith(
            color: _normalizeBbColor(
              child.attributes['color'] ?? _cssProperty(css, 'color'),
            ),
            fontFamily: child.attributes['face'],
            fontSizeScale: _htmlFontSizeScale(child.attributes['size']) ??
                _cssFontSizeScale(css),
            backgroundColor: _cssBackgroundColor(
              css,
            ),
          );
          break;
        case 'span':
          final css = child.attributes['style'];
          final weight = _cssProperty(css, 'font-weight')?.toLowerCase();
          final numericWeight = int.tryParse(weight ?? '');
          final fontStyle = _cssProperty(css, 'font-style')?.toLowerCase();
          final decoration =
              _cssProperty(css, 'text-decoration')?.toLowerCase();
          nextStyle = nextStyle.copyWith(
            color: _normalizeBbColor(_cssProperty(css, 'color')),
            backgroundColor: _cssBackgroundColor(css),
            fontFamily: _cssProperty(css, 'font-family'),
            fontSizeScale: _cssFontSizeScale(css),
            bold: weight == 'bold' ||
                    (numericWeight != null && numericWeight >= 600)
                ? true
                : null,
            italic: fontStyle == 'italic' ? true : null,
            underline: decoration?.contains('underline') == true ? true : null,
            strikethrough:
                decoration?.contains('line-through') == true ? true : null,
          );
          break;
      }
      for (final nested in child.nodes) {
        appendStyledNode(nested, nextStyle, linkUrl: nextLink);
      }
    }

    processNode = (html_dom.Node node) {
      if (node is html_dom.Text) {
        // HTML 源码中为排版添加的 CRLF/缩进不是正文换行，
        // 浏览器也会把它们折叠为普通空白。真正的用户换行由
        // <br> 节点单独处理，避免 <br />\r\n 被计算两次。
        final rawText = node.text;
        if (rawText.trim().isEmpty && rawText.contains(RegExp(r'[\r\n]'))) {
          return;
        }
        var value = rawText
            .replaceAll('\u00a0', ' ')
            .replaceAll(RegExp(r'[ \t\r\n]+'), ' ');
        if (RegExp(r'^[ \t]*[\r\n]').hasMatch(rawText)) {
          value = value.trimLeft();
        }
        if (RegExp(r'[\r\n][ \t]*$').hasMatch(rawText)) {
          value = value.trimRight();
        }
        if (value.isNotEmpty) textBuffer.write(value);
        return;
      }

      if (node is! html_dom.Element) {
        return;
      }

      final tag = (node.localName ?? '').toLowerCase();
      final classes = node.classes;

      final lowerClasses = classes.map((value) => value.toLowerCase());
      final nodeId = (node.attributes['id'] ?? '').toLowerCase();
      final isCodeContainer = lowerClasses.any(
            (value) => value == 'blockcode' || value.contains('blockcode'),
          ) ||
          nodeId.startsWith('code_') ||
          node.attributes['data-type']?.toLowerCase() == 'code';

      if (tag == 'table') {
        // Discuz 会用 table/td 包裹正文图片做布局。若直接转成
        // 文本表格，cell.text 会丢掉 <img>，App 最终只渲染出空单元格。
        // 带图片的表格按普通富媒体容器递归，纯文字表格则保留
        // 原有的行列渲染。
        final containsRenderableImage =
            node.querySelectorAll('img').any(isRenderableInlineImage);
        if (containsRenderableImage) {
          flushText();
          for (final child in node.nodes) {
            processNode(child);
          }
          flushText();
          return;
        }

        final rows = tableRows(node);
        if (rows.isNotEmpty) {
          flushText();
          contents.add(
            PostContent.table(
              rows,
              headerRows: tableHeaderRows(node),
            ),
          );
        }
        return;
      }

      if (tag == 'hr') {
        flushText();
        contents.add(PostContent.divider());
        return;
      }

      final alignment = (node.attributes['align'] ??
              _cssProperty(node.attributes['style'], 'text-align'))
          ?.trim()
          .toLowerCase();
      if ((tag == 'div' || tag == 'p') &&
          const {'left', 'center', 'right', 'justify'}.contains(alignment)) {
        flushText();
        final children = _parseRichContent(node, baseUrl: baseUrl);
        if (children.isNotEmpty) {
          contents.add(
            PostContent.aligned(children, alignment: alignment!),
          );
        }
        return;
      }

      if (tag == 'ul' || tag == 'ol') {
        flushText();
        final listChildren = <PostContent>[];
        final listItems = node.children
            .where(
              (element) => (element.localName ?? '').toLowerCase() == 'li',
            )
            .toList(growable: false);
        var index = 0;
        for (final item in listItems) {
          index++;
          final type = (node.attributes['type'] ?? '').toLowerCase();
          final marker = tag == 'ol' || type == '1'
              ? '$index. '
              : type == 'a'
                  ? '${String.fromCharCode(96 + ((index - 1) % 26) + 1)}. '
                  : '• ';
          listChildren.add(PostContent.text(marker));

          final itemContents = _parseRichContent(item, baseUrl: baseUrl);
          for (final content in itemContents) {
            // Discuz 常把 [list][*]渲染成：
            //   <li><div align="left">正文</div></li>
            // left 只是模板默认样式，不应在 App 中再变成独立块。
            // 否则列表符号会独占一行，正文被挤到下一段。
            if (content.type == PostContentType.aligned &&
                content.alignment == 'left') {
              listChildren.addAll(content.children);
            } else {
              listChildren.add(content);
            }
          }
          if (index < listItems.length) {
            listChildren.add(PostContent.text('\n'));
          }
        }
        if (listChildren.isNotEmpty) {
          contents.add(
            PostContent.list(
              listChildren,
              type: node.attributes['type'] ?? (tag == 'ol' ? '1' : ''),
            ),
          );
        }
        return;
      }

      final isAttachmentContainer = lowerClasses.any(
        (value) =>
            value == 'tattl' ||
            value == 'attm' ||
            value == 'attachment' ||
            value == 'attachments' ||
            value == 'attachlist' ||
            value == 'comiis_attach' ||
            value == 'comiis_attachment',
      );
      if (isAttachmentContainer) {
        var added = false;
        for (final anchor in node.querySelectorAll('a')) {
          final href = anchor.attributes['href'];
          if (!isAttachmentHref(href)) continue;
          if (anchor.querySelectorAll('img').any(isRenderableInlineImage)) {
            continue;
          }
          final url = _absoluteUrl(href, baseUrl);
          flushText();
          contents.add(
            PostContent.attachment(
              attachmentName(anchor),
              url: url,
            ),
          );
          added = true;
        }
        if (added) {
          return;
        }
      }

      if (isCodeContainer) {
        flushText();
        final code = codeText(node);
        if (code.isNotEmpty) {
          contents.add(PostContent.code(code));
        }
        return;
      }

      if (classes.contains('comiis_quote')) {
        // Comiis 同时会把普通引用和“已解锁的隐藏内容/下载内容”放进
        // .comiis_quote。后者内部可能包含真正的 <a href>、附件或图片。
        // 旧逻辑直接 node.text 会把它们全部压平成纯文字，例如：
        //   本帖隐藏的内容：下载链接
        // 从而导致“下载链接”无法点击。
        final hasUsefulAnchor = node.querySelectorAll('a[href]').any((anchor) {
          final rawHref = (anchor.attributes['href'] ?? '')
              .replaceAll('&amp;', '&')
              .trim();
          if (rawHref.isEmpty ||
              rawHref.toLowerCase().startsWith('javascript:')) {
            return false;
          }
          final lower = rawHref.toLowerCase();
          return !lower.contains('action=reply') &&
              !lower.contains('repquote=') &&
              !lower.contains('showmessage(');
        });
        final hasRenderableImage =
            node.querySelectorAll('img').any(isRenderableInlineImage);
        final hasAttachment = node.querySelectorAll('a[href]').any(
              (anchor) => isAttachmentHref(anchor.attributes['href']),
            );
        final hasRawLink = RegExp(
          r'''(?:https?://|www\.|(?:[A-Za-z0-9-]+\.)+[A-Za-z]{2,}/)''',
          caseSensitive: false,
        ).hasMatch(node.text);

        if ((hasUsefulAnchor || hasRawLink) &&
            !hasRenderableImage &&
            !hasAttachment) {
          // 已解锁隐藏内容最常见的真实结构：
          // <div class="comiis_quote">
          //   <h2>本帖隐藏的内容:</h2>
          //   <a href="...">下载链接</a>
          // </div>
          // 保留 quote 卡片视觉，同时让内部链接维持可点击语义。
          final children = quoteInlineContents(node);
          if (children.isNotEmpty) {
            flushText();
            contents.add(PostContent.richQuote(children));
            return;
          }
        }

        if (hasRenderableImage || hasAttachment) {
          // 图片/附件结构继续按完整富文本递归，避免丢失媒体。
          flushText();
          for (final child in node.nodes) {
            processNode(child);
          }
          flushText();
          return;
        }

        // 纯文字引用仍维持原来的引用卡片样式。
        flushText();
        final quote = _cleanMultiline(node.text);
        if (quote.isNotEmpty) {
          contents.add(PostContent.quote(quote));
        }
        return;
      }

      if (classes.any(
        (value) =>
            value.toLowerCase().contains('free') ||
            value.toLowerCase().contains('showhide'),
      )) {
        // 已解锁的隐藏/付费内容里经常包含真实 <a href>、图片或裸链接。
        // 旧逻辑直接 node.text 压平成 PostContent.free，会把下载地址吃掉，
        // 最终只能看到“下载链接”几个字。只对纯提示文本使用 free 卡片；
        // 一旦容器中存在可交互内容，就继续按普通富文本递归解析。
        final usefulAnchor = node.querySelectorAll('a[href]').any((anchor) {
          final href = (anchor.attributes['href'] ?? '')
              .replaceAll('&amp;', '&')
              .trim();
          if (href.isEmpty || href.toLowerCase().startsWith('javascript:')) {
            return false;
          }
          final lower = href.toLowerCase();
          return !lower.contains('action=reply') &&
              !lower.contains('repquote=') &&
              !lower.contains('showmessage(');
        });
        final hasImage = node.querySelectorAll('img').any(isRenderableInlineImage);
        final hasRawLink = RegExp(
          r'''(?:https?://|www\.|(?:[A-Za-z0-9-]+\.)+[A-Za-z]{2,}/)''',
          caseSensitive: false,
        ).hasMatch(node.text);

        if (usefulAnchor || hasImage || hasRawLink) {
          flushText();
          for (final child in node.nodes) {
            processNode(child);
          }
          flushText();
          return;
        }

        final freeText = _cleanMultiline(node.text);
        if (freeText.isNotEmpty) {
          flushText();
          contents.add(PostContent.free(freeText));
          return;
        }
      }

      switch (tag) {
        case 'br':
          textBuffer.write('\n');
          return;

        case 'strong':
        case 'b':
        case 'i':
        case 'em':
        case 'u':
        case 's':
        case 'strike':
        case 'del':
        case 'font':
        case 'span':
          flushText();
          final before = contents.length;
          appendStyledNode(node, const _InlineStyle());
          if (contents.length == before) {
            final fallback = _cleanInline(node.text);
            if (fallback.isNotEmpty) textBuffer.write(fallback);
          }
          return;

        case 'a':
          final rawHref = node.attributes['href'];
          final href = _absoluteUrl(rawHref, baseUrl);
          final label = _cleanInline(node.text);

          // Discuz 图片通常被 <a> 包裹用于 Web 端放大查看。
          // 若先按普通链接处理，会吞掉内部 img，最终只能依赖“游离图片”补偿，
          // 图片顺序也会错。这里优先保留图片/表情节点。
          final wrappedImages = node
              .querySelectorAll('img')
              .where(isRenderableInlineImage)
              .toList(growable: false);
          if (wrappedImages.isNotEmpty) {
            flushText();
            for (final image in wrappedImages) {
              processNode(image);
            }
            return;
          }

          if (isAttachmentHref(rawHref)) {
            flushText();
            contents.add(
              PostContent.attachment(
                attachmentName(node),
                url: href,
              ),
            );
            return;
          }

          final hasStyledChildren = node.querySelector(
                'strong, b, i, em, u, s, strike, del, font, span[style]',
              ) !=
              null;
          if (hasStyledChildren && href != null && href.isNotEmpty) {
            flushText();
            appendStyledNode(node, const _InlineStyle());
            return;
          }

          if (href != null &&
              href.isNotEmpty &&
              !href.toLowerCase().startsWith('javascript:')) {
            flushText();
            contents.add(
              PostContent.link(
                label.isEmpty ? href : label,
                href,
              ),
            );
          } else {
            textBuffer.write(node.text);
          }
          return;

        case 'img':
          final rawUrl = node.attributes['zoomfile'] ??
              node.attributes['file'] ??
              node.attributes['data-original'] ??
              node.attributes['data-src'] ??
              node.attributes['src'];
          final url = _absoluteUrl(rawUrl, baseUrl);
          if (url == null || url.isEmpty) {
            return;
          }

          flushText();

          final lowerUrl = url.toLowerCase();
          final isEmoji =
              node.attributes['smilieid'] != null ||
              node.classes.any(
                (value) => value.toLowerCase().contains('smilie'),
              ) ||
              SmileyCatalog.isForumSmileyUrl(lowerUrl);

          if (isEmoji) {
            contents.add(PostContent.emoji(url));
          } else {
            contents.add(PostContent.image(url));
          }
          return;

        case 'audio':
          final url = mediaUrl(node);
          if (url != null) {
            flushText();
            contents.add(PostContent.audio(url));
          }
          return;

        case 'video':
          final url = mediaUrl(node);
          if (url != null) {
            flushText();
            contents.add(PostContent.video(url));
          }
          return;

        case 'embed':
          final url = mediaUrl(node);
          if (url != null) {
            flushText();
            final type = node.attributes['type']?.toLowerCase() ?? '';
            if (type.contains('shockwave') ||
                type.contains('flash') ||
                url.toLowerCase().endsWith('.swf')) {
              contents.add(PostContent.flash(url));
            } else {
              contents.add(PostContent.video(url));
            }
          }
          return;

        case 'object':
          final url = mediaUrl(node);
          if (url != null) {
            flushText();
            contents.add(PostContent.flash(url));
          }
          return;

        case 'pre':
        case 'code':
          flushText();
          final code = codeText(node);
          if (code.isNotEmpty) {
            contents.add(PostContent.code(code));
          }
          return;

        case 'blockquote':
          flushText();
          final quote = _cleanMultiline(node.text);
          if (quote.isNotEmpty) {
            contents.add(PostContent.quote(quote));
          }
          return;

        case 'li':
          textBuffer.write('• ');
          for (final child in node.nodes) {
            processNode(child);
          }
          textBuffer.write('\n');
          return;

        case 'div':
        case 'p':
        case 'section':
          for (final child in node.nodes) {
            processNode(child);
          }
          textBuffer.write('\n');
          return;

        default:
          for (final child in node.nodes) {
            processNode(child);
          }
      }
    };

    for (final node in root.nodes) {
      processNode(node);
    }

    flushText();
    final normalized = _normalizeRichContents(contents);
    return _promoteCommandSnippets(
      _normalizeRichBlockBoundaries(normalized),
    );
  }

  /// 兼容极少数页面仍把 BBCode 原文直接塞进正文的情况。
  ///
  /// Discuz 正常情况下会在服务端把 BBCode 转为 HTML，但这里保留原始
  /// BBCode 解析作为兜底，避免 [code] / [quote] 等直接显示给用户。
  List<PostContent> _parseBbCodeText(
    String input, {
    required String baseUrl,
  }) {
    if (input.isEmpty) {
      return const [];
    }

    final pattern = RegExp(
      r'\[url=([^\]]+)\](.*?)\[/url\]'
      r'|\[img\](.*?)\[/img\]'
      r'|\[audio\](.*?)\[/audio\]'
      r'|\[media=[^\]]*\](.*?)\[/media\]'
      r'|\[flash\](.*?)\[/flash\]'
      r'|\[quote\](.*?)\[/quote\]'
      r'|\[code\](.*?)\[/code\]'
      r'|\[free\](.*?)\[/free\]'
      r'|\[attach\](.*?)\[/attach\]'
      r'|\[attachimg\](.*?)\[/attachimg\]',
      caseSensitive: false,
      dotAll: true,
    );

    final result = <PostContent>[];
    var cursor = 0;

    for (final match in pattern.allMatches(input)) {
      if (match.start > cursor) {
        final plain = input.substring(cursor, match.start);
        if (plain.isNotEmpty) {
          _appendLinkifiedText(
            result,
            plain,
            baseUrl: baseUrl,
          );
        }
      }

      if (match.group(1) != null) {
        final rawUrl = match.group(1)!.trim();
        final url = _absoluteUrl(rawUrl, baseUrl) ?? rawUrl;
        result.add(
          PostContent.link(
            match.group(2)?.trim().isNotEmpty == true
                ? match.group(2)!.trim()
                : url,
            url,
          ),
        );
      } else if (match.group(3) != null) {
        final rawUrl = match.group(3)!.trim();
        final url = _absoluteUrl(rawUrl, baseUrl) ?? rawUrl;
        final lowerUrl = url.toLowerCase();
        final isEmoji = SmileyCatalog.isForumSmileyUrl(lowerUrl);
        result.add(isEmoji ? PostContent.emoji(url) : PostContent.image(url));
      } else if (match.group(4) != null) {
        final rawUrl = match.group(4)!.trim();
        final url = _absoluteUrl(rawUrl, baseUrl) ?? rawUrl;
        result.add(PostContent.audio(url));
      } else if (match.group(5) != null) {
        final rawUrl = match.group(5)!.trim();
        final url = _absoluteUrl(rawUrl, baseUrl) ?? rawUrl;
        result.add(PostContent.video(url));
      } else if (match.group(6) != null) {
        final rawUrl = match.group(6)!.trim();
        final url = _absoluteUrl(rawUrl, baseUrl) ?? rawUrl;
        result.add(PostContent.flash(url));
      } else if (match.group(7) != null) {
        result.add(PostContent.quote(match.group(7)!.trim()));
      } else if (match.group(8) != null) {
        result.add(PostContent.code(match.group(8)!.trim()));
      } else if (match.group(9) != null) {
        result.add(PostContent.free(match.group(9)!.trim()));
      } else if (match.group(10) != null || match.group(11) != null) {
        final aid = (match.group(10) ?? match.group(11) ?? '').trim();
        final url = aid.isEmpty
            ? null
            : '$baseUrl/forum.php?mod=attachment&aid=$aid';
        result.add(
          PostContent.attachment(
            aid.isEmpty ? '附件' : '附件 #$aid',
            url: url,
          ),
        );
      }

      cursor = match.end;
    }

    if (cursor < input.length) {
      final plain = input.substring(cursor);
      if (plain.isNotEmpty) {
        _appendLinkifiedText(
          result,
          plain,
          baseUrl: baseUrl,
        );
      }
    }

    if (result.isEmpty) {
      _appendLinkifiedText(
        result,
        input,
        baseUrl: baseUrl,
      );
    }

    return _normalizeRichContents(result);
  }

  /// 清理未匹配/未闭合的 BBCode 残留标记，避免原样显示给用户。
  String _stripBbCodeRemains(String input) {
    return input
        .replaceAll(
          RegExp(r'\[url=[^\]]*\]', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(
              r'\[/(?:url|img|audio|media|flash|quote|code|free|hide|attach|attachimg)\]',
              caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(
              r'\[(?:url|img|audio|media|flash|quote|code|free|hide|attach|attachimg)\]',
              caseSensitive: false),
          '',
        );
  }

  void _appendLinkifiedText(
    List<PostContent> output,
    String input, {
    required String baseUrl,
  }) {
    if (input.isEmpty) {
      return;
    }

    // 清理未匹配/未闭合的 BBCode 残留标记，避免原样显示给用户。
    final cleaned = _stripBbCodeRemains(input);
    if (cleaned.isEmpty) {
      return;
    }
    input = cleaned;

    final linkPattern = RegExp(
      r'''(?:(?:https?://|www\.)[^\s<>"']+|(?:[A-Za-z0-9-]+\.)+[A-Za-z]{2,}(?::\d+)?(?:/[^\s<>"']*)?)''',
      caseSensitive: false,
    );

    var cursor = 0;

    for (final match in linkPattern.allMatches(input)) {
      if (match.start > cursor) {
        output.add(
          PostContent.text(
            input.substring(cursor, match.start),
          ),
        );
      }

      final rawMatch = match.group(0)!;
      final cleaned = _trimLinkPunctuation(rawMatch);
      final trailing = rawMatch.substring(cleaned.length);

      if (cleaned.isNotEmpty) {
        final url = _normalizeExternalUrl(cleaned, baseUrl);
        output.add(PostContent.link(cleaned, url));
      }

      if (trailing.isNotEmpty) {
        output.add(PostContent.text(trailing));
      }

      cursor = match.end;
    }

    if (cursor < input.length) {
      output.add(
        PostContent.text(
          input.substring(cursor),
        ),
      );
    }
  }

  String _trimLinkPunctuation(String value) {
    var end = value.length;
    const trailing = '.,;:!?，。；：！？)]}》】';

    while (end > 0 && trailing.contains(value[end - 1])) {
      end--;
    }

    return value.substring(0, end);
  }

  String _normalizeExternalUrl(String value, String baseUrl) {
    final trimmed = value.trim();

    if (trimmed.startsWith('//')) {
      return 'https:$trimmed';
    }

    if (RegExp(r'^https?://', caseSensitive: false).hasMatch(trimmed)) {
      return trimmed;
    }

    if (trimmed.toLowerCase().startsWith('www.') ||
        RegExp(
          r'^(?:[A-Za-z0-9-]+\.)+[A-Za-z]{2,}(?::\d+)?(?:/|$)',
          caseSensitive: false,
        ).hasMatch(trimmed)) {
      return 'https://$trimmed';
    }

    return _absoluteUrl(trimmed, baseUrl) ?? trimmed;
  }

  List<PostContent> _normalizeRichContents(List<PostContent> input) {
    final result = <PostContent>[];

    bool isPlainText(PostContent item) {
      return item.type == PostContentType.text &&
          !item.isBold &&
          !item.isItalic &&
          !item.isUnderline &&
          !item.isStrikethrough &&
          item.color == null &&
          item.backgroundColor == null &&
          item.fontFamily == null &&
          item.fontSizeScale == null;
    }

    for (final item in input) {
      if (isPlainText(item)) {
        // 纯换行也是有意义的富文本节点，尤其用于连接两个不同样式的
        // TextSpan。保留边界换行，只清理行内多余空格。
        final text = _normalizeMultiline(item.text);
        if (text.isEmpty) {
          continue;
        }

        if (result.isNotEmpty &&
            isPlainText(result.last)) {
          final previous = result.removeLast();
          result.add(
            PostContent.text(
              _normalizeMultiline('${previous.text}$text'),
            ),
          );
        } else {
          result.add(PostContent.text(text));
        }
      } else if (item.type == PostContentType.text) {
        if (item.text.isNotEmpty) result.add(item);
      } else {
        result.add(item);
      }
    }

    return result;
  }

  /// 只处理完整富文本树里的块级边界。
  ///
  /// 不能把这段逻辑放进 [_normalizeRichContents]：普通文字缓冲区会在
  /// color/size/url 等样式节点前后多次 flush，单独的 `\n` 在那一层看似
  /// 是首尾空白，实际上是两个行内样式之间必须保留的换行。
  List<PostContent> _normalizeRichBlockBoundaries(List<PostContent> input) {
    bool isInline(PostContent item) {
      return item.type == PostContentType.text ||
          item.type == PostContentType.bold ||
          item.type == PostContentType.link ||
          item.type == PostContentType.emoji;
    }

    PostContent withText(PostContent item, String text) {
      return PostContent.inline(
        text,
        url: item.url,
        bold: item.isBold || item.type == PostContentType.bold,
        italic: item.isItalic,
        underline: item.isUnderline,
        strikethrough: item.isStrikethrough,
        color: item.color,
        backgroundColor: item.backgroundColor,
        fontFamily: item.fontFamily,
        fontSizeScale: item.fontSizeScale,
      );
    }

    final result = <PostContent>[];
    for (var index = 0; index < input.length; index++) {
      final item = input[index];
      if (item.type != PostContentType.text &&
          item.type != PostContentType.bold &&
          item.type != PostContentType.link) {
        result.add(item);
        continue;
      }

      var text = item.text;
      final followsBlock = index == 0 || !isInline(input[index - 1]);
      final precedesBlock =
          index == input.length - 1 || !isInline(input[index + 1]);
      if (followsBlock) text = text.replaceFirst(RegExp(r'^\n+'), '');
      if (precedesBlock) text = text.replaceFirst(RegExp(r'\n+$'), '');
      if (text.isNotEmpty) result.add(withText(item, text));
    }
    return result;
  }

  /// 将论坛里没有包进 [code]/<pre> 的常见命令行片段提升为代码块。
  ///
  /// 一些帖子会写成“启动： npx ...”或“安装： git clone <自动链接>”，
  /// Discuz 会把 URL 单独转成 <a>，原解析只能显示成普通段落。这里采用
  /// 保守规则：仅识别明显的命令前缀，并要求出现在行首或冒号之后。
  List<PostContent> _promoteCommandSnippets(List<PostContent> input) {
    final result = <PostContent>[];
    final commandPattern = RegExp(
      r'(^|[\n：:]\s*)('
      r'git\s+clone(?:[ \t]+[^\n]+)?'
      r'|(?:npx|curl|wget)(?:[ \t]+[^\n]+)?'
      r'|(?:npm|pnpm|yarn|adb|fastboot|flutter|dart|python(?:3)?|pip(?:3)?|docker|go|cargo|gradle|\./gradlew)[ \t]+[^\n]+'
      r')',
      caseSensitive: false,
      multiLine: true,
    );

    bool mayAppendAdjacentLink(String command) {
      final value = command.trim();
      if (RegExp(r'[，。；！？：\u4e00-\u9fff]').hasMatch(value)) {
        return false;
      }
      return RegExp(
        r'^(?:git\s+clone|npx|curl|wget|npm\s+(?:i|install)|pnpm\s+(?:add|dlx)|yarn\s+(?:add|dlx))\b',
        caseSensitive: false,
      ).hasMatch(value);
    }

    var i = 0;
    while (i < input.length) {
      final item = input[i];
      if (item.type != PostContentType.text) {
        result.add(item);
        i++;
        continue;
      }

      final text = item.text;
      final matches = commandPattern.allMatches(text).toList();
      if (matches.isEmpty) {
        result.add(item);
        i++;
        continue;
      }

      var cursor = 0;
      var consumeNextLink = false;
      for (final match in matches) {
        final commandStart = match.start + (match.group(1)?.length ?? 0);
        if (commandStart > cursor) {
          final prefix = text.substring(cursor, commandStart).trimRight();
          if (prefix.isNotEmpty) {
            result.add(PostContent.text(prefix));
          }
        }

        var command = text.substring(commandStart, match.end).trim();

        // Discuz 会自动把命令参数里的 URL 拆成独立 <a> 节点。
        // 例如“git clone https://...”和“npx https://...”。
        // 仅当命令位于当前文本节点末尾、且命令本身没有中文说明时拼接，
        // 避免误吞后面的普通文档链接。
        if (match.end == text.length &&
            mayAppendAdjacentLink(command) &&
            i + 1 < input.length &&
            input[i + 1].type == PostContentType.link) {
          final link = input[i + 1];
          final target = (link.url?.trim().isNotEmpty == true)
              ? link.url!.trim()
              : link.text.trim();
          if (target.isNotEmpty) {
            command = '$command $target';
            consumeNextLink = true;
          }
        }

        result.add(PostContent.code(command));
        cursor = match.end;
      }

      if (cursor < text.length) {
        final suffix = text.substring(cursor).trimLeft();
        if (suffix.isNotEmpty) {
          result.add(PostContent.text(suffix));
        }
      }

      if (consumeNextLink) {
        i++;
      }
      i++;
    }

    return _normalizeRichContents(result);
  }

  bool _isPostContentImage(String url, html_dom.Element image) {
    final lower = url.toLowerCase();
    final classes = image.classes.map((value) => value.toLowerCase()).toSet();
    if (SmileyCatalog.isForumSmileyUrl(lower) ||
        lower.contains('/static/image/') ||
        lower.contains('avatar.php') ||
        lower.contains('/uc_server/avatar') ||
        classes.contains('top_tximg') ||
        classes.contains('avatar')) {
      return false;
    }

    var insidePostBody = false;
    var insideAttachmentContainer = false;
    html_dom.Element? parent = image.parent;
    while (parent != null) {
      final parentClasses =
          parent.classes.map((value) => value.toLowerCase()).toList();
      if (parentClasses.any(
        (value) =>
            value.contains('comiis_message') ||
            value.contains('comiis_postimg') ||
            value == 't_f',
      )) {
        insidePostBody = true;
      }
      if (parentClasses.any(
        (value) =>
            value.contains('attachment') ||
            value.contains('attachlist') ||
            value.contains('comiis_attach') ||
            value == 'comiis_img_list' ||
            value == 't_att' ||
            value == 'pattl',
      )) {
        insideAttachmentContainer = true;
      }
      parent = parent.parent;
    }

    // 楼层补图扫描会遍历 pid 块中的所有 <img>。Comiis 会在“最新评论”
    // 以及固定楼层间插入板块/推荐模块，这些图标通常位于
    // /data/attachment/common/ 或其他普通图片 URL。过去只要 URL 以
    // .png/.jpg 结尾就会被当成帖子图片，因此出现“每隔若干楼混入板块图标”。
    //
    // 正文里的普通外链图片已经由 insidePostBody 覆盖；正文外只允许明确的
    // 帖子附件特征（forum 附件目录、aid、zoomfile/file 或附件容器）。
    return insidePostBody ||
        insideAttachmentContainer ||
        lower.contains('/data/attachment/forum/') ||
        image.attributes['aid'] != null ||
        image.attributes['zoomfile'] != null ||
        image.attributes['file'] != null ||
        classes.contains('zoom');
  }

  List<String> _extractContentImagesFromFloor(String raw, String baseUrl) {
    final fragment = html_parser.parseFragment(raw);
    final result = <String>[];

    for (final image in fragment.querySelectorAll('img')) {
      final candidate = image.attributes['zoomfile'] ??
          image.attributes['file'] ??
          image.attributes['data-original'] ??
          image.attributes['data-src'] ??
          image.attributes['src'];
      final url = _absoluteUrl(candidate, baseUrl);
      if (url == null || !_isPostContentImage(url, image)) {
        continue;
      }
      if (!result.contains(url)) {
        result.add(url);
      }
    }

    return result;
  }

  List<PostContent> _extractAttachmentsFromFloor(
    String raw,
    String baseUrl,
  ) {
    final fragment = html_parser.parseFragment(raw);
    final result = <PostContent>[];
    final seen = <String>{};

    for (final anchor in fragment.querySelectorAll('a')) {
      final rawHref = anchor.attributes['href'];
      if (rawHref == null || rawHref.trim().isEmpty) continue;
      final lower = rawHref.toLowerCase();
      final isAttachment = lower.contains('mod=attachment') ||
          lower.contains('attachment.php') ||
          RegExp(r'(?:[?&]|&amp;)aid=').hasMatch(lower);
      if (!isAttachment) continue;

      final wrapsPostImage = anchor.querySelectorAll('img').any((image) {
        final candidate = image.attributes['zoomfile'] ??
            image.attributes['file'] ??
            image.attributes['data-original'] ??
            image.attributes['data-src'] ??
            image.attributes['src'];
        final imageUrl = _absoluteUrl(candidate, baseUrl);
        return imageUrl != null && _isPostContentImage(imageUrl, image);
      });
      if (wrapsPostImage) continue;

      final url = _absoluteUrl(rawHref, baseUrl);
      final dedupeKey = url ?? rawHref;
      if (!seen.add(dedupeKey)) continue;

      var name = _cleanInline(anchor.text);
      if (name.isEmpty || name == '下载附件' || name == '下载') {
        name = anchor.attributes['download']?.trim() ??
            anchor.attributes['title']?.trim() ??
            '附件';
      }
      result.add(PostContent.attachment(name, url: url));
    }

    return result;
  }

  List<String> _extractImagesFromRaw(String raw, String baseUrl) {
    final result = <String>[];
    final pattern = RegExp(
      r'''<img\b[^>]*(?:zoomfile|file|data-original|data-src|src)\s*=\s*['"]([^'"]+)['"][^>]*>''',
      caseSensitive: false,
    );
    for (final match in pattern.allMatches(raw)) {
      final url = _absoluteUrl(match.group(1), baseUrl);
      if (url == null ||
          SmileyCatalog.isForumSmileyUrl(url) ||
          url.contains('/static/image/') ||
          url.contains('avatar.php') ||
          url.contains('/uc_server/avatar')) {
        continue;
      }
      if (!result.contains(url)) result.add(url);
    }
    return result;
  }

  String _stripHtmlFallback(String raw) {
    var value = raw
        .replaceAll(
          RegExp(r'<script\b[^>]*>.*?</script>',
              caseSensitive: false, dotAll: true),
          ' ',
        )
        .replaceAll(
          RegExp(r'<style\b[^>]*>.*?</style>',
              caseSensitive: false, dotAll: true),
          ' ',
        )
        .replaceAll(
          RegExp(r'<i\b[^>]*class=[^>]*\bpstatus\b[^>]*>.*?</i>',
              caseSensitive: false, dotAll: true),
          ' ',
        )
        .replaceAll(
          RegExp(
            r'<br\s*/?>[ \t]*(?:\r?\n)?',
            caseSensitive: false,
          ),
          '\n',
        )
        .replaceAll(RegExp(r'<[^>]+>'), ' ');

    return _cleanMultiline(value);
  }

  String? _extractFormhash(String body) {
    final js = RegExp(
      r'''formhash\s*=\s*['"]([a-fA-F0-9]+)['"]''',
      caseSensitive: false,
    ).firstMatch(body);
    if (js != null) return js.group(1);

    final input = RegExp(
      r'''name\s*=\s*['"]formhash['"][^>]*value\s*=\s*['"]([a-fA-F0-9]+)['"]''',
      caseSensitive: false,
    ).firstMatch(body);
    if (input != null) return input.group(1);

    final valueFirst = RegExp(
      r'''value\s*=\s*['"]([a-fA-F0-9]+)['"][^>]*name\s*=\s*['"]formhash['"]''',
      caseSensitive: false,
    ).firstMatch(body);
    return valueFirst?.group(1);
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

  String? _cleanThreadExcerpt(String? value) {
    if (value == null) return null;

    var cleaned = _cleanInline(value);
    // 列表已经通过 hasHiddenContent 显示“隐藏”标记，摘要中继续显示
    // Discuz/Comiis 的隐藏占位提示只会重复占空间并影响阅读。这里只
    // 过滤模板提示，不尝试恢复或泄露真正的隐藏正文。
    cleaned = cleaned
        .replaceAll(
          RegExp(r'[*＊\s]*本(?:帖)?内容被作者隐藏[*＊\s]*'),
          ' ',
        )
        .replaceAll(
          RegExp(r'[*＊\s]*本帖隐藏的内容\s*[:：]?[*＊\s]*'),
          ' ',
        )
        .replaceAll(
          RegExp(r'[*＊\s]*(?:回复后可见|回复可见|查看隐藏内容)[*＊\s]*'),
          ' ',
        );
    cleaned = _cleanInline(cleaned);
    return cleaned.isEmpty ? null : cleaned;
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

  String? _nullableText(String? value) {
    if (value == null) return null;
    final cleaned = _cleanInline(value);
    return cleaned.isEmpty ? null : cleaned;
  }

  String _cleanInline(String value) {
    return value
        .replaceAll('&nbsp;', ' ')
        .replaceAll('\u00a0', ' ')
        .replaceAll(RegExp(r'[\uE000-\uF8FF\uFFFD\u25A1]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _cleanMultiline(String value) {
    return _normalizeMultiline(value).trim();
  }

  String _normalizeMultiline(String value) {
    final text = value
        .replaceAll('&nbsp;', ' ')
        .replaceAll('\u00a0', ' ')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');

    final lines = text
        .split('\n')
        .map((line) => line.replaceAll(RegExp(r'[ \t]+'), ' ').trimRight())
        .toList();

    // 连续换行来自用户正文中的多个 <br>，必须原样保留；调用方根据
    // 场景决定是否裁剪首尾。富文本节点边界不能裁剪。
    return lines.join('\n');
  }

  String? _cssProperty(String? style, String name) {
    if (style == null || style.trim().isEmpty) return null;
    final match = RegExp(
      '(?:^|;)\\s*${RegExp.escape(name)}\\s*:\\s*([^;]+)',
      caseSensitive: false,
    ).firstMatch(style);
    final value = match?.group(1)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  String? _cssBackgroundColor(String? style) {
    return _normalizeBbColor(
      _cssProperty(style, 'background-color') ??
          _cssProperty(style, 'background'),
    );
  }

  double? _htmlFontSizeScale(String? raw) {
    final size = int.tryParse(raw?.trim() ?? '');
    if (size == null) return null;
    return const <int, double>{
      1: 0.72,
      2: 0.84,
      3: 1.0,
      4: 1.15,
      5: 1.32,
      6: 1.52,
      7: 1.75,
    }[size.clamp(1, 7)];
  }

  double? _cssFontSizeScale(String? style) {
    final raw = _cssProperty(style, 'font-size')
        ?.replaceAll(RegExp(r'\s*!important\s*$', caseSensitive: false), '')
        .trim()
        .toLowerCase();
    if (raw == null || raw.isEmpty) return null;
    const named = <String, double>{
      'xx-small': 0.60,
      'x-small': 0.72,
      'small': 0.84,
      'medium': 1.0,
      'large': 1.15,
      'x-large': 1.32,
      'xx-large': 1.52,
      'smaller': 0.84,
      'larger': 1.15,
    };
    if (named.containsKey(raw)) return named[raw];
    final match = RegExp(r'^(-?\d+(?:\.\d+)?)\s*(px|pt|em|rem|%)?$')
        .firstMatch(raw);
    if (match == null) return null;
    final value = double.tryParse(match.group(1) ?? '');
    if (value == null || value <= 0) return null;
    final unit = match.group(2) ?? 'px';
    final scale = switch (unit) {
      'pt' => value / 12,
      'em' || 'rem' => value,
      '%' => value / 100,
      _ => value / 16,
    };
    return scale.clamp(0.60, 2.50).toDouble();
  }

  String? _normalizeBbColor(String? raw) {
    if (raw == null) return null;
    var value = raw
        .trim()
        .replaceAll(RegExp(r'\s*!important\s*$', caseSensitive: false), '')
        .trim();
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      value = value.substring(1, value.length - 1).trim();
    }
    if (value.isEmpty) return null;
    final hex = value.startsWith('#') ? value.substring(1) : value;
    if (RegExp(r'^[0-9a-fA-F]{3,4}$|^[0-9a-fA-F]{6}$|^[0-9a-fA-F]{8}$')
        .hasMatch(hex)) {
      return '#${hex.toUpperCase()}';
    }
    if (RegExp(r'^rgba?\([^)]*\)$', caseSensitive: false).hasMatch(value)) {
      return value.toLowerCase();
    }
    if (RegExp(r'^[a-zA-Z]+$').hasMatch(value)) {
      return value.toLowerCase();
    }
    // 非法颜色值不参与渲染，正文仍按主题默认颜色显示。
    return null;
  }

  String? _absoluteUrl(String? raw, String baseUrl) {
    if (raw == null) return null;
    final value = raw.trim();
    if (value.isEmpty) return null;
    if (value.startsWith('//')) return 'https:$value';
    if (RegExp(r'^https?://', caseSensitive: false).hasMatch(value)) {
      return value;
    }
    if (value.toLowerCase().startsWith('www.') ||
        RegExp(
          r'^(?:[A-Za-z0-9-]+\.)+[A-Za-z]{2,}(?::\d+)?(?:/|$)',
          caseSensitive: false,
        ).hasMatch(value)) {
      return 'https://$value';
    }
    if (value.startsWith('/')) return '$baseUrl$value';
    return '$baseUrl/$value';
  }
}

class _InlineStyle {
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strikethrough;
  final String? color;
  final String? backgroundColor;
  final String? fontFamily;
  final double? fontSizeScale;

  const _InlineStyle({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strikethrough = false,
    this.color,
    this.backgroundColor,
    this.fontFamily,
    this.fontSizeScale,
  });

  _InlineStyle copyWith({
    bool? bold,
    bool? italic,
    bool? underline,
    bool? strikethrough,
    String? color,
    String? backgroundColor,
    String? fontFamily,
    double? fontSizeScale,
  }) {
    return _InlineStyle(
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      underline: underline ?? this.underline,
      strikethrough: strikethrough ?? this.strikethrough,
      color: color ?? this.color,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      fontFamily: fontFamily ?? this.fontFamily,
      fontSizeScale: fontSizeScale ?? this.fontSizeScale,
    );
  }
}

class _ReplyRelation {
  final String? pid;
  final String? name;
  final String? time;
  final String? quotedText;

  const _ReplyRelation({
    this.pid,
    this.name,
    this.time,
    this.quotedText,
  });
}

class _ParsedMessage {
  final String text;
  final String? hiddenHint;
  final String? lastEditTime;
  final String? lastEditor;
  final List<String> images;
  final List<PostContent> contents;

  const _ParsedMessage({
    required this.text,
    this.hiddenHint,
    this.lastEditTime,
    this.lastEditor,
    this.images = const [],
    this.contents = const [],
  });
}
