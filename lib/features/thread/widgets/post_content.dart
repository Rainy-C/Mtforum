part of '../thread_detail_page.dart';

class _RichContentView extends StatelessWidget {
  final List<PostContent> contents;
  final ValueChanged<String>? onImageTap;
  final TextAlign textAlign;

  const _RichContentView({
    required this.contents,
    this.onImageTap,
    this.textAlign = TextAlign.left,
  });

  Future<void> _openUrl(BuildContext context, String url) async {
    await _openPostLink(context, url);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final widgets = <Widget>[];
    final inline = <PostContent>[];

    void flushInline() {
      if (inline.isEmpty) {
        return;
      }

      final richText = _InlineRichText(
        contents: List<PostContent>.from(inline),
        textAlign: textAlign,
      );
      widgets.add(
        textAlign == TextAlign.left
            ? richText
            : SizedBox(width: double.infinity, child: richText),
      );
      inline.clear();
    }

    for (final content in contents) {
      switch (content.type) {
        case PostContentType.text:
        case PostContentType.bold:
        case PostContentType.link:
        case PostContentType.emoji:
          inline.add(content);

        case PostContentType.image:
          flushInline();

          final url = content.url;
          if (url == null || url.isEmpty) {
            break;
          }

          widgets.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: GestureDetector(
                onTap: () => onImageTap?.call(url),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.fitWidth,
                    placeholder: (_, __) => Container(
                      constraints: const BoxConstraints(minHeight: 140),
                      color: colors.surfaceContainerHigh,
                      alignment: Alignment.center,
                      child: const CircularProgressIndicator(),
                    ),
                    errorWidget: (_, __, ___) => Container(
                      height: 120,
                      color: colors.surfaceContainerHighest,
                      alignment: Alignment.center,
                      child: const Icon(Icons.broken_image_outlined),
                    ),
                  ),
                ),
              ),
            ),
          );

        case PostContentType.quote:
          flushInline();
          widgets.add(
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(vertical: 6),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
                border: Border(
                  left: BorderSide(
                    color: colors.primary,
                    width: 3,
                  ),
                ),
              ),
              child: SelectableText(
                content.text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ),
          );

        case PostContentType.richQuote:
          flushInline();
          if (content.children.isEmpty) {
            break;
          }
          widgets.add(_RichQuoteBlock(contents: content.children));

        case PostContentType.code:
          flushInline();
          widgets.add(
            _CodeBlock(code: content.text),
          );

        case PostContentType.free:
          flushInline();
          widgets.add(
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(vertical: 6),
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: colors.secondaryContainer.withValues(alpha: 0.40),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: colors.onSecondaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SelectableText(
                      content.text,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSecondaryContainer,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );

        case PostContentType.attachment:
          flushInline();
          widgets.add(
            _AttachmentCard(
              name: content.text.trim().isEmpty ? '附件' : content.text.trim(),
              url: content.url,
              onOpen: content.url == null || content.url!.isEmpty
                  ? null
                  : () => _openUrl(context, content.url!),
            ),
          );

        case PostContentType.table:
          flushInline();
          if (content.tableRows.isNotEmpty) {
            widgets.add(
              _TableBlock(
                rows: content.tableRows,
                headerRows: content.tableHeaderRows,
              ),
            );
          }

        case PostContentType.divider:
          flushInline();
          widgets.add(
            Divider(
              height: 24,
              thickness: 1,
              color: colors.outlineVariant,
            ),
          );

        case PostContentType.aligned:
          flushInline();
          if (content.children.isNotEmpty) {
            final alignment = switch (content.alignment) {
              'center' => Alignment.center,
              'right' => Alignment.centerRight,
              _ => Alignment.centerLeft,
            };
            final alignedText = switch (content.alignment) {
              'center' => TextAlign.center,
              'right' => TextAlign.right,
              'justify' => TextAlign.justify,
              _ => TextAlign.left,
            };
            widgets.add(
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Align(
                  alignment: alignment,
                  child: _RichContentView(
                    contents: content.children,
                    onImageTap: onImageTap,
                    textAlign: alignedText,
                  ),
                ),
              ),
            );
          }

        case PostContentType.list:
          flushInline();
          if (content.children.isNotEmpty) {
            widgets.add(
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                child: _RichContentView(
                  contents: content.children,
                  onImageTap: onImageTap,
                ),
              ),
            );
          }

        case PostContentType.audio:
          flushInline();
          if (content.url != null) {
            widgets.add(
              _MediaCard(
                icon: Icons.audiotrack_rounded,
                title: '音频',
                subtitle: content.url!,
                actionLabel: '播放',
                onTap: () => _openUrl(context, content.url!),
              ),
            );
          }

        case PostContentType.video:
          flushInline();
          if (content.url != null) {
            widgets.add(
              _MediaCard(
                icon: Icons.play_circle_outline_rounded,
                title: '视频',
                subtitle: content.url!,
                actionLabel: '播放',
                onTap: () => _openUrl(context, content.url!),
              ),
            );
          }

        case PostContentType.flash:
          flushInline();
          if (content.url != null) {
            widgets.add(
              _MediaCard(
                icon: Icons.extension_off_outlined,
                title: 'Flash 内容',
                subtitle: 'Android 已不原生支持 Flash · 点击尝试外部打开',
                actionLabel: '打开',
                onTap: () => _openUrl(context, content.url!),
              ),
            );
          }
      }
    }

    flushInline();

    // 让整段帖子正文进入同一个选择区域，普通文字、引用、链接前后
    // 的内容都可以长按框选/复制；图片和链接点击行为保持不变。
    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: widgets,
      ),
    );
  }
}

class _RichQuoteBlock extends StatelessWidget {
  final List<PostContent> contents;

  const _RichQuoteBlock({required this.contents});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final firstText = contents.isEmpty ? '' : contents.first.text.trim();
    final isHidden = firstText.contains('本帖隐藏的内容') ||
        firstText.contains('隐藏内容');

    if (!isHidden) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
          border: Border(
            left: BorderSide(color: colors.primary, width: 3),
          ),
        ),
        child: _InlineRichText(contents: contents),
      );
    }

    final body = contents.skip(1).toList(growable: true);
    while (body.isNotEmpty &&
        body.first.type == PostContentType.text &&
        body.first.text.trim().isEmpty) {
      body.removeAt(0);
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            firstText.isEmpty ? '本帖隐藏的内容:' : firstText,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.tertiary,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (body.isNotEmpty) ...[
            const SizedBox(height: 7),
            _InlineRichText(contents: body),
          ],
        ],
      ),
    );
  }
}

class _InlineRichText extends StatefulWidget {
  final List<PostContent> contents;
  final TextAlign textAlign;

  const _InlineRichText({
    required this.contents,
    this.textAlign = TextAlign.left,
  });

  @override
  State<_InlineRichText> createState() => _InlineRichTextState();
}

class _InlineRichTextState extends State<_InlineRichText> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  Future<void> _openUrl(String url) async {
    await _openPostLink(context, url);
  }

  @override
  void didUpdateWidget(_InlineRichText oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 只在内容真正变化时才重建手势识别器，避免每次 build 都 dispose+重建导致闪烁。
    if (!_sameContents(oldWidget.contents, widget.contents)) {
      _disposeRecognizers();
    }
  }

  bool _sameContents(List<PostContent> a, List<PostContent> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].type != b[i].type ||
          a[i].text != b[i].text ||
          a[i].url != b[i].url ||
          a[i].isBold != b[i].isBold ||
          a[i].isItalic != b[i].isItalic ||
          a[i].isUnderline != b[i].isUnderline ||
          a[i].isStrikethrough != b[i].isStrikethrough ||
          a[i].color != b[i].color ||
          a[i].backgroundColor != b[i].backgroundColor ||
          a[i].fontFamily != b[i].fontFamily ||
          a[i].fontSizeScale != b[i].fontSizeScale) {
        return false;
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final baseStyle = theme.textTheme.bodyMedium?.copyWith(height: 1.55);
    final spans = <InlineSpan>[];

    TextStyle? contentStyle(PostContent content, {bool link = false}) {
      final decorations = <TextDecoration>[];
      if (content.isUnderline || link) decorations.add(TextDecoration.underline);
      if (content.isStrikethrough) decorations.add(TextDecoration.lineThrough);
      final parsedColor = _parseBbColor(content.color);
      final parsedBackground = _parseBbColor(content.backgroundColor);
      return baseStyle?.copyWith(
        color: parsedColor ?? (link ? colors.primary : null),
        backgroundColor: parsedBackground,
        fontWeight: content.isBold || content.type == PostContentType.bold
            ? FontWeight.w700
            : null,
        fontStyle: content.isItalic ? FontStyle.italic : null,
        decoration: decorations.isEmpty
            ? null
            : TextDecoration.combine(decorations),
        decorationColor: parsedColor ?? (link ? colors.primary : null),
        decorationThickness: decorations.isEmpty ? null : 1,
        fontFamily: content.fontFamily,
        fontSize: content.fontSizeScale == null || baseStyle?.fontSize == null
            ? null
            : baseStyle!.fontSize! * content.fontSizeScale!,
      );
    }

    for (final content in widget.contents) {
      switch (content.type) {
        case PostContentType.text:
          spans.add(
            TextSpan(
              text: content.text,
              style: contentStyle(content),
            ),
          );

        case PostContentType.bold:
          spans.add(
            TextSpan(
              text: content.text,
              style: contentStyle(content),
            ),
          );

        case PostContentType.link:
          final url = content.url;
          if (url == null || url.isEmpty) {
            spans.add(TextSpan(text: content.text, style: contentStyle(content)));
            continue;
          }

          final recognizer = TapGestureRecognizer()
            ..onTap = () => _openUrl(url);
          _recognizers.add(recognizer);

          spans.add(
            TextSpan(
              text: content.text,
              recognizer: recognizer,
              mouseCursor: SystemMouseCursors.click,
              style: contentStyle(content, link: true),
            ),
          );

        case PostContentType.emoji:
          final url = content.url;
          if (url == null || url.isEmpty) {
            continue;
          }

          spans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: CachedNetworkImage(
                  imageUrl: url,
                  width: 22,
                  height: 22,
                  errorWidget: (_, __, ___) =>
                      const SizedBox(width: 22, height: 22),
                ),
              ),
            ),
          );

        default:
          break;
      }
    }

    return RichText(
      textAlign: widget.textAlign,
      text: TextSpan(
        style: baseStyle,
        children: spans,
      ),
      selectionRegistrar: SelectionContainer.maybeOf(context),
      selectionColor: colors.primary.withValues(alpha: 0.24),
    );
  }
}
