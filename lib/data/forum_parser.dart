import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;

import '../models/models.dart';

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
      final titleLink = el.querySelector(
        '.mmlist_li_box h2 a, h2 a[href*="thread-"]',
      );
      final href = titleLink?.attributes['href'] ?? '';
      final tid = RegExp(r'thread-(\d+)-?').firstMatch(href)?.group(1);
      if (tid == null || tid.isEmpty) continue;

      final authorEl = el.querySelector('.top_user');
      final authorHref = authorEl?.attributes['href'] ?? '';
      final authorUid =
          RegExp(r'uid=(\d+)').firstMatch(authorHref)?.group(1);

      final forumEl = el.querySelector('a[href*="forum-"]');
      final forumHref = forumEl?.attributes['href'] ?? '';
      final forumId = RegExp(r'forum-(\d+)').firstMatch(forumHref)?.group(1);

      final bottomText = el.querySelector('.comiis_znalist_bottom')?.text ?? '';
      final viewCount =
          RegExp(r'(\d+)\s*阅读').firstMatch(bottomText)?.group(1);
      final replyCount =
          RegExp(r'(\d+)\s*评论').firstMatch(bottomText)?.group(1);
      final likeCount = RegExp(r'num-all_\d+[^>]*>\s*(\d+)')
          .firstMatch(el.innerHtml)
          ?.group(1);

      String? avatarUrl;
      final avatarEl = el.querySelector('img.top_tximg, .top_tximg img');
      avatarUrl = _absoluteUrl(
        avatarEl?.attributes['src'] ?? avatarEl?.attributes['data-src'],
        baseUrl,
      );

      final timeEl = el.querySelector('.forumlist_li_time .f_d, span.f_d');

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
        excerpt: _nullableText(el.querySelector('.list_body a')?.text),
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

    return ThreadDetail(
      tid: tid,
      title: title,
      posts: posts,
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

      final isOp = page == 1 && posts.isEmpty;
      final floorText = _cleanInline(
        fragment.querySelector('.f_d.y')?.text ?? '',
      );
      final explicitFloor =
          RegExp(r'(\d+)\s*#').firstMatch(floorText)?.group(1);
      final floor = explicitFloor ??
          (isOp ? '1' : '${(page - 1) * 10 + posts.length + 1}');

      final replyToMatch = RegExp(
        r'^\s*回复\s+(.+?)\s+发表于',
        caseSensitive: false,
      ).firstMatch(parsedMessage.text);

      final repquote = fragment.querySelector('a[href*="repquote="]');
      final repquotePid = RegExp(r'repquote=(\d+)')
          .firstMatch(repquote?.attributes['href'] ?? '')
          ?.group(1);

      posts.add(Post(
        pid: pid,
        authorUid: authorUid,
        authorName: _nullableText(authorEl?.text),
        authorLevel: _nullableText(fragment.querySelector('.top_lev')?.text),
        avatarUrl: avatarUrl,
        content: parsedMessage.text,
        floor: floor,
        postTime: _nullableText(fragment.querySelector('.kmtime')?.text),
        isOp: isOp,
        images: parsedMessage.images,
        richContent: parsedMessage.contents,
        repquotePid: repquotePid,
        replyToName: replyToMatch?.group(1)?.trim(),
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
        fragment.querySelector('[class*="comiis_message_table"]');

    if (message == null) {
      final fallbackText = _stripHtmlFallback(raw);
      return _ParsedMessage(
        text: fallbackText,
        images: _extractImagesFromRaw(raw, baseUrl),
        contents: _parseBbCodeText(
          fallbackText,
          baseUrl: baseUrl,
        ),
      );
    }

    final images = <String>[];
    for (final image in message.querySelectorAll('.comiis_postimg img, img')) {
      final candidate = image.attributes['file'] ??
          image.attributes['data-src'] ??
          image.attributes['src'];
      final normalized = _absoluteUrl(candidate, baseUrl);
      if (normalized == null ||
          normalized.contains('smiley') ||
          normalized.contains('/static/image/smiley/')) {
        continue;
      }

      if (!images.contains(normalized)) {
        images.add(normalized);
      }
    }

    String? hiddenHint;
    for (final quote in message.querySelectorAll('.comiis_quote').toList()) {
      final text = _cleanInline(quote.text);

      if (_isHiddenPrompt(text)) {
        hiddenHint ??= text;
        quote.remove();
      }
    }

    for (final node
        in message.querySelectorAll('script, style, .pstatus').toList()) {
      node.remove();
    }

    final contents = _parseRichContent(
      message,
      baseUrl: baseUrl,
    );

    var cleanedHtml = message.innerHtml
        .replaceAll(
          RegExp(r'<br\s*/?>', caseSensitive: false),
          '\n',
        )
        .replaceAll(
          RegExp(
            r'</(?:div|p|li|ol|ul|blockquote|pre)>',
            caseSensitive: false,
          ),
          '\n',
        )
        .replaceAll(RegExp(r'<[^>]+>'), ' ');

    var text = _cleanMultiline(cleanedHtml);
    if (text.isEmpty) {
      text = _stripHtmlFallback(raw);
    }

    return _ParsedMessage(
      text: text,
      hiddenHint: hiddenHint,
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

      final value = _cleanMultiline(textBuffer.toString());
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

    void processNode(html_dom.Node node) {
      if (node is html_dom.Text) {
        textBuffer.write(node.text);
        return;
      }

      if (node is! html_dom.Element) {
        return;
      }

      final tag = (node.localName ?? '').toLowerCase();
      final classes = node.classes;

      if (classes.contains('comiis_blockcode')) {
        flushText();
        final code = codeText(node);
        if (code.isNotEmpty) {
          contents.add(PostContent.code(code));
        }
        return;
      }

      if (classes.contains('comiis_quote')) {
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
          flushText();
          final bold = _cleanInline(node.text);
          if (bold.isNotEmpty) {
            contents.add(PostContent.bold(bold));
          }
          return;

        case 'a':
          final href = _absoluteUrl(node.attributes['href'], baseUrl);
          final label = _cleanInline(node.text);

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
          final rawUrl = node.attributes['file'] ??
              node.attributes['data-src'] ??
              node.attributes['src'];
          final url = _absoluteUrl(rawUrl, baseUrl);
          if (url == null || url.isEmpty) {
            return;
          }

          flushText();

          final isEmoji =
              node.attributes['smilieid'] != null ||
              url.contains('/static/image/smiley/') ||
              url.contains('smiley');

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
    }

    for (final node in root.nodes) {
      processNode(node);
    }

    flushText();
    return _normalizeRichContents(contents);
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
      r'|\[free\](.*?)\[/free\]',
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
        result.add(PostContent.image(url));
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

  void _appendLinkifiedText(
    List<PostContent> output,
    String input, {
    required String baseUrl,
  }) {
    if (input.isEmpty) {
      return;
    }

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

    for (final item in input) {
      if (item.type == PostContentType.text) {
        final text = _cleanMultiline(item.text);
        if (text.isEmpty) {
          continue;
        }

        if (result.isNotEmpty &&
            result.last.type == PostContentType.text) {
          final previous = result.removeLast();
          result.add(
            PostContent.text(
              _cleanMultiline('${previous.text}\n$text'),
            ),
          );
        } else {
          result.add(PostContent.text(text));
        }
      } else {
        result.add(item);
      }
    }

    return result;
  }

  List<String> _extractImagesFromRaw(String raw, String baseUrl) {
    final result = <String>[];
    final pattern = RegExp(
      r'''<img\b[^>]*(?:src|file|data-src)\s*=\s*['"]([^'"]+)['"][^>]*>''',
      caseSensitive: false,
    );
    for (final match in pattern.allMatches(raw)) {
      final url = _absoluteUrl(match.group(1), baseUrl);
      if (url == null || url.contains('smiley')) continue;
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
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
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
    return text.contains('如果您要查看本帖隐藏内容请回复') ||
        text.contains('回复后可见') ||
        text.contains('回复可见') ||
        (text.contains('隐藏内容') && text.contains('请回复'));
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
    var text = value
        .replaceAll('&nbsp;', ' ')
        .replaceAll('\u00a0', ' ')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');

    final lines = text
        .split('\n')
        .map((line) => line.replaceAll(RegExp(r'[ \t]+'), ' ').trimRight())
        .toList();

    text = lines.join('\n');
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return text.trim();
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

class _ParsedMessage {
  final String text;
  final String? hiddenHint;
  final List<String> images;
  final List<PostContent> contents;

  const _ParsedMessage({
    required this.text,
    this.hiddenHint,
    this.images = const [],
    this.contents = const [],
  });
}
