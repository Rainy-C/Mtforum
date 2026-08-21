import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import 'thread_detail_page.dart';

class MyThreadsPage extends StatefulWidget {
  const MyThreadsPage({super.key});

  @override
  State<MyThreadsPage> createState() => _MyThreadsPageState();
}

class _MyThreadsPageState extends State<MyThreadsPage>
    with SingleTickerProviderStateMixin {
  final _api = ApiService.instance;
  final _scrollController = ScrollController();

  late final TabController _tabController;

  final _types = const ['thread', 'reply', 'postcomment'];
  final _labels = const ['主题', '回复', '点评'];

  List<Thread> _items = [];
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
        _scrollController.position.maxScrollExtent - 240) {
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
      final items = await _api.getMyThreads(
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
      if (!mounted) {
        return;
      }
      setState(() => _error = '加载失败：$e');
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
      final next = await _api.getMyThreads(
        type: _types[_tabController.index],
        page: nextPage,
      );

      if (!mounted) {
        return;
      }

      final known = _items.map((e) => e.tid).toSet();
      final additions = next.where((e) => !known.contains(e.tid)).toList();

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverAppBar(
            title: const Text('我的帖子'),
            pinned: true,
            bottom: TabBar(
              controller: _tabController,
              tabs: _labels.map((label) => Tab(text: label)).toList(),
            ),
          ),
          if (_loading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _ErrorState(
                message: _error!,
                onRetry: _reload,
              ),
            )
          else if (_items.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  '暂无${_labels[_tabController.index]}记录',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
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
                    return _ThreadCard(
                      item: item,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ThreadDetailPage(tid: item.tid),
                          ),
                        );
                      },
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
}

class _ThreadCard extends StatelessWidget {
  final Thread item;
  final VoidCallback onTap;

  const _ThreadCard({
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (item.thumbnails.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: CachedNetworkImage(
                    imageUrl: item.thumbnails.first,
                    width: 74,
                    height: 74,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) =>
                        const SizedBox(width: 74, height: 74),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title ?? '无标题',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (item.excerpt?.isNotEmpty ?? false) ...[
                      const SizedBox(height: 5),
                      Text(
                        item.excerpt!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.outline,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        if (item.likeCount != null)
                          _Meta(
                            icon: Icons.thumb_up_alt_outlined,
                            text: item.likeCount!,
                          ),
                        if (item.replyCount != null)
                          _Meta(
                            icon: Icons.chat_bubble_outline_rounded,
                            text: item.replyCount!,
                          ),
                        if (item.viewCount != null)
                          _Meta(
                            icon: Icons.visibility_outlined,
                            text: item.viewCount!,
                          ),
                        if (item.lastReplyTime != null)
                          _Meta(
                            icon: Icons.schedule_rounded,
                            text: item.lastReplyTime!,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Meta({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outline;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 3),
        Text(
          text,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
              ),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({
    required this.message,
    required this.onRetry,
  });

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
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}
