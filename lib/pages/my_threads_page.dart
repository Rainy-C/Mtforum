import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/app_state_view.dart';
import '../widgets/thread_card.dart';
import '../routes/thread_routes.dart';

class MyThreadsPage extends StatefulWidget {
  final String? uid;
  final String? username;
  final String initialType;

  const MyThreadsPage({
    super.key,
    this.uid,
    this.username,
    this.initialType = 'thread',
  });

  @override
  State<MyThreadsPage> createState() => _MyThreadsPageState();
}

class _MyThreadsPageState extends State<MyThreadsPage>
    with SingleTickerProviderStateMixin {
  final _api = ApiService.instance;
  final _scrollController = ScrollController();

  late final TabController _tabController;

  late final List<String> _types;
  late final List<String> _labels;

  List<Thread> _items = [];
  int _page = 1;
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.uid == null) {
      _types = const ['thread', 'reply', 'postcomment'];
      _labels = const ['主题', '回复', '点评'];
    } else {
      _types = const ['thread', 'reply'];
      _labels = const ['主题', '回复'];
    }
    final initialIndex = _types.indexOf(widget.initialType);
    _tabController = TabController(
      length: _types.length,
      initialIndex: initialIndex < 0 ? 0 : initialIndex,
      vsync: this,
    );
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
      final type = _types[_tabController.index];
      final items = widget.uid == null
          ? await _api.getMyThreads(type: type, page: 1)
          : await _api.getUserThreads(
              uid: widget.uid!,
              type: type,
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
      final type = _types[_tabController.index];
      final next = widget.uid == null
          ? await _api.getMyThreads(type: type, page: nextPage)
          : await _api.getUserThreads(
              uid: widget.uid!,
              type: type,
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
            title: Text(
              widget.uid == null
                  ? '我的帖子'
                  : '${widget.username ?? '用户'}的内容',
            ),
            pinned: true,
            bottom: TabBar(
              controller: _tabController,
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
              child: AppStateView.empty(
                icon: Icons.article_outlined,
                title: '暂无${_labels[_tabController.index]}记录',
                message: '当前分类还没有内容。',
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 22),
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
                    return ThreadCard(
                      thread: item,
                      onTap: () {
                        Navigator.push(
                          context,
                          buildThreadRoute(item.tid),
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
