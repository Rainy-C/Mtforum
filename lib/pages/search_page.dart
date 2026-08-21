import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/api_service.dart';
import '../models/models.dart';
import 'thread_detail_page.dart';

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
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final kw = _controller.text.trim();
    if (kw.isEmpty) return;
    setState(() { _loading = true; _hasSearched = true; _results = []; _page = 1; _keyword = kw; });
    try {
      final results = await _api.search(kw, page: 1);
      setState(() { _results = results; _loading = false; });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('搜索失败: $e')),
        );
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final next = _page + 1;
      final results = await _api.search(_keyword, page: next);
      setState(() { _results.addAll(results); _page = next; _loading = false; });
    } catch (e) { setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverAppBar.large(
            title: const Text('搜索'), pinned: true,
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(64),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: SearchBar(
                  controller: _controller, hintText: '搜索帖子...',
                  leading: const Icon(Icons.search),
                  trailing: [
                    if (_controller.text.isNotEmpty)
                      IconButton(icon: const Icon(Icons.close), onPressed: () {
                        _controller.clear();
                        setState(() { _results = []; _hasSearched = false; });
                      }),
                  ],
                  onSubmitted: (_) => _search(),
                  elevation: const WidgetStatePropertyAll(0),
                ),
              ),
            ),
          ),
          if (_loading && _results.isEmpty)
            const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
          else if (_hasSearched && _results.isEmpty && !_loading)
            const SliverFillRemaining(child: Center(child: Text('未找到相关帖子')))
          else if (_results.isEmpty)
            SliverFillRemaining(child: Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [Icon(Icons.search, size: 64, color: Theme.of(context).colorScheme.outline),
                const SizedBox(height: 16), Text('输入关键词开始搜索', style: Theme.of(context).textTheme.bodyLarge)],
            )))
          else
            SliverPadding(
              padding: const EdgeInsets.all(10),
              sliver: SliverList(delegate: SliverChildBuilderDelegate(
                (context, index) {
                  if (index == _results.length) {
                    return _loading ? const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
                      : Padding(padding: const EdgeInsets.all(8), child: Center(child: FilledButton.tonal(onPressed: _loadMore, child: const Text('加载更多'))));
                  }
                  final r = _results[index];
                  return _SearchResultCard(result: r, onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => ThreadDetailPage(tid: r.tid))));
                },
                childCount: _results.length + 1,
              )),
            ),
        ],
      ),
    );
  }
}

class _SearchResultCard extends StatelessWidget {
  final SearchResult result;
  final VoidCallback onTap;
  const _SearchResultCard({required this.result, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap, borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // 标题
            Text(result.title ?? '无标题',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              maxLines: 2, overflow: TextOverflow.ellipsis),
            // 摘要
            if (result.excerpt != null && result.excerpt!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(result.excerpt!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
            const SizedBox(height: 8),
            // 作者 + 版块 + 时间
            Row(children: [
              if (result.authorName != null) ...[
                Icon(Icons.person_outline, size: 14, color: theme.colorScheme.outline),
                const SizedBox(width: 3),
                Flexible(child: Text(result.authorName!,
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline),
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
              ],
              if (result.forumName != null) ...[
                const SizedBox(width: 8),
                Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: theme.colorScheme.secondaryContainer, borderRadius: BorderRadius.circular(4)),
                  child: Text(result.forumName!,
                    style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSecondaryContainer))),
              ],
              const Spacer(),
              if (result.postTime != null) Text(result.postTime!,
                style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline)),
            ]),
          ]),
        ),
      ),
    );
  }
}
