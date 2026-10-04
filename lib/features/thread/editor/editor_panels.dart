part of '../../../pages/thread_editor_page.dart';

enum _EditorPanel { none, smiley, mention, insert, attachment, advanced }

class _ForumHeader extends StatelessWidget {
  final String forumName;
  final ColorScheme colors;

  const _ForumHeader({required this.forumName, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colors.primaryContainer.withValues(alpha: 0.48),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: [
            Icon(Icons.forum_outlined, size: 18, color: colors.primary),
            const SizedBox(width: 8),
            Text(
              '发布到',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                forumName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: colors.onPrimaryContainer,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThreadTypeSelector extends StatelessWidget {
  final List<ThreadTypeOption> options;
  final String selectedId;
  final ValueChanged<String> onSelected;

  const _ThreadTypeSelector({
    required this.options,
    required this.selectedId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(Icons.sell_outlined, size: 18, color: colors.primary),
            const SizedBox(width: 8),
            Text(
              '主题分类',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 7,
                  runSpacing: 6,
                  children: [
                    for (final option in options)
                      ChoiceChip(
                        label: Text(option.name),
                        selected: option.id == selectedId,
                        showCheckmark: false,
                        avatar: option.id == '58'
                            ? const Icon(Icons.check_circle_outline, size: 16)
                            : option.id == '59'
                                ? const Icon(Icons.help_outline_rounded, size: 16)
                                : null,
                        onSelected: (_) => onSelected(option.id),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditorModeBar extends StatelessWidget {
  final _EditorPanel selected;
  final ValueChanged<_EditorPanel> onSelected;

  const _EditorModeBar({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final items = <({
      _EditorPanel panel,
      IconData icon,
      String label,
    })>[
      (
        panel: _EditorPanel.smiley,
        icon: Icons.sentiment_satisfied_alt_outlined,
        label: '表情',
      ),
      (panel: _EditorPanel.mention, icon: Icons.alternate_email, label: '@好友'),
      (panel: _EditorPanel.insert, icon: Icons.send_outlined, label: '插入'),
      (panel: _EditorPanel.attachment, icon: Icons.attach_file, label: '附件'),
      (panel: _EditorPanel.advanced, icon: Icons.tune_rounded, label: '高级'),
    ];

    final colors = Theme.of(context).colorScheme;
    return Container(
      color: colors.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: Row(
        children: [
          for (final item in items)
            Expanded(
              child: _ModeButton(
                icon: item.icon,
                label: item.label,
                selected: selected == item.panel,
                onTap: () => onSelected(item.panel),
              ),
            ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ModeButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = selected ? colors.primary : colors.onSurfaceVariant;
    return InkResponse(
      onTap: onTap,
      radius: 28,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 24, color: foreground),
            const SizedBox(height: 2),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: foreground,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
