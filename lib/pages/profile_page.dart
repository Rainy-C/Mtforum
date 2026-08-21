import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/api_service.dart';
import '../services/sign_service.dart';
import '../models/models.dart';
import 'settings_page.dart';
import 'my_threads_page.dart';
import 'favorites_page.dart';
import 'mall_page.dart';
import 'account/profile_edit_page.dart';
import 'account/credits_page.dart';
import 'account/social_center_page.dart';
import 'account/account_tools_page.dart';
import 'account/private_messages_page.dart';

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
    } else if (!_api.isLoggedIn) {
      setState(() => _profile = null);
    }
  }

  Future<void> _loadProfile() async {
    setState(() => _loading = true);
    try {
      final p = await _api.getProfile();
      setState(() {
        _profile = p;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: const Text('我的'),
            pinned: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _api.isLoggedIn ? _loadProfile : null,
              ),
            ],
          ),
          if (!_api.isLoggedIn)
            SliverFillRemaining(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.lock_outline,
                          size: 64, color: theme.colorScheme.outline),
                      const SizedBox(height: 16),
                      const Text('登录后可使用签到、收藏、好友与金币兑换'),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const SettingsPage()),
                          ).then((_) {
                            // 从设置页返回后刷新
                            if (_api.isLoggedIn && _profile == null) {
                              _loadProfile();
                            }
                          });
                        },
                        icon: const Icon(Icons.settings),
                        label: const Text('登录 / 设置'),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (_loading && _profile == null)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_profile != null)
            SliverToBoxAdapter(
              child: Column(
                children: [
                  // 用户信息卡
                  Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          theme.colorScheme.primaryContainer,
                          theme.colorScheme.secondaryContainer,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 40,
                          backgroundColor: theme.colorScheme.primary,
                          backgroundImage: _profile!.avatarUrl != null
                              ? CachedNetworkImageProvider(
                                  _profile!.avatarUrl!)
                              : null,
                          child: _profile!.avatarUrl == null
                              ? Text(
                                  (_profile!.username ?? '?')[0],
                                  style: TextStyle(
                                      fontSize: 32,
                                      color: theme.colorScheme.onPrimary),
                                )
                              : null,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _profile!.username ?? '未知用户',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'UID: ${_profile!.uid}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 积分卡片
                  if (_profile!.credits != null || _profile!.gold != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          if (_profile!.credits != null)
                            Expanded(
                              child: _StatCard(
                                icon: Icons.star,
                                label: '积分',
                                value: _profile!.credits.toString(),
                              ),
                            ),
                          if (_profile!.credits != null &&
                              _profile!.gold != null)
                            const SizedBox(width: 12),
                          if (_profile!.gold != null)
                            Expanded(
                              child: _StatCard(
                                icon: Icons.monetization_on_outlined,
                                label: '金币',
                                value: _profile!.gold.toString(),
                              ),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                  // 功能列表
                  _buildMenuList(context),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMenuList(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    Widget quickAction({
      required IconData icon,
      required Color color,
      required String title,
      required VoidCallback onTap,
    }) {
      return Material(
        color: colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(17),
          side: BorderSide(color: colors.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 10, 11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 20, color: color),
                ),
                const Spacer(),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget rowItem({
      required IconData icon,
      required String title,
      required String subtitle,
      required VoidCallback onTap,
      Color? accent,
    }) {
      final color = accent ?? colors.primary;
      return ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: color, size: 21),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(subtitle),
        trailing: Icon(
          Icons.chevron_right_rounded,
          color: colors.outline,
        ),
        onTap: onTap,
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '我的内容',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.95,
            children: [
              quickAction(
                icon: Icons.article_outlined,
                color: colors.primary,
                title: '帖子',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const MyThreadsPage(),
                  ),
                ),
              ),
              quickAction(
                icon: Icons.bookmarks_outlined,
                color: colors.secondary,
                title: '收藏',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const FavoritesPage(),
                  ),
                ),
              ),
              quickAction(
                icon: Icons.people_outline_rounded,
                color: colors.tertiary,
                title: '关系',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SocialCenterPage(),
                  ),
                ),
              ),
              quickAction(
                icon: Icons.edit_calendar_outlined,
                color: colors.primary,
                title: '签到',
                onTap: _openSignPage,
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            '服务与设置',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Material(
            color: colors.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: colors.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                rowItem(
                  icon: Icons.chat_bubble_outline_rounded,
                  title: '私信',
                  subtitle: '查看会话和发送私信',
                  accent: colors.primary,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PrivateMessagesPage(),
                    ),
                  ),
                ),
                const Divider(height: 1, indent: 64),
                rowItem(
                  icon: Icons.manage_accounts_outlined,
                  title: '编辑资料',
                  subtitle: '基本资料与隐私设置',
                  accent: colors.primary,
                  onTap: () => Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ProfileEditPage(),
                    ),
                  ).then((changed) {
                    if (changed == true) {
                      _loadProfile();
                    }
                  }),
                ),
                const Divider(height: 1, indent: 64),
                rowItem(
                  icon: Icons.stars_rounded,
                  title: '积分中心',
                  subtitle: '积分、金币、好评、信誉与记录',
                  accent: colors.tertiary,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CreditsPage(),
                    ),
                  ),
                ),
                const Divider(height: 1, indent: 64),
                rowItem(
                  icon: Icons.admin_panel_settings_outlined,
                  title: '账号工具',
                  subtitle: '用户组、推广、短信、改名等',
                  accent: colors.secondary,
                  onTap: () {
                    final uid = _profile?.uid ?? '';
                    final oldAvatar = _profile?.avatarUrl;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AccountToolsPage(uid: uid),
                      ),
                    ).then((_) async {
                      if (oldAvatar != null && oldAvatar.isNotEmpty) {
                        await CachedNetworkImage.evictFromCache(oldAvatar);
                      }
                      if (mounted) _loadProfile();
                    });
                  },
                ),
                const Divider(height: 1, indent: 64),
                rowItem(
                  icon: Icons.storefront_outlined,
                  title: '积分商城',
                  subtitle: '使用论坛金币兑换商品',
                  accent: colors.tertiary,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const MallPage(),
                    ),
                  ),
                ),
                const Divider(height: 1, indent: 64),
                rowItem(
                  icon: Icons.settings_outlined,
                  title: '设置',
                  subtitle: '账号、主题、更新与应用设置',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SettingsPage(),
                    ),
                  ).then((_) {
                    if (_api.isLoggedIn && _profile == null) {
                      _loadProfile();
                    }
                  }),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openSignPage() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const _SignRankPage()),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(height: 8),
            Text(value,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            Text(label, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
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
