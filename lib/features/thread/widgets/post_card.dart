part of '../thread_detail_page.dart';

class _PostCard extends StatelessWidget {
  final Post post;
  final Post? replyParent;
  final bool compactFloor;
  final bool highlighted;
  final bool hideQuotedContext;
  final VoidCallback? onReplyContextTap;
  final VoidCallback onReply;
  final VoidCallback? onEdit;
  final ValueChanged<int> onImageTap;

  const _PostCard({
    required this.post,
    this.replyParent,
    this.compactFloor = false,
    this.highlighted = false,
    this.hideQuotedContext = false,
    this.onReplyContextTap,
    required this.onReply,
    this.onEdit,
    required this.onImageTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final visibleRichContent = hideQuotedContext
        ? post.richContent
            .where(
              (item) =>
                  item.type != PostContentType.quote &&
                  item.type != PostContentType.richQuote,
            )
            .toList(growable: false)
        : post.richContent;
    final content = hideQuotedContext
        ? _contentWithoutQuotedContext(post)
        : post.content.trim();
    final postTime = post.postTime?.trim() ?? '';
    final lastEditTime = post.lastEditTime?.trim() ?? '';
    final lastEditor = post.lastEditor?.trim() ?? '';
    final authorName = post.authorName?.trim() ?? '';
    final editLabel = lastEditTime.isEmpty
        ? ''
        : lastEditor.isNotEmpty &&
                lastEditor.toLowerCase() != authorName.toLowerCase()
            ? '$lastEditor 编辑于 $lastEditTime'
            : '编辑于 $lastEditTime';
    final replyParentFloor = replyParent == null
        ? ''
        : (_floorText(replyParent!.floor).isEmpty
            ? '原评论'
            : _floorText(replyParent!.floor));
    final richImageUrls = visibleRichContent
        .where((item) => item.type == PostContentType.image)
        .map((item) => item.url)
        .whereType<String>()
        .toSet();
    final detachedImages = post.images
        .where(
          (url) =>
              !richImageUrls.contains(url) &&
              !SmileyCatalog.isForumSmileyUrl(url),
        )
        .toList(growable: false);

    return Card(
      margin: compactFloor
          ? EdgeInsets.zero
          : const EdgeInsets.only(bottom: 8),
      elevation: compactFloor ? 0 : null,
      color: compactFloor
          ? (highlighted
              ? Color.alphaBlend(
                  colors.primary.withValues(alpha: 0.065),
                  colors.surface,
                )
              : colors.surface)
          : (highlighted
              ? Color.alphaBlend(
                  colors.primary.withValues(alpha: 0.10),
                  colors.surfaceContainerLow,
                )
              : colors.surfaceContainerLow),
      shape: compactFloor
          ? const RoundedRectangleBorder(borderRadius: BorderRadius.zero)
          : RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: highlighted ? colors.primary : colors.outlineVariant,
                width: highlighted ? 1.5 : 1,
              ),
            ),
      child: Padding(
        padding: compactFloor
            ? const EdgeInsets.fromLTRB(4, 11, 4, 0)
            : const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (post.isOp && !compactFloor) ...[
                  Container(
                    width: 3,
                    height: 34,
                    decoration: BoxDecoration(
                      color: colors.primary,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                InkWell(
                  customBorder: const CircleBorder(),
                  onTap: post.authorUid == null
                      ? null
                      : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => UserProfilePage(
                                uid: post.authorUid!,
                              ),
                            ),
                          ),
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: colors.surfaceContainerHighest,
                    backgroundImage: post.avatarUrl == null
                        ? null
                        : CachedNetworkImageProvider(post.avatarUrl!),
                    child: post.avatarUrl == null
                        ? Text(_initial(post.authorName))
                        : null,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              post.authorName ?? '匿名',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (post.isOp) ...[
                            const SizedBox(width: 6),
                            _Pill(text: '楼主', primary: true),
                          ],
                        ],
                      ),
                      if ((post.authorLevel?.trim().isNotEmpty ?? false) ||
                          postTime.isNotEmpty ||
                          editLabel.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 5,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (post.authorLevel != null &&
                                  post.authorLevel!.trim().isNotEmpty)
                                UserLevelBadge(
                                  text: post.authorLevel!,
                                ),
                              if (postTime.isNotEmpty)
                                _PostTimeLabel(time: postTime),
                              if (editLabel.isNotEmpty)
                                _PostEditLabel(text: editLabel),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _Pill(text: _floorText(post.floor)),
              ],
            ),
            if (replyParent != null) ...[
              const SizedBox(height: 9),
              _ReplyContextStrip(
                label: '回复 $replyParentFloor '
                    '@${replyParent!.authorName ?? post.replyToName ?? '用户'}',
                preview: replyParent!.content,
                onTap: onReplyContextTap,
              ),
            ] else if (post.replyToName?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 9),
              _ReplyContextStrip(
                label: '回复 @${post.replyToName!.trim()}',
              ),
            ],
            if (visibleRichContent.isNotEmpty) ...[
              const SizedBox(height: 10),
              _RichContentView(
                contents: visibleRichContent,
                onImageTap: (url) {
                  final index = post.images.indexOf(url);
                  if (index >= 0) {
                    onImageTap(index);
                  }
                },
              ),
            ] else if (content.isNotEmpty) ...[
              const SizedBox(height: 10),
              SelectableText(
                content,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
              ),
            ],
            if (post.hiddenHint != null && post.hiddenHint!.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: colors.tertiaryContainer.withValues(alpha: 0.30),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 16,
                      color: colors.onTertiaryContainer,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        post.hiddenHint!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onTertiaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (detachedImages.isNotEmpty) ...[
              const SizedBox(height: 10),
              _PostImages(
                images: detachedImages,
                onTap: (index) {
                  final originalIndex = post.images.indexOf(detachedImages[index]);
                  if (originalIndex >= 0) {
                    onImageTap(originalIndex);
                  }
                },
              ),
            ],
            if (!post.isOp || onEdit != null) ...[
              const SizedBox(height: 2),
              Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onEdit != null)
                      TextButton.icon(
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: const Text('编辑'),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    if (!post.isOp)
                      TextButton.icon(
                        onPressed: onReply,
                        icon: const Icon(Icons.reply_rounded, size: 16),
                        label: const Text('回复'),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                  ],
                ),
              ),
            ],
            if (compactFloor)
              Divider(
                height: 1,
                thickness: 0.8,
                color: colors.outlineVariant.withValues(alpha: 0.72),
              ),
          ],
        ),
      ),
    );
  }

  String _contentWithoutQuotedContext(Post post) {
    var value = post.content.trim();
    final quoted = post.replyQuoteText?.trim() ?? '';
    if (quoted.isNotEmpty) {
      final index = value.indexOf(quoted);
      if (index >= 0) {
        value = value.substring(index + quoted.length).trim();
      }
    }
    return value;
  }

  String _initial(String? name) {
    final value = name?.trim() ?? '';
    return value.isEmpty ? '?' : value.substring(0, 1);
  }

  String _floorText(String? floor) {
    if (floor == null || floor.isEmpty) return '';
    if (floor == '1') return '楼主';
    return '$floor楼';
  }
}

class _ReplyContextStrip extends StatelessWidget {
  final String label;
  final String? preview;
  final VoidCallback? onTap;

  const _ReplyContextStrip({
    required this.label,
    this.preview,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final previewText = (preview ?? '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(9, 7, 8, 7),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest.withValues(alpha: 0.62),
            borderRadius: BorderRadius.circular(8),
            border: Border(
              left: BorderSide(
                color: colors.primary.withValues(alpha: 0.80),
                width: 3,
              ),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (previewText.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        previewText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(
                    Icons.my_location_rounded,
                    size: 14,
                    color: colors.primary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PostTimeLabel extends StatelessWidget {
  final String time;

  const _PostTimeLabel({required this.time});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Semantics(
      label: '评论时间 $time',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.schedule_rounded,
            size: 13,
            color: colors.outline,
          ),
          const SizedBox(width: 3),
          Text(
            time,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w500,
              height: 1.15,
            ),
          ),
        ],
      ),
    );
  }
}

class _PostEditLabel extends StatelessWidget {
  final String text;

  const _PostEditLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Semantics(
      label: '帖子$text',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.edit_outlined,
            size: 13,
            color: colors.outline,
          ),
          const SizedBox(width: 3),
          Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w500,
              height: 1.15,
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final bool primary;

  const _Pill({required this.text, this.primary = false});

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: primary ? colors.primaryContainer : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: primary ? colors.onPrimaryContainer : colors.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
