import 'package:flutter/material.dart';

import '../models/models.dart';
import '../routes/thread_routes.dart';
import '../services/api_service.dart';
import '../widgets/app_state_view.dart';
import '../widgets/thread_card.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _api = ApiService.instance;
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  List<SearchResult> _results = [];
  bool _loading = false;
  bool _hasSearched = false;
  int _page = 1;
  String _keyword = '';

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onQueryChanged);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _search() async {
    final kw = _controller.text.trim();
    if (kw.isEmpty || _loading) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _hasSearched = true;
      _results = [];
      _page = 1;
      _keyword = kw;
    });
    try {
      final results = await _api.search(kw, page: 1);
      if (!mounted) return;
      setState(() => _results = results);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('搜索失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _keyword.isEmpty) return;
    setState(() => _loading = true);
    try {
      final next = _page + 1;
      final results = await _api.search(_keyword, page: next);
      if (!mounted) return;
      setState(() {
        _results.addAll(results);
        _page = next;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _clear() {
    _controller.clear();
    setState(() {
      _results = [];
      _hasSearched = false;
      _keyword = '';
      _page = 1;
    });
  }

  Thread _asThread(SearchResult result) {
    return Thread(
      tid: result.tid,
      title: result.title,
      authorUid: result.authorUid,
      authorName: result.authorName,
      avatarUrl: result.avatarUrl,
      forumName: result.forumName,
      replyCount: result.replyCount,
      viewCount: result.viewCount,
      likeCount: result.likeCount,
      lastReplyTime: result.postTime,
      excerpt: result.excerpt,
      thumbnails: result.thumbnails,
      hasHiddenContent: result.hasHiddenContent,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('搜索'),
      ),
      body: CustomScrollView(
        controller: _scrollController,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: SearchBar(
                controller: _controller,
                hintText: '搜索帖子',
                leading: const Icon(Icons.search_rounded),
                trailing: [
                  if (_controller.text.isNotEmpty)
                    IconButton(
                      tooltip: '清空',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: _clear,
                    ),
                ],
                onSubmitted: (_) => _search(),
                textInputAction: TextInputAction.search,
                padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 14),
                ),
              ),
            ),
          ),
          if (_hasSearched && _keyword.isNotEmpty && _results.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '“$_keyword”',
                        style: TextStyle(
                          color: colors.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      TextSpan(
                        text: ' 的搜索结果',
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelLarge,
                ),
              ),
            ),
          if (_loading && _results.isEmpty)
            const SliverFillRemaining(child: AppStateView.loading())
          else if (_hasSearched && _results.isEmpty && !_loading)
            const SliverFillRemaining(
              child: AppStateView.empty(
                icon: Icons.search_off_rounded,
                title: '未找到相关帖子',
                message: '换一个关键词再试试。',
              ),
            )
          else if (_results.isEmpty)
            const SliverFillRemaining(
              child: AppStateView.empty(
                icon: Icons.search_rounded,
                title: '搜索帖子',
                message: '输入关键词开始搜索。',
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
              sliver: SliverList.builder(
                itemCount: _results.length + 1,
                itemBuilder: (context, index) {
                  if (index == _results.length) {
                    if (_loading) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 2, bottom: 8),
                        child: FilledButton.tonal(
                          onPressed: _loadMore,
                          child: const Text('加载更多'),
                        ),
                      ),
                    );
                  }
                  final result = _results[index];
                  return ThreadCard(
                    thread: _asThread(result),
                    onTap: () => Navigator.push(
                      context,
                      buildThreadRoute(result.tid),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
