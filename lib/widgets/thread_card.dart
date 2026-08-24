import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';

/// 全局统一帖子列表卡片。
///
/// 首页、板块、搜索、我的内容、用户主页内容、收藏帖子统一使用这一套
/// 信息层级，避免后续再次出现“同一个帖子在不同页面长得完全不一样”。
class ThreadCard extends StatelessWidget {
  final Thread thread;
  final VoidCallback onTap;

  const ThreadCard({
    super.key,
    required this.thread,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final thumbs = thread.thumbnails;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      thread.title?.trim().isNotEmpty == true
                          ? thread.title!.trim()
                          : '未知标题',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.30,
                        letterSpacing: 0.05,
                      ),
                    ),
                  ),
                  if (thread.hasHiddenContent) ...[
                    const SizedBox(width: 8),
                    const _HiddenBadge(),
                  ],
                ],
              ),
              if (thread.excerpt?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 7),
                Text(
                  thread.excerpt!.trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                    height: 1.42,
                  ),
                ),
              ],
              // 规则：少于 3 张完全不外显，有 3 张及以上固定展示前三张。
              if (thumbs.length >= 3) ...[
                const SizedBox(height: 11),
                _ThumbnailStrip(thumbs: thumbs.take(3).toList()),
              ],
              const SizedBox(height: 11),
              Row(
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: colors.secondaryContainer,
                    backgroundImage: thread.avatarUrl?.isNotEmpty == true
                        ? CachedNetworkImageProvider(thread.avatarUrl!)
                        : null,
                    child: thread.avatarUrl?.isNotEmpty == true
                        ? null
                        : Text(
                            _initial(thread.authorName),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colors.onSecondaryContainer,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            thread.authorName?.trim().isNotEmpty == true
                                ? thread.authorName!.trim()
                                : '匿名',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (thread.forumName?.trim().isNotEmpty == true) ...[
                          const SizedBox(width: 7),
                          Container(
                            constraints: const BoxConstraints(maxWidth: 112),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: colors.primaryContainer.withValues(alpha: 0.70),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              thread.forumName!.trim(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colors.onPrimaryContainer,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (thread.lastReplyTime?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.schedule_rounded, size: 13, color: colors.outline),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        thread.lastReplyTime!.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.outline,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              Divider(
                height: 1,
                color: colors.outlineVariant.withValues(alpha: 0.55),
              ),
              const SizedBox(height: 9),
              Row(
                children: [
                  Expanded(
                    child: _Stat(
                      icon: Icons.thumb_up_alt_outlined,
                      label: '点赞',
                      value: _statValue(thread.likeCount),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _Stat(
                      icon: Icons.chat_bubble_outline_rounded,
                      label: '评论',
                      value: _statValue(thread.replyCount),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _Stat(
                      icon: Icons.visibility_outlined,
                      label: '阅读',
                      value: _statValue(thread.viewCount),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _statValue(String? value) {
    final clean = value?.trim() ?? '';
    return clean.isEmpty ? '—' : clean;
  }

  static String _initial(String? name) {
    final value = name?.trim() ?? '';
    if (value.isEmpty) return '?';
    return value.substring(0, 1);
  }
}

class _ThumbnailStrip extends StatelessWidget {
  final List<String> thumbs;

  const _ThumbnailStrip({required this.thumbs});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: AspectRatio(
                aspectRatio: 1.18,
                child: CachedNetworkImage(
                  imageUrl: thumbs[i],
                  fit: BoxFit.cover,
                  fadeInDuration: const Duration(milliseconds: 120),
                  placeholder: (_, __) => Container(
                    color: colors.surfaceContainerHighest,
                  ),
                  errorWidget: (_, __, ___) => Container(
                    color: colors.surfaceContainerHighest,
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.broken_image_outlined,
                      size: 19,
                      color: colors.outline,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _HiddenBadge extends StatelessWidget {
  const _HiddenBadge();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.tertiaryContainer.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.lock_outline_rounded,
            size: 12,
            color: colors.onTertiaryContainer,
          ),
          const SizedBox(width: 3),
          Text(
            '隐藏',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.onTertiaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _Stat({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: colors.onSurfaceVariant),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              '$label $value',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
