import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/message_badge_service.dart';
import 'account/private_messages_page.dart';
import 'account/social_center_page.dart';
import 'notice_page.dart';

/// 消息中心：论坛通知、私信、好友申请统一入口。
class MessagesPage extends StatefulWidget {
  const MessagesPage({super.key});

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  final _api = ApiService.instance;
  final _badges = MessageBadgeService.instance;

  @override
  void initState() {
    super.initState();
    _api.addLoginListener(_onLoginChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    _api.removeLoginListener(_onLoginChanged);
    super.dispose();
  }

  void _onLoginChanged() {
    if (_api.isLoggedIn) {
      _refresh(force: true);
    } else {
      _badges.clear();
    }
  }

  Future<void> _refresh({bool force = true}) => _badges.refresh(force: force);

  Future<void> _open(Widget page) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
    if (mounted) await _refresh(force: true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: _badges,
      builder: (context, _) {
        final summary = _badges.summary;
        return Scaffold(
          body: RefreshIndicator(
            onRefresh: () => _refresh(force: true),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverAppBar.large(
                  title: const Text('消息'),
                  pinned: true,
                  actions: [
                    IconButton(
                      tooltip: '刷新未读状态',
                      onPressed: _badges.refreshing
                          ? null
                          : () => _refresh(force: true),
                      icon: _badges.refreshing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      _MessageEntryCard(
                        icon: Icons.notifications_none_rounded,
                        iconBackground: colors.tertiaryContainer,
                        iconForeground: colors.onTertiaryContainer,
                        title: '论坛通知',
                        subtitle: '帖子回复、@我、互动和系统提醒',
                        badge: summary.notices.label,
                        onTap: () => _open(const NoticePage()),
                      ),
                      const SizedBox(height: 12),
                      _MessageEntryCard(
                        icon: Icons.chat_bubble_outline_rounded,
                        iconBackground: colors.primaryContainer,
                        iconForeground: colors.onPrimaryContainer,
                        title: '私信',
                        subtitle: '查看会话和发送私信',
                        badge: summary.privateMessages.label,
                        onTap: () => _open(const PrivateMessagesPage()),
                      ),
                      const SizedBox(height: 12),
                      _MessageEntryCard(
                        icon: Icons.group_add_outlined,
                        iconBackground: colors.secondaryContainer,
                        iconForeground: colors.onSecondaryContainer,
                        title: '好友申请',
                        subtitle: '直接查看和处理待处理请求',
                        badge: summary.friendRequests.label,
                        onTap: () => _open(const FriendRequestsPage()),
                      ),
                      if (!_api.isLoggedIn) ...[
                        const SizedBox(height: 18),
                        _LoginHint(colors: colors),
                      ],
                    ]),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MessageEntryCard extends StatelessWidget {
  final IconData icon;
  final Color iconBackground;
  final Color iconForeground;
  final String title;
  final String subtitle;
  final String? badge;
  final VoidCallback onTap;

  const _MessageEntryCard({
    required this.icon,
    required this.iconBackground,
    required this.iconForeground,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: iconBackground,
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: iconForeground, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (badge != null) _CountBadge(label: badge!),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded, color: colors.outline),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  final String label;
  const _CountBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colors.error,
        borderRadius: BorderRadius.circular(999),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          color: colors.onError,
          fontSize: 11,
          height: 1.2,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _LoginHint extends StatelessWidget {
  final ColorScheme colors;
  const _LoginHint({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline_rounded, color: colors.onSurfaceVariant),
          const SizedBox(width: 12),
          const Expanded(child: Text('登录论坛后才能读取私信、好友申请和通知未读数。')),
        ],
      ),
    );
  }
}
