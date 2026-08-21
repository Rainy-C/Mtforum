import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../widgets/user_level_badge.dart';
import 'private_messages_page.dart';
import 'poke_page.dart';

class UserProfilePage extends StatefulWidget {
  final String uid;

  const UserProfilePage({
    super.key,
    required this.uid,
  });

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  final _api = ApiService.instance;

  SpaceUserProfile? _profile;
  bool _loading = true;
  bool _followBusy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final profile = await _api.getSpaceUserProfile(widget.uid);
      if (mounted) setState(() => _profile = profile);
    } catch (e) {
      if (mounted) setState(() => _error = '主页加载失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleFollow() async {
    final profile = _profile;
    if (profile == null || _followBusy) return;

    if (!_api.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先登录')),
      );
      return;
    }

    setState(() => _followBusy = true);
    final wasFollowing = profile.isFollowing;
    final result = wasFollowing
        ? await _api.unfollowUser(widget.uid, ownUid: _api.currentUid)
        : await _api.followUser(widget.uid);

    if (!mounted) return;
    setState(() => _followBusy = false);

    if (result.success) {
      final oldFollowers = profile.followers;
      final int? nextFollowers = oldFollowers == null
          ? null
          : wasFollowing
              ? (oldFollowers > 0 ? oldFollowers - 1 : 0)
              : oldFollowers + 1;
      setState(() {
        _profile = profile.copyWith(
          isFollowing: !wasFollowing,
          followers: nextFollowers,
        );
      });
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );
  }

  void _notAdapted(String action) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$action 的完整写操作还没有抓包，暂不伪造请求')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_profile?.username ?? '用户主页'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading && _profile == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _profile == null
              ? _LoadError(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
                    children: [
                      _ProfileHeader(profile: _profile!),
                      const SizedBox(height: 10),
                      _ProfileStats(profile: _profile!),
                      if (_profile!.medalUrls.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _Medals(urls: _profile!.medalUrls),
                      ],
                      const SizedBox(height: 10),
                      _Actions(
                        profile: _profile!,
                        followBusy: _followBusy,
                        onFollow: _toggleFollow,
                        onFriend: _profile!.friendUrl == null
                            ? null
                            : () => _notAdapted('加好友'),
                        onPoke: _profile!.pokeUrl == null
                            ? null
                            : () => showPokeDialog(
                                  context,
                                  uid: widget.uid,
                                  username: _profile!.username,
                                ),
                        onMessage: _profile!.messageUrl == null
                            ? null
                            : () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => PmConversationPage(
                                      touid: widget.uid,
                                      initialName: _profile!.username,
                                    ),
                                  ),
                                ),
                        onBlock: () => _notAdapted('拉黑'),
                      ),
                      const SizedBox(height: 12),
                      if (_profile!.signature != null ||
                          _profile!.customTitle != null)
                        _Section(
                          title: '个人资料',
                          children: [
                            if (_profile!.signature != null)
                              _InfoRow(
                                label: '个人签名',
                                value: _profile!.signature!,
                              ),
                            if (_profile!.customTitle != null)
                              _InfoRow(
                                label: '自定义衔',
                                value: _profile!.customTitle!,
                              ),
                          ],
                        ),
                      if (_profile!.credits != null ||
                          _profile!.goodReview != null ||
                          _profile!.gold != null ||
                          _profile!.reputation != null) ...[
                        const SizedBox(height: 10),
                        _CreditGrid(profile: _profile!),
                      ],
                      const SizedBox(height: 10),
                      _Section(
                        title: '详细资料',
                        children: [
                          _InfoRow(label: '用户ID', value: _profile!.uid),
                          if (_profile!.occupation != null)
                            _InfoRow(
                              label: '职业',
                              value: _profile!.occupation!,
                            ),
                          if (_profile!.residence != null)
                            _InfoRow(
                              label: '居住地',
                              value: _profile!.residence!,
                            ),
                          if (_profile!.birthday != null)
                            _InfoRow(
                              label: '生日',
                              value: _profile!.birthday!,
                            ),
                          if (_profile!.gender != null)
                            _InfoRow(
                              label: '性别',
                              value: _profile!.gender!,
                            ),
                          if (_profile!.onlineTime != null)
                            _InfoRow(
                              label: '在线时间',
                              value: _profile!.onlineTime!,
                            ),
                          if (_profile!.registerTime != null)
                            _InfoRow(
                              label: '注册时间',
                              value: _profile!.registerTime!,
                            ),
                          if (_profile!.lastVisit != null)
                            _InfoRow(
                              label: '最后访问',
                              value: _profile!.lastVisit!,
                              showDivider: false,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _LoadError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _LoadError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final SpaceUserProfile profile;

  const _ProfileHeader({required this.profile});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Material(
        color: colors.surfaceContainerLow,
        child: Stack(
          children: [
            if (profile.backgroundUrl != null)
              Positioned.fill(
                child: CachedNetworkImage(
                  imageUrl: profile.backgroundUrl!,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            if (profile.backgroundUrl != null)
              Positioned.fill(
                child: ColoredBox(
                  color: colors.surface.withValues(alpha: 0.70),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: colors.surfaceContainerHighest,
                    backgroundImage: profile.avatarUrl == null
                        ? null
                        : CachedNetworkImageProvider(profile.avatarUrl!),
                    child: profile.avatarUrl == null
                        ? const Icon(Icons.person_rounded, size: 34)
                        : null,
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile.username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Wrap(
                          spacing: 6,
                          runSpacing: 5,
                          children: [
                            if (profile.gender != null)
                              _SmallTag(
                                icon: profile.gender!.contains('女')
                                    ? Icons.female_rounded
                                    : profile.gender!.contains('男')
                                        ? Icons.male_rounded
                                        : Icons.person_outline_rounded,
                                text: profile.gender!,
                              ),
                            if (profile.level != null)
                              UserLevelBadge(text: profile.level!),
                            if (profile.userGroup != null)
                              UserLevelBadge(text: profile.userGroup!),
                          ],
                        ),
                      ],
                    ),
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

class _SmallTag extends StatelessWidget {
  final IconData icon;
  final String text;

  const _SmallTag({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: colors.secondaryContainer.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 3),
          Text(text, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _ProfileStats extends StatelessWidget {
  final SpaceUserProfile profile;

  const _ProfileStats({required this.profile});

  @override
  Widget build(BuildContext context) {
    final values = <(String, int?)>[
      ('帖子', profile.posts),
      ('回复', profile.replies),
      ('好友', profile.friends),
      ('关注', profile.following),
      ('粉丝', profile.followers),
      ('人气', profile.popularity),
    ];

    Widget row(int start) => Row(
          children: [
            for (var i = start; i < start + 3; i++) ...[
              if (i != start) const SizedBox(width: 5),
              Expanded(
                child: _StatItem(label: values[i].$1, value: values[i].$2),
              ),
            ],
          ],
        );

    return Column(
      children: [
        row(0),
        const SizedBox(height: 5),
        row(3),
      ],
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final int? value;

  const _StatItem({required this.label, this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
        child: Column(
          children: [
            Text(
              value?.toString() ?? '-',
              maxLines: 1,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Medals extends StatelessWidget {
  final List<String> urls;

  const _Medals({required this.urls});

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: '勋章荣誉',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
          child: Wrap(
            spacing: 8,
            runSpacing: 7,
            children: [
              for (final url in urls)
                CachedNetworkImage(
                  imageUrl: url,
                  width: 28,
                  height: 28,
                  fit: BoxFit.contain,
                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Actions extends StatelessWidget {
  final SpaceUserProfile profile;
  final bool followBusy;
  final VoidCallback onFollow;
  final VoidCallback? onFriend;
  final VoidCallback? onPoke;
  final VoidCallback? onMessage;
  final VoidCallback? onBlock;

  const _Actions({
    required this.profile,
    required this.followBusy,
    required this.onFollow,
    this.onFriend,
    this.onPoke,
    this.onMessage,
    this.onBlock,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: profile.isFollowing
              ? FilledButton.tonalIcon(
                  onPressed: followBusy ? null : onFollow,
                  icon: followBusy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.done_rounded),
                  label: const Text('已关注'),
                )
              : FilledButton.icon(
                  onPressed: followBusy ? null : onFollow,
                  icon: followBusy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('关注'),
                ),
        ),
        const SizedBox(height: 7),
        Row(
          children: [
            _ActionIcon(
              icon: Icons.group_add_outlined,
              label: '加好友',
              onPressed: onFriend,
            ),
            _ActionIcon(
              icon: Icons.waving_hand_outlined,
              label: '打招呼',
              onPressed: onPoke,
            ),
            _ActionIcon(
              icon: Icons.chat_bubble_outline_rounded,
              label: '聊天',
              onPressed: onMessage,
            ),
            _ActionIcon(
              icon: Icons.block_rounded,
              label: '拉黑',
              onPressed: onBlock,
            ),
          ],
        ),
      ],
    );
  }
}

class _ActionIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  const _ActionIcon({
    required this.icon,
    required this.label,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 21),
            const SizedBox(height: 2),
            Text(label, style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}

class _CreditGrid extends StatelessWidget {
  final SpaceUserProfile profile;

  const _CreditGrid({required this.profile});

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: '积分',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Row(
            children: [
              Expanded(child: _CreditItem('积分', profile.credits)),
              Expanded(child: _CreditItem('好评', profile.goodReview)),
              Expanded(child: _CreditItem('金币', profile.gold)),
              Expanded(child: _CreditItem('信誉', profile.reputation)),
            ],
          ),
        ),
      ],
    );
  }
}

class _CreditItem extends StatelessWidget {
  final String label;
  final int? value;

  const _CreditItem(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          Text(
            value?.toString() ?? '-',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: colors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool showDivider;

  const _InfoRow({
    required this.label,
    required this.value,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 76,
                child: Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            indent: 12,
            endIndent: 12,
            color: colors.outlineVariant.withValues(alpha: 0.55),
          ),
      ],
    );
  }
}
