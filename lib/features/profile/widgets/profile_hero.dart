part of '../../../pages/profile_page.dart';

class _ProfileHero extends StatelessWidget {
  final UserProfile profile;

  const _ProfileHero({required this.profile});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final avatar = profile.avatarUrl;
    final username = profile.username?.trim().isNotEmpty == true
        ? profile.username!.trim()
        : '未知用户';

    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
        child: Column(
          children: [
            CircleAvatar(
              radius: 36,
              backgroundColor: colors.primaryContainer,
              backgroundImage: avatar?.isNotEmpty == true
                  ? CachedNetworkImageProvider(avatar!)
                  : null,
              child: avatar?.isNotEmpty == true
                  ? null
                  : Text(
                      username.substring(0, 1),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: colors.onPrimaryContainer,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                Text(
                  username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (profile.userGroup?.trim().isNotEmpty == true)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      profile.userGroup!.trim(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onPrimaryContainer,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'UID ${profile.uid}',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.outline,
              ),
            ),
            if (profile.credits != null || profile.gold != null) ...[
              const SizedBox(height: 9),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 6,
                children: [
                  if (profile.credits != null)
                    _MiniValue(
                      icon: Icons.stars_rounded,
                      text: '${profile.credits} 积分',
                    ),
                  if (profile.gold != null)
                    _MiniValue(
                      icon: Icons.monetization_on_outlined,
                      text: '${profile.gold} 金币',
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MiniValue extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MiniValue({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: colors.tertiary),
        const SizedBox(width: 4),
        Text(
          text,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: colors.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _ProfileStats extends StatelessWidget {
  final UserProfile profile;
  final VoidCallback onThreads;
  final VoidCallback onReplies;
  final VoidCallback onFriends;

  const _ProfileStats({
    required this.profile,
    required this.onThreads,
    required this.onReplies,
    required this.onFriends,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Expanded(
            child: _StatAction(
              label: '帖子',
              value: profile.threads?.toString() ?? '—',
              onTap: onThreads,
            ),
          ),
          const SizedBox(height: 38, child: VerticalDivider()),
          Expanded(
            child: _StatAction(
              label: '回复',
              value: profile.posts?.toString() ?? '—',
              onTap: onReplies,
            ),
          ),
          const SizedBox(height: 38, child: VerticalDivider()),
          Expanded(
            child: _StatAction(
              label: '好友',
              value: profile.friends?.toString() ?? '—',
              onTap: onFriends,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatAction extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _StatAction({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
