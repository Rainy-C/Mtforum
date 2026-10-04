part of '../../../pages/account/private_messages_page.dart';

class _PmSmileyEditingController extends TextEditingController {
  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final spans = <InlineSpan>[];
    final buffer = StringBuffer();

    void flushText() {
      if (buffer.isEmpty) return;
      spans.add(TextSpan(text: buffer.toString(), style: style));
      buffer.clear();
    }

    for (final codeUnit in text.codeUnits) {
      final url = SmileyCatalog.urlForCodeUnit(codeUnit);
      if (url == null) {
        buffer.writeCharCode(codeUnit);
        continue;
      }
      flushText();
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: CachedNetworkImage(
            imageUrl: url,
            width: 26,
            height: 26,
            fit: BoxFit.contain,
            errorWidget: (_, __, ___) => const SizedBox(
              width: 26,
              height: 26,
              child: Icon(Icons.sentiment_satisfied_alt_rounded, size: 20),
            ),
          ),
        ),
      );
    }
    flushText();
    return TextSpan(style: style, children: spans);
  }
}

class _PmSmileyPicker extends StatelessWidget {
  final ValueChanged<String> onSelected;

  const _PmSmileyPicker({required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DefaultTabController(
      length: SmileyCatalog.packs.length,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          border: Border(top: BorderSide(color: colors.outlineVariant)),
        ),
        child: Column(
          children: [
            TabBar(
              dividerHeight: 1,
              tabs: [
                for (final pack in SmileyCatalog.packs)
                  Tab(text: '${pack.title}  ${pack.urls.length}'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  for (final pack in SmileyCatalog.packs)
                    GridView.builder(
                      padding: const EdgeInsets.all(8),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 54,
                        mainAxisSpacing: 4,
                        crossAxisSpacing: 4,
                      ),
                      itemCount: pack.urls.length,
                      itemBuilder: (context, index) {
                        final url = pack.urls[index];
                        return InkWell(
                          borderRadius: BorderRadius.circular(9),
                          onTap: () => onSelected(url),
                          child: Center(
                            child: CachedNetworkImage(
                              imageUrl: url,
                              width: 32,
                              height: 32,
                              fit: BoxFit.contain,
                              errorWidget: (_, __, ___) => Icon(
                                Icons.broken_image_outlined,
                                size: 19,
                                color: colors.outline,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
