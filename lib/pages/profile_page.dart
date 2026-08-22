import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../services/sign_service.dart';
import '../widgets/app_state_view.dart';
import 'about_page.dart';
import 'account/account_tools_page.dart';
import 'account/credits_page.dart';
import 'account/private_messages_page.dart';
import 'account/profile_edit_page.dart';
import 'account/social_center_page.dart';
import 'account/user_group_page.dart';
import 'account/wall_page.dart';
import 'favorites_page.dart';
import 'mall_page.dart';
import 'my_threads_page.dart';
import 'settings_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _api = ApiService.instance;
  UserProfile? _profile;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _api.addLoginListener(_onLoginStateChanged);
    if (_api.isLoggedIn) _loadProfile();
  }

  @override
  void dispose() {
    _api.removeLoginListener(_onLoginStateChanged);
    super.dispose();
  }

  void _onLoginStateChanged() {
    if (_api.isLoggedIn && _profile == null) {
      _loadProfile();
    } else if (!_api.isLoggedIn && mounted) {
      setState(() => _profile = null);
    }
  }

  Future<void> _loadProfile() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final profile = await _api.getProfile();
      if (!mounted) return;
      setState(() => _profile = profile);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _api.isLoggedIn ? _loadProfile : () async {},
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              title: const Text('我的'),
              pinned: true,
              actions: [
                IconButton(
                  tooltip: '刷新',
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: _api.isLoggedIn && !_loading ? _loadProfile : null,
                ),
              ],
            ),
            if (!_api.isLoggedIn)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _LoggedOutView(
                  onLogin: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SettingsPage()),
                    ).then((_) {
                      if (_api.isLoggedIn) _loadProfile();
                    });
                  },
                ),
              )
            else if (_loading && _profile == null)
              const SliverFillRemaining(child: AppStateView.loading())
            else if (_profile != null)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _ProfileHero(profile: _profile!),
                    const SizedBox(height: 12),
                    _ProfileStats(
                      profile: _profile!,
                      onThreads: () => _openMyContent('thread'),
                      onReplies: () => _openMyContent('reply'),
                      onFriends: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SocialUsersPage(
                            type: 'friend',
                            uid: _profile!.uid,
                            title: '我的好友',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const _SectionTitle('常用功能'),
                    const SizedBox(height: 9),
                    _QuickActions(
                      onMessages: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const PrivateMessagesPage(),
                        ),
                      ),
                      onFavorites: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const FavoritesPage()),
                      ),
                      onSign: _openSignPage,
                      onSocial: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SocialCenterPage(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const _SectionTitle('论坛账户'),
                    const SizedBox(height: 9),
                    _MenuGroup(
                      children: [
                        _MenuEntry(
                          icon: Icons.manage_accounts_outlined,
                          title: '编辑资料',
                          subtitle: '资料、签名与隐私设置',
                          onTap: () => Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ProfileEditPage(),
                            ),
                          ).then((changed) {
                            if (changed == true) _loadProfile();
                          }),
                        ),
                        _MenuEntry(
                          icon: Icons.stars_rounded,
                          title: '积分中心',
                          subtitle: '积分、金币与收支记录',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const CreditsPage()),
                          ),
                        ),
                        _MenuEntry(
                          icon: Icons.workspace_premium_outlined,
                          title: '用户组',
                          subtitle: _profile!.userGroup?.trim().isNotEmpty == true
                              ? '当前：${_profile!.userGroup}'
                              : '等级进度与权限详情',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const UserGroupPage(),
                            ),
                          ),
                        ),
                        _MenuEntry(
                          icon: Icons.rate_review_outlined,
                          title: '留言墙',
                          subtitle: '查看、发表和管理留言',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => WallPage(
                                uid: _profile!.uid,
                                username: _profile!.username,
                              ),
                            ),
                          ),
                        ),
                        _MenuEntry(
                          icon: Icons.storefront_outlined,
                          title: '积分商城',
                          subtitle: '使用论坛金币兑换商品',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const MallPage()),
                          ),
                        ),
                        _MenuEntry(
                          icon: Icons.tune_rounded,
                          title: '更多账号工具',
                          subtitle: '推广、短信、改名等低频功能',
                          onTap: _openAccountTools,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const _SectionTitle('设置与支持'),
                    const SizedBox(height: 9),
                    _MenuGroup(
                      children: [
                        _MenuEntry(
                          icon: Icons.settings_outlined,
                          title: '设置',
                          subtitle: '主题、文字大小、更新与账号',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const SettingsPage()),
                          ),
                        ),
                        _MenuEntry(
                          icon: Icons.info_outline_rounded,
                          title: '关于与反馈',
                          subtitle: '版本、作者信息与问题反馈',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const AboutPage()),
                          ),
                        ),
                      ],
                    ),
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _openMyContent(String type) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MyThreadsPage(initialType: type),
      ),
    );
  }

  void _openSignPage() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const _SignRankPage()),
    );
  }

  void _openAccountTools() {
    final uid = _profile?.uid ?? '';
    final oldAvatar = _profile?.avatarUrl;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AccountToolsPage(uid: uid)),
    ).then((_) async {
      if (oldAvatar != null && oldAvatar.isNotEmpty) {
        await CachedNetworkImage.evictFromCache(oldAvatar);
      }
      if (mounted) _loadProfile();
    });
  }
}

class _LoggedOutView extends StatelessWidget {
  final VoidCallback onLogin;

  const _LoggedOutView({required this.onLogin});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(
              Icons.person_outline_rounded,
              size: 38,
              color: colors.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            '登录 MT论坛',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            '登录后可使用消息、收藏、签到、好友与论坛账户功能。',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: onLogin,
            icon: const Icon(Icons.login_rounded),
            label: const Text('登录 / 设置'),
          ),
        ],
      ),
    );
  }
}

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

class _QuickActions extends StatelessWidget {
  final VoidCallback onMessages;
  final VoidCallback onFavorites;
  final VoidCallback onSign;
  final VoidCallback onSocial;

  const _QuickActions({
    required this.onMessages,
    required this.onFavorites,
    required this.onSign,
    required this.onSocial,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Expanded(
            child: _QuickAction(
              icon: Icons.chat_bubble_outline_rounded,
              label: '私信',
              color: colors.primary,
              onTap: onMessages,
            ),
          ),
          Expanded(
            child: _QuickAction(
              icon: Icons.bookmarks_outlined,
              label: '收藏',
              color: colors.secondary,
              onTap: onFavorites,
            ),
          ),
          Expanded(
            child: _QuickAction(
              icon: Icons.edit_calendar_outlined,
              label: '签到',
              color: colors.tertiary,
              onTap: onSign,
            ),
          ),
          Expanded(
            child: _QuickAction(
              icon: Icons.people_outline_rounded,
              label: '关系',
              color: colors.primary,
              onTap: onSocial,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
        child: Column(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 21, color: color),
            ),
            const SizedBox(height: 7),
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _MenuGroup extends StatelessWidget {
  final List<_MenuEntry> children;

  const _MenuGroup({required this.children});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1)
              const Divider(height: 1, indent: 58),
          ],
        ],
      ),
    );
  }
}

class _MenuEntry extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuEntry({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: colors.primaryContainer.withValues(alpha: 0.62),
          borderRadius: BorderRadius.circular(11),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 20, color: colors.onPrimaryContainer),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Icon(Icons.chevron_right_rounded, color: colors.outline),
    );
  }
}

// 签到页面
class _SignRankPage extends StatefulWidget {
  const _SignRankPage();

  @override
  State<_SignRankPage> createState() => _SignRankPageState();
}

class _SignRankPageState extends State<_SignRankPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  final _api = ApiService.instance;
  final _signs = SignService.instance;

  List<SignRecord> _records = [];
  bool _loading = false;
  bool _signing = false;
  bool _autoSign = false;
  bool _signedToday = false;

  final _tabs = const ['今日', '本月', '总排行'];
  final _types = const ['today', 'month', 'zong'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        _loadData();
      }
    });
    _loadState();
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadState() async {
    final autoSign = await _signs.getAutoSignEnabled();
    final signedToday = await _signs.syncTodayStatus();

    if (!mounted) {
      return;
    }

    setState(() {
      _autoSign = autoSign;
      _signedToday = signedToday;
    });
  }

  Future<void> _loadData() async {
    if (mounted) {
      setState(() => _loading = true);
    }

    try {
      final records = await _api.getSignRank(
        _types[_tabController.index],
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _records = records;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _signNow() async {
    if (_signing) {
      return;
    }

    setState(() => _signing = true);

    try {
      final result = await _signs.signNow();

      if (!mounted) {
        return;
      }

      if (result.success) {
        setState(() => _signedToday = true);
        await _loadData();
      }

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
    } finally {
      if (mounted) {
        setState(() => _signing = false);
      }
    }
  }

  Future<void> _setAutoSign(bool value) async {
    setState(() => _autoSign = value);
    await _signs.setAutoSignEnabled(value);

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          value
              ? '自动签到已开启：每天首次打开 App 自动签到'
              : '自动签到已关闭',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            title: const Text('签到'),
            pinned: true,
            bottom: TabBar(
              controller: _tabController,
              tabs: _tabs.map((tab) => Tab(text: tab)).toList(),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
              child: Material(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(18),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: _signedToday
                            ? colors.primaryContainer
                            : colors.surfaceContainerHighest,
                        child: Icon(
                          _signedToday
                              ? Icons.check_rounded
                              : Icons.calendar_today_rounded,
                          color: _signedToday
                              ? colors.onPrimaryContainer
                              : colors.onSurfaceVariant,
                        ),
                      ),
                      title: Text(
                        _signedToday ? '今日已签到' : '今日尚未签到',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        _signedToday
                            ? '今天无需重复操作'
                            : '点击右侧按钮立即签到',
                      ),
                      trailing: FilledButton(
                        onPressed: _signing || _signedToday ? null : _signNow,
                        child: _signing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(_signedToday ? '已签到' : '签到'),
                      ),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      secondary: const Icon(Icons.autorenew_rounded),
                      title: const Text('自动签到'),
                      subtitle: const Text(
                        '开启后每天第一次打开软件自动签到；失败会在下次启动重试',
                      ),
                      value: _autoSign,
                      onChanged: _setAutoSign,
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 6),
            sliver: SliverToBoxAdapter(
              child: Text(
                '${_tabs[_tabController.index]}签到排行',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          if (_loading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_records.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  '暂无签到记录',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.outline,
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final record = _records[index];
                    final topThree = index < 3;

                    final accent = switch (index) {
                      0 => const Color(0xFFE7A300),
                      1 => const Color(0xFF7D8897),
                      2 => const Color(0xFFA76438),
                      _ => colors.primary,
                    };

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: topThree
                            ? accent.withValues(alpha: 0.10)
                            : colors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(17),
                        border: Border.all(
                          color: topThree
                              ? accent.withValues(alpha: 0.32)
                              : colors.outlineVariant,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
                        child: Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: topThree
                                    ? accent
                                    : colors.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(13),
                              ),
                              alignment: Alignment.center,
                              child: topThree
                                  ? Icon(
                                      index == 0
                                          ? Icons.emoji_events_rounded
                                          : Icons.workspace_premium_rounded,
                                      color: Colors.white,
                                      size: 21,
                                    )
                                  : Text(
                                      '${index + 1}',
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          record.username,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.titleSmall
                                              ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      if (topThree) ...[
                                        const SizedBox(width: 6),
                                        Text(
                                          '#${index + 1}',
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                            color: accent,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    [
                                      if (record.signTime.isNotEmpty)
                                        record.signTime,
                                      if (record.totalDays.isNotEmpty)
                                        record.totalDays,
                                    ].join(' · '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colors.outline,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (record.reward.trim().isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Container(
                                constraints:
                                    const BoxConstraints(maxWidth: 120),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: colors.secondaryContainer,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  record.reward.replaceAll(
                                    RegExp(r'\s+'),
                                    ' ',
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colors.onSecondaryContainer,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                  childCount: _records.length,
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}
