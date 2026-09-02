import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../services/analytics_service.dart';
import '../services/api_service.dart';
import '../widgets/app_state_view.dart';
import '../widgets/thread_card.dart';
import '../routes/thread_routes.dart';
import 'ranklist_page.dart';
import 'search_page.dart';

class HomePageController {
  VoidCallback? _scrollToTopCallback;

  void scrollToTop() => _scrollToTopCallback?.call();
}

enum _HomeFeedSort {
  hot('hot', '最新热门', Icons.local_fire_department_outlined),
  latestPublish('newthread', '最新发表', Icons.article_outlined),
  digest('digest', '最新精华', Icons.auto_awesome_outlined),
  sofa('sofa', '抢沙发', Icons.weekend_outlined);

  const _HomeFeedSort(this.view, this.label, this.icon);

  final String view;
  final String label;
  final IconData icon;

  static _HomeFeedSort fromView(String? view) {
    return _HomeFeedSort.values.firstWhere(
      (item) => item.view == view,
      orElse: () => _HomeFeedSort.hot,
    );
  }
}

class HomePage extends StatefulWidget {
  final HomePageController? controller;

  const HomePage({super.key, this.controller});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _sortPreferenceKey = 'home_feed_sort';
  final _api = ApiService.instance;
  final _scrollController = ScrollController();

  final List<Thread> _threads = [];
  int _page = 1;
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  _HomeFeedSort _sort = _HomeFeedSort.hot;
  Timer? _onlineStatsTimer;
  int? _forumOnlineUsers;
  bool _onlineStatsLoading = false;

  @override
  void initState() {
    super.initState();
    widget.controller?._scrollToTopCallback = _scrollToTop;
    _scrollController.addListener(_onScroll);
    unawaited(_refreshForumOnlineUsers());
    _onlineStatsTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(_refreshForumOnlineUsers()),
    );
    _initializeFeed();
  }

  @override
  void dispose() {
    widget.controller?._scrollToTopCallback = null;
    _onlineStatsTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _refreshForumOnlineUsers() async {
    if (_onlineStatsLoading) return;
    _onlineStatsLoading = true;
    try {
      var onlineUsers = await _api.getForumOnlineCount();
      if (onlineUsers == null) {
        // 论坛页面抓取失败时，回退到自建统计服务的在线人数。
        try {
          onlineUsers = (await AnalyticsService.instance.fetchStats())?.onlineUsers;
        } catch (_) {
          // 保持 null，展示层继续显示上一次结果。
        }
      }
      if (!mounted || onlineUsers == null) return;
      if (_forumOnlineUsers != onlineUsers) {
        setState(() => _forumOnlineUsers = onlineUsers);
      }
    } catch (_) {
      // 论坛在线人数仅用于轻量展示，失败时保留上一次结果。
    } finally {
      _onlineStatsLoading = false;
    }
  }

  Widget _buildOnlineBadge(BuildContext context) {
    final onlineUsers = _forumOnlineUsers;
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: colors.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            onlineUsers == null ? '-- 在线' : '$onlineUsers 在线',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }

  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
    FocusManager.instance.primaryFocus?.unfocus();
    _scrollController.animateTo(
      _scrollController.position.minScrollExtent,
      duration: const Duration(milliseconds: 460),
      curve: Curves.easeOutCubic,
    );
  }

  void _onScroll() {
    if (_loadingMore || !_hasMore || !_scrollController.hasClients) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 260) {
      _loadMore();
    }
  }

  Future<void> _initializeFeed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _sort = _HomeFeedSort.fromView(prefs.getString(_sortPreferenceKey));
    } catch (_) {
      _sort = _HomeFeedSort.hot;
    }
    if (!mounted) return;
    await _loadFirstPage();
  }

  Future<void> _changeSort(_HomeFeedSort sort) async {
    if (_sort == sort || _loading) return;

    setState(() {
      _sort = sort;
      _threads.clear();
      _page = 1;
      _hasMore = true;
      _error = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_sortPreferenceKey, sort.view);
    } catch (_) {
      // 排序偏好保存失败不影响本次切换。
    }

    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    await _loadFirstPage();
  }

  Future<void> _loadFirstPage() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _api.getThreadList(page: 1, view: _sort.view);
      if (!mounted) return;
      setState(() {
        _threads
          ..clear()
          ..addAll(items);
        _page = 1;
        _hasMore = items.isNotEmpty;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '加载失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final nextPage = _page + 1;
      final items = await _api.getThreadList(
        page: nextPage,
        view: _sort.view,
      );
      if (!mounted) return;
      setState(() {
        if (items.isEmpty) {
          _hasMore = false;
        } else {
          final seen = _threads.map((e) => e.tid).toSet();
          _threads.addAll(items.where((e) => !seen.contains(e.tid)));
          _page = nextPage;
        }
      });
    } catch (_) {
      // 保留当前列表。
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _loadFirstPage,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('MT论坛'),
                  _buildOnlineBadge(context),
                ],
              ),
              pinned: true,
              centerTitle: false,
              actions: [
                IconButton(
                  tooltip: '搜索',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SearchPage(),
                    ),
                  ),
                  icon: const Icon(Icons.search_rounded),
                ),
                PopupMenuButton<_HomeFeedSort>(
                  tooltip: '帖子排序',
                  initialValue: _sort,
                  onSelected: _changeSort,
                  icon: const Icon(Icons.swap_vert_rounded),
                  itemBuilder: (context) => _HomeFeedSort.values
                      .map(
                        (item) => PopupMenuItem<_HomeFeedSort>(
                          value: item,
                          child: Row(
                            children: [
                              Icon(
                                item.icon,
                                size: 20,
                                color: item == _sort
                                    ? Theme.of(context).colorScheme.primary
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  item.label,
                                  style: TextStyle(
                                    fontWeight: item == _sort
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                              ),
                              if (item == _sort)
                                Icon(
                                  Icons.check_rounded,
                                  size: 20,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
                IconButton(
                  tooltip: '排行榜',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const RanklistPage(),
                    ),
                  ),
                  icon: const Icon(Icons.emoji_events_outlined),
                ),
              ],
            ),
            if (_loading && _threads.isEmpty)
              const SliverFillRemaining(
                child: AppStateView.loading(),
              )
            else if (_error != null && _threads.isEmpty)
              SliverFillRemaining(
                child: AppStateView.error(
                  message: _error!,
                  onRetry: _loadFirstPage,
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      if (index == _threads.length) {
                        if (_loadingMore) {
                          return const Padding(
                            padding: EdgeInsets.all(18),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        return const SizedBox(height: 12);
                      }
                      final thread = _threads[index];
                      return ThreadCard(
                        thread: thread,
                        onTap: () {
                          Navigator.push(context, buildThreadRoute(thread.tid));
                        },
                      );
                    },
                    childCount: _threads.length + 1,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
