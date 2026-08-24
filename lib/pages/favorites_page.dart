import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/app_state_view.dart';
import '../widgets/thread_card.dart';
import '../routes/thread_routes.dart';

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage>
    with SingleTickerProviderStateMixin {
  final _api = ApiService.instance;
  final _scrollController = ScrollController();

  late final TabController _tabController;

  final _types = const ['all', 'thread', 'forum', 'group'];
  final _labels = const ['全部', '帖子', '版块', '群组'];

  List<FavoriteItem> _items = [];
  int _page = 1;
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _types.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        _reload();
      }
    });
    _scrollController.addListener(_onScroll);
    _reload();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_loading ||
        _loadingMore ||
        !_hasMore ||
        !_scrollController.hasClients) {
      return;
    }

    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 220) {
      _loadMore();
    }
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _loadingMore = false;
      _page = 1;
      _hasMore = true;
      _error = null;
      _items = [];
    });

    try {
      final items = await _api.getMyFavorites(
        type: _types[_tabController.index],
        page: 1,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _items = items;
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
    if (_loadingMore || !_hasMore) {
      return;
    }

    setState(() => _loadingMore = true);

    try {
      final nextPage = _page + 1;
      final next = await _api.getMyFavorites(
        type: _types[_tabController.index],
        page: nextPage,
      );

      if (!mounted) {
        return;
      }

      final known = _items
          .map((e) => '${e.favid}:${e.href}')
          .toSet();
      final additions = next
          .where((e) => !known.contains('${e.favid}:${e.href}'))
          .toList();

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

  void _open(FavoriteItem item) {
    if (item.isThread) {
      Navigator.push(
        context,
        buildThreadRoute(item.tid!),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${item.type.isEmpty ? '该收藏' : item.type}暂未接入原生详情页',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverAppBar(
            title: const Text('我的收藏'),
            pinned: true,
            bottom: TabBar(
              controller: _tabController,
              isScrollable: false,
              tabs: _labels.map((label) => Tab(text: label)).toList(),
            ),
          ),
          if (_loading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: AppStateView.loading(),
            )
          else if (_error != null)
            SliverFillRemaining(
              hasScrollBody: false,
              child: AppStateView.error(
                message: _error!,
                onRetry: _reload,
              ),
            )
          else if (_items.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: const AppStateView.empty(
                icon: Icons.bookmark_border_rounded,
                title: '暂无收藏',
                message: '收藏的帖子会出现在这里。',
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index == _items.length) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Center(
                          child: _loadingMore
                              ? const CircularProgressIndicator()
                              : Text(
                                  _hasMore ? '继续下滑加载' : '没有更多了',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.outline,
                                  ),
                                ),
                        ),
                      );
                    }

                    final item = _items[index];

                    if (item.isThread) {
                      final parsedThread = item.thread ??
                          Thread(
                            tid: item.tid!,
                            title: item.title,
                          );
                      final thread =
                          parsedThread.authorName?.trim().isNotEmpty == true
                              ? parsedThread
                              : parsedThread.copyWith(
                                  authorName: '作者信息暂缺',
                                );
                      return ThreadCard(
                        thread: thread,
                        onTap: () => _open(item),
                      );
                    }

                    return Card(
                      margin: const EdgeInsets.only(bottom: 7),
                      child: ListTile(
                        leading: Icon(_iconForType(item.type)),
                        title: Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: item.favid.isEmpty
                            ? null
                            : Text('收藏 ID ${item.favid}'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => _open(item),
                      ),
                    );
                  },
                  childCount: _items.length + 1,
                ),
              ),
            ),
        ],
      ),
    );
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'thread':
        return Icons.article_outlined;
      case 'forum':
        return Icons.forum_outlined;
      case 'group':
        return Icons.groups_outlined;
      default:
        return Icons.bookmark_outline_rounded;
    }
  }
}

class _FavoriteError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _FavoriteError({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: onRetry,
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }
}
