part of '../thread_detail_page.dart';

class _AttachmentCard extends StatelessWidget {
  final String name;
  final String? url;
  final VoidCallback? onOpen;

  const _AttachmentCard({
    required this.name,
    required this.url,
    required this.onOpen,
  });

  IconData _iconForName(String value) {
    final lower = value.toLowerCase();
    if (RegExp(r'\.(?:zip|rar|7z|tar|gz|xz)$').hasMatch(lower)) {
      return Icons.folder_zip_outlined;
    }
    if (RegExp(r'\.(?:apk|apks|xapk)$').hasMatch(lower)) {
      return Icons.android_rounded;
    }
    if (RegExp(r'\.(?:txt|md|log|json|xml|yaml|yml|ini|conf)$')
        .hasMatch(lower)) {
      return Icons.description_outlined;
    }
    if (RegExp(r'\.(?:pdf)$').hasMatch(lower)) {
      return Icons.picture_as_pdf_outlined;
    }
    return Icons.attach_file_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _iconForName(name),
              size: 21,
              color: colors.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  name,
                  maxLines: 2,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (url != null && url!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    '论坛附件',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.outline,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 6),
          IconButton.filledTonal(
            tooltip: onOpen == null ? '附件地址不可用' : '打开附件',
            onPressed: onOpen,
            icon: const Icon(Icons.open_in_new_rounded, size: 19),
          ),
        ],
      ),
    );
  }
}

class _MediaCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onTap;

  const _MediaCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: [
          Icon(icon, color: colors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.outline,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onTap,
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}

class _PostImages extends StatelessWidget {
  final List<String> images;
  final Function(int) onTap;
  const _PostImages({required this.images, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (images.length == 1) {
      return GestureDetector(
        onTap: () => onTap(0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: CachedNetworkImage(
            imageUrl: images.first, fit: BoxFit.cover,
            placeholder: (_, __) => Container(height: 200, color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Center(child: CircularProgressIndicator())),
            errorWidget: (_, __, ___) => const SizedBox.shrink()),
        ),
      );
    }
    return GridView.builder(
      shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 6, mainAxisSpacing: 6),
      itemCount: images.length,
      itemBuilder: (context, index) => GestureDetector(
        onTap: () => onTap(index),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CachedNetworkImage(
            imageUrl: images[index], fit: BoxFit.cover,
            placeholder: (_, __) => Container(color: Theme.of(context).colorScheme.surfaceContainerHighest),
            errorWidget: (_, __, ___) => Container(color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Icon(Icons.broken_image_outlined))),
        ),
      ),
    );
  }
}
