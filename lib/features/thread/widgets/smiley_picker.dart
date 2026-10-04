part of '../thread_detail_page.dart';

class _SmileyEditingController extends TextEditingController {
  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final spans = <InlineSpan>[];
    final buffer = StringBuffer();

    void flushText() {
      if (buffer.isEmpty) {
        return;
      }
      spans.add(
        TextSpan(
          text: buffer.toString(),
          style: style,
        ),
      );
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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: CachedNetworkImage(
              imageUrl: url,
              width: 26,
              height: 26,
              fit: BoxFit.contain,
              errorWidget: (_, __, ___) => const SizedBox(
                width: 26,
                height: 26,
                child: Icon(
                  Icons.sentiment_satisfied_alt_rounded,
                  size: 20,
                ),
              ),
            ),
          ),
        ),
      );
    }

    flushText();

    return TextSpan(
      style: style,
      children: spans,
    );
  }
}

class _SmileyPicker extends StatelessWidget {
  final ValueChanged<String> onSelected;

  const _SmileyPicker({
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return DefaultTabController(
      length: SmileyCatalog.packs.length,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.outlineVariant),
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
                    _SmileyGrid(
                      urls: pack.urls,
                      onSelected: onSelected,
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

class _SmileyGrid extends StatelessWidget {
  final List<String> urls;
  final ValueChanged<String> onSelected;

  const _SmileyGrid({
    required this.urls,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 58,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: urls.length,
      itemBuilder: (context, index) {
        final url = urls[index];

        return Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => onSelected(url),
            child: Center(
              child: CachedNetworkImage(
                imageUrl: url,
                width: 34,
                height: 34,
                fit: BoxFit.contain,
                placeholder: (_, __) => SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: colors.outline,
                  ),
                ),
                errorWidget: (_, __, ___) => Icon(
                  Icons.broken_image_outlined,
                  size: 20,
                  color: colors.outline,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
