part of '../../../pages/notice_page.dart';

class _NoticeCard extends StatelessWidget {
  final NoticeItem item;
  final String sectionLabel;
  final VoidCallback onOpen;
  final VoidCallback? onIgnore;
  final Post? replyPreview;
  final bool hasLocalAction;
  final VoidCallback? onPokeBack;

  const _NoticeCard({
    required this.item,
    required this.sectionLabel,
    required this.onOpen,
    this.replyPreview,
    this.onIgnore,
    this.hasLocalAction = false,
    this.onPokeBack,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final title = item.isSystem
        ? sectionLabel
        : (item.username.isEmpty ? sectionLabel : item.username);
    final canOpen =
        hasLocalAction || item.targetUrl != null || item.hasThreadTarget;
    final action = item.actionText.isEmpty ? item.content : item.actionText;

    return Card(
      margin: EdgeInsets.zero,
      color: item.isUnread
          ? Color.alphaBlend(
              colors.primary.withValues(alpha: 0.055),
              colors.surfaceContainerLow,
            )
          : colors.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: canOpen ? onOpen : null,
        onLongPress: onIgnore,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(11, 11, 11, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _NoticeAvatar(item: item),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (item.isUnread) ...[
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  color: colors.primary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 7),
                            ],
                            Expanded(
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            if (item.time.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Text(
                                item.time,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colors.outline,
                                ),
                              ),
                            ],
                            if (onIgnore != null) ...[
                              const SizedBox(width: 3),
                              SizedBox(
                                width: 32,
                                height: 32,
                                child: IconButton(
                                  tooltip: '忽略这条通知',
                                  onPressed: onIgnore,
                                  padding: EdgeInsets.zero,
                                  visualDensity: VisualDensity.compact,
                                  iconSize: 18,
                                  color: colors.outline,
                                  icon: const Icon(
                                    Icons.notifications_off_outlined,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (action.trim().isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            action.trim(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (replyPreview != null) ...[
                const SizedBox(height: 8),
                _NoticeReplyPreview(post: replyPreview!),
              ],
              if (canOpen) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: colors.primaryContainer.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        hasLocalAction
                            ? Icons.group_add_outlined
                            : item.hasThreadTarget
                                ? Icons.article_outlined
                                : Icons.open_in_new_rounded,
                        size: 16,
                        color: colors.primary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          item.targetTitle ??
                              (hasLocalAction
                                  ? '处理好友申请'
                                  : item.hasThreadTarget
                                      ? '查看相关帖子'
                                      : '查看相关页面'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: colors.primary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: colors.primary,
                      ),
                    ],
                  ),
                ),
              ],
              if (onPokeBack != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: ActionChip(
                    onPressed: onPokeBack,
                    visualDensity: VisualDensity.compact,
                    avatar: Icon(
                      Icons.waving_hand_outlined,
                      size: 17,
                      color: colors.primary,
                    ),
                    label: const Text('回打招呼'),
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

class _NoticeReplyPreview extends StatelessWidget {
  final Post post;

  const _NoticeReplyPreview({required this.post});

  int get _imageCount {
    final seen = <String>{};

    void collect(Iterable<PostContent> contents) {
      for (final content in contents) {
        if (content.type == PostContentType.image) {
          final url = content.url?.trim() ?? '';
          if (url.isNotEmpty) seen.add(url);
        }
        if (content.children.isNotEmpty) collect(content.children);
      }
    }

    collect(post.richContent);
    for (final rawUrl in post.images) {
      final url = rawUrl.trim();
      if (url.isNotEmpty) seen.add(url);
    }
    return seen.length;
  }

  String get _summary {
    var value = ApiService.buildPostPreview(post).trim();
    if (value.isEmpty) return '';

    // 通知只做快速预览，不把图片占位符或大段换行带进卡片。
    value = value
        .replaceAll(RegExp(r'\[图片\]', caseSensitive: false), ' ')
        .replaceAll(
          RegExp(r'\[img\][\s\S]*?\[/img\]', caseSensitive: false),
          ' ',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return value;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = _summary;
    final imageCount = _imageCount;

    if (text.isEmpty && imageCount == 0) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(9),
        border: Border(
          left: BorderSide(
            color: colors.primary.withValues(alpha: 0.72),
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (text.isNotEmpty)
            Text(
              text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
                height: 1.42,
              ),
            ),
          if (imageCount > 0) ...[
            if (text.isNotEmpty) const SizedBox(height: 5),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.image_outlined,
                  size: 14,
                  color: colors.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  imageCount == 1 ? '含图片' : '含 $imageCount 张图片',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _NoticeAvatar extends StatelessWidget {
  final NoticeItem item;

  const _NoticeAvatar({required this.item});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final url = item.avatarUrl;

    if (item.isSystem) {
      return CircleAvatar(
        radius: 20,
        backgroundColor: colors.tertiaryContainer,
        child: Icon(
          Icons.campaign_outlined,
          color: colors.onTertiaryContainer,
        ),
      );
    }

    if (url == null || url.isEmpty) {
      return CircleAvatar(
        radius: 20,
        backgroundColor: colors.secondaryContainer,
        child: Icon(
          Icons.person_outline_rounded,
          color: colors.onSecondaryContainer,
        ),
      );
    }

    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: url,
        width: 40,
        height: 40,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(
          width: 40,
          height: 40,
          color: colors.surfaceContainerHighest,
        ),
        errorWidget: (_, __, ___) => Container(
          width: 40,
          height: 40,
          color: colors.secondaryContainer,
          alignment: Alignment.center,
          child: Icon(
            Icons.person_outline_rounded,
            color: colors.onSecondaryContainer,
          ),
        ),
      ),
    );
  }
}

class _NoticeEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Future<void> Function()? action;

  const _NoticeEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: colors.outline),
            const SizedBox(height: 12),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.outline,
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: () => action!(),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('重试'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NoticeSection {
  final String label;
  final String view;
  final IconData icon;
  final List<_NoticeSubtype> subtypes;

  const _NoticeSection({
    required this.label,
    required this.view,
    required this.icon,
    this.subtypes = const [],
  });
}

class _NoticeSubtype {
  final String label;
  final String type;

  const _NoticeSubtype(this.label, this.type);
}
