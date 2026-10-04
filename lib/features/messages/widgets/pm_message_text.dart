part of '../../../pages/account/private_messages_page.dart';

class _PmInlineMessageText extends StatelessWidget {
  final String text;

  const _PmInlineMessageText({required this.text});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    final spans = <InlineSpan>[];
    final buffer = StringBuffer();

    void flushText() {
      if (buffer.isEmpty) return;
      spans.add(TextSpan(text: buffer.toString()));
      buffer.clear();
    }

    void appendEmoji(String url) {
      flushText();
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: CachedNetworkImage(
              imageUrl: url,
              width: 28,
              height: 28,
              fit: BoxFit.contain,
              errorWidget: (_, __, ___) => const SizedBox(
                width: 28,
                height: 28,
                child: Icon(Icons.sentiment_satisfied_alt_rounded, size: 20),
              ),
            ),
          ),
        ),
      );
    }

    void appendTextWithMarkers(String value) {
      for (final codeUnit in value.codeUnits) {
        final url = SmileyCatalog.urlForCodeUnit(codeUnit);
        if (url == null) {
          buffer.writeCharCode(codeUnit);
        } else {
          appendEmoji(url);
        }
      }
    }

    final bbSmileyPattern = RegExp(
      r'\[img\](https?://[^\[]+)\[/img\]',
      caseSensitive: false,
    );
    var cursor = 0;
    for (final match in bbSmileyPattern.allMatches(text)) {
      if (match.start > cursor) {
        appendTextWithMarkers(text.substring(cursor, match.start));
      }
      final url = match.group(1)?.trim() ?? '';
      if (SmileyCatalog.isForumSmileyUrl(url)) {
        appendEmoji(url);
      } else {
        buffer.write(match.group(0));
      }
      cursor = match.end;
    }
    if (cursor < text.length) {
      appendTextWithMarkers(text.substring(cursor));
    }
    flushText();

    return SelectableText.rich(
      TextSpan(style: style, children: spans),
    );
  }
}
