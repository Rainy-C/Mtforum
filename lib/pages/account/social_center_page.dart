import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../widgets/app_state_view.dart';
import 'user_profile_page.dart';

class SocialCenterPage extends StatefulWidget {
  const SocialCenterPage({super.key});

  @override
  State<SocialCenterPage> createState() => _SocialCenterPageState();
}

class _SocialCenterPageState extends State<SocialCenterPage> {
  final _api = ApiService.instance;

  String? _uid;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadUid();
  }

  Future<void> _loadUid() async {
    try {
      final profile = await _api.getProfile();
      if (mounted) {
        setState(() => _uid = profile.uid);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = '用户信息加载失败：$e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_uid == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('关系中心')),
        body: Center(
          child: _error == null
              ? const CircularProgressIndicator()
              : Text(_error!),
        ),
      );
    }

    return DefaultTabController(
      length: 7,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('关系中心'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: '好友'),
              Tab(text: '关注'),
              Tab(text: '粉丝'),
              Tab(text: '来访'),
              Tab(text: '足迹'),
              Tab(text: '请求'),
              Tab(text: '黑名单'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _SocialList(type: 'friend', uid: _uid!),
            _SocialList(
              type: 'following',
              uid: _uid!,
              allowUnfollow: true,
            ),
            _SocialList(type: 'follower', uid: _uid!, canFollow: true),
            _SocialList(type: 'visitor', uid: _uid!, canFollow: true),
            _SocialList(type: 'trace', uid: _uid!, canFollow: true),
            const _FriendRequestList(),
            _SocialList(type: 'blacklist', uid: _uid!),
          ],
        ),
      ),
    );
  }
}

class SocialUsersPage extends StatelessWidget {
  final String type;
  final String uid;
  final String title;
  final bool canFollow;
  final bool allowUnfollow;

  const SocialUsersPage({
    super.key,
    required this.type,
    required this.uid,
    required this.title,
    this.canFollow = false,
    this.allowUnfollow = false,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: _SocialList(
        type: type,
        uid: uid,
        canFollow: canFollow,
        allowUnfollow: allowUnfollow,
      ),
    );
  }
}

class _SocialList extends StatefulWidget {
  final String type;
  final String uid;
  final bool canFollow;
  final bool allowUnfollow;

  const _SocialList({
    required this.type,
    required this.uid,
    this.canFollow = false,
    this.allowUnfollow = false,
  });

  @override
  State<_SocialList> createState() => _SocialListState();
}

class _SocialListState extends State<_SocialList> {
  final _api = ApiService.instance;
  final _scroll = ScrollController();

  final List<SocialUser> _items = [];
  final Set<String> _followingNow = {};
  final Set<String> _followedUids = {};

  int _page = 1;
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _reload();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients ||
        _loading ||
        _loadingMore ||
        !_hasMore) {
      return;
    }

    if (_scroll.position.pixels >=
        _scroll.position.maxScrollExtent - 240) {
      _loadMore();
    }
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _page = 1;
      _hasMore = true;
      _error = null;
      _items.clear();
    });

    try {
      final items = await _api.getSocialUsers(
        type: widget.type,
        uid: widget.uid,
        page: 1,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _items.addAll(items);
        _hasMore = items.isNotEmpty;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = '加载失败：$e');
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);

    try {
      final nextPage = _page + 1;
      final next = await _api.getSocialUsers(
        type: widget.type,
        uid: widget.uid,
        page: nextPage,
      );

      if (!mounted) {
        return;
      }

      final seen = _items.map((item) => item.uid).toSet();
      final additions =
          next.where((item) => !seen.contains(item.uid)).toList();

      setState(() {
        if (additions.isEmpty) {
          _hasMore = false;
        } else {
          _items.addAll(additions);
          _page = nextPage;
        }
      });
    } finally {
      if (mounted) {
        setState(() => _loadingMore = false);
      }
    }
  }

  Future<void> _follow(SocialUser user) async {
    if (_followingNow.contains(user.uid)) {
      return;
    }

    setState(() => _followingNow.add(user.uid));
    final result = await _api.followUser(user.uid);

    if (!mounted) {
      return;
    }

    setState(() {
      _followingNow.remove(user.uid);
      if (result.success) _followedUids.add(user.uid);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );
  }


  Future<void> _unblock(SocialUser user) async {
    if (_followingNow.contains(user.uid)) return;

    setState(() => _followingNow.add(user.uid));
    final result = await _api.unblockUser(uid: user.uid);

    if (!mounted) return;

    setState(() {
      _followingNow.remove(user.uid);
      if (result.success) {
        _items.removeWhere((item) => item.uid == user.uid);
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );
  }

  Future<void> _unfollow(SocialUser user) async {
    if (_followingNow.contains(user.uid)) {
      return;
    }

    setState(() => _followingNow.add(user.uid));
    final result = await _api.unfollowUser(
      user.uid,
      ownUid: widget.uid,
    );

    if (!mounted) return;

    setState(() => _followingNow.remove(user.uid));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );

    if (result.success) {
      await _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    if (_loading && _items.isEmpty) {
      return const AppStateView.loading();
    }

    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
        itemCount: _items.isEmpty ? 1 : _items.length + 1,
        itemBuilder: (context, index) {
          if (_items.isEmpty) {
            return SizedBox(
              height: 360,
              child: _error != null
                  ? AppStateView.error(
                      message: _error!,
                      onRetry: _reload,
                    )
                  : const AppStateView.empty(
                      icon: Icons.people_outline_rounded,
                      title: '暂无数据',
                      message: '这个列表目前没有内容。',
                    ),
            );
          }

          if (index == _items.length) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: _loadingMore
                    ? const CircularProgressIndicator()
                    : Text(
                        _hasMore ? '继续下滑加载' : '没有更多了',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.outline,
                        ),
                      ),
              ),
            );
          }

          final user = _items[index];
          final busy = _followingNow.contains(user.uid);
          final followed = _followedUids.contains(user.uid);

          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: CircleAvatar(
                backgroundImage: user.avatarUrl == null
                    ? null
                    : CachedNetworkImageProvider(user.avatarUrl!),
                child: user.avatarUrl == null
                    ? Text(
                        user.username.isEmpty
                            ? '?'
                            : user.username.substring(0, 1),
                      )
                    : null,
              ),
              title: Text(
                user.username,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text('UID ${user.uid}'),
              trailing: widget.type == 'blacklist'
                  ? FilledButton.tonal(
                      onPressed: busy ? null : () => _unblock(user),
                      child: busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('取消拉黑'),
                    )
                  : widget.type == 'following' && widget.allowUnfollow
                      ? FilledButton.tonal(
                          onPressed: busy ? null : () => _unfollow(user),
                          child: busy
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('取消关注'),
                        )
                      : widget.canFollow
                          ? FilledButton.tonal(
                              onPressed: busy || followed
                                  ? null
                                  : () => _follow(user),
                              child: busy
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(followed ? '已关注' : '关注'),
                            )
                          : const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => UserProfilePage(uid: user.uid),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class FriendRequestsPage extends StatelessWidget {
  const FriendRequestsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('好友申请')),
      body: const _FriendRequestList(),
    );
  }
}

class _FriendRequestList extends StatefulWidget {
  const _FriendRequestList();

  @override
  State<_FriendRequestList> createState() => _FriendRequestListState();
}

class _FriendRequestListState extends State<_FriendRequestList> {
  final _api = ApiService.instance;

  List<FriendRequestItem> _items = const [];
  bool _loading = true;
  final Set<String> _operating = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    try {
      final items = await _api.getFriendRequests();
      if (mounted) {
        setState(() => _items = items);
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _operate(
    FriendRequestItem item,
    String? url,
  ) async {
    if (_operating.contains(item.uid)) {
      return;
    }

    setState(() => _operating.add(item.uid));
    final result = await _api.respondFriendRequest(url);

    if (!mounted) {
      return;
    }

    setState(() => _operating.remove(item.uid));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );

    if (result.success) {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    if (_loading) {
      return const AppStateView.loading();
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
        children: [
          if (_items.isEmpty)
            const SizedBox(
              height: 360,
              child: AppStateView.empty(
                icon: Icons.group_add_outlined,
                title: '暂无好友申请',
                message: '目前没有新的好友请求。',
              ),
            )
          else
            for (final item in _items)
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundImage: item.avatarUrl == null
                        ? null
                        : CachedNetworkImageProvider(item.avatarUrl!),
                    child: item.avatarUrl == null
                        ? const Icon(Icons.person_outline_rounded)
                        : null,
                  ),
                  title: Text(item.username),
                  subtitle: Text('UID ${item.uid}'),
                  trailing: _operating.contains(item.uid)
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : Wrap(
                          spacing: 4,
                          children: [
                            TextButton(
                              onPressed: item.ignoreUrl == null
                                  ? null
                                  : () => _operate(item, item.ignoreUrl),
                              child: const Text('忽略'),
                            ),
                            FilledButton(
                              onPressed: item.acceptUrl == null
                                  ? null
                                  : () => _operate(item, item.acceptUrl),
                              child: const Text('通过'),
                            ),
                          ],
                        ),
                ),
              ),
        ],
      ),
    );
  }
}
