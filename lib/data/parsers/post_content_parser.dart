part of '../forum_parser.dart';

extension ForumParserPostContentParserPart on ForumParser {
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
      final direct = HtmlText.imageSourceOf(element) ?? element.attributes['data'];
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
      final candidate = HtmlText.imageSourceOf(image);
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
          final rawUrl = HtmlText.imageSourceOf(node);
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

    // 板块 / 推荐模块的图标固定放在 /data/attachment/common/ 下，
    // 每个帖子页都会在楼层之间插入十来个（版本发布、插件交流、综合交流…），
    // 它们同样带 comiis_loadimages（懒加载），所以必须在最前面直接排除，
    // 否则会被当成正文图片混进评论区，表现为"每隔几楼出现一排板块图标"。
    if (lower.contains('/data/attachment/common/')) return false;

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
        // 克米懒加载：src 是占位图，真实地址在这个私有属性上
        image.attributes['comiis_loadimages'] != null ||
        classes.contains('zoom');
  }

  List<String> _extractContentImagesFromFloor(String raw, String baseUrl) {
    final fragment = html_parser.parseFragment(raw);
    final result = <String>[];

    for (final image in fragment.querySelectorAll('img')) {
      final candidate = HtmlText.imageSourceOf(image);
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
        final candidate = HtmlText.imageSourceOf(image);
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
    // comiis_loadimages 是克米模板懒加载的真实地址（src 只是占位图），
    // 必须参与匹配；顺序放在 src 之前，让模板把两者都写出来时优先取它。
    final pattern = RegExp(
      r'''<img\b[^>]*(?:comiis_loadimages|data-lazy-src|zoomfile|file|data-original|data-src|src)\s*=\s*['"]([^'"]+)['"][^>]*>''',
      caseSensitive: false,
    );
    for (final match in pattern.allMatches(raw)) {
      final rawCandidate = match.group(1) ?? '';
      if (HtmlText.isPlaceholderImage(rawCandidate)) continue;
      final url = _absoluteUrl(rawCandidate, baseUrl);
      if (url == null ||
          HtmlText.isPlaceholderImage(url) ||
          SmileyCatalog.isForumSmileyUrl(url) ||
          url.contains('/static/image/') ||
          url.contains('/data/attachment/common/') ||
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
}
