import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/app_state_view.dart';
import '../widgets/thread_card.dart';
import '../routes/thread_routes.dart';
import 'ranklist_page.dart';
import 'search_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _api = ApiService.instance;
  final _scrollController = ScrollController();

  final List<Thread> _threads = [];
  int _page = 1;
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadFirstPage();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_loadingMore || !_hasMore || !_scrollController.hasClients) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 260) {
      _loadMore();
    }
  }

  Future<void> _loadFirstPage() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _api.getThreadList(page: 1);
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
      final items = await _api.getThreadList(page: nextPage);
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
            SliverAppBar.large(
              title: const Text('MT论坛'),
              pinned: true,
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
                IconButton(
                  tooltip: '刷新',
                  onPressed: _loading ? null : _loadFirstPage,
                  icon: const Icon(Icons.refresh_rounded),
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
