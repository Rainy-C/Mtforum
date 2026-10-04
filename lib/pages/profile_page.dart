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

part '../features/profile/widgets/profile_hero.dart';
part '../features/profile/widgets/profile_quick_actions.dart';
part '../features/profile/widgets/sign_rank_page.dart';

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
