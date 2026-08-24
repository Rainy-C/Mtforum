import 'package:flutter/material.dart';

import '../models/models.dart';
import '../routes/thread_routes.dart';
import '../services/api_service.dart';
import '../widgets/app_state_view.dart';
import '../widgets/thread_card.dart';

enum _SearchSort { latest, hot }

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
  _SearchSort _sort = _SearchSort.latest;

  List<SearchResult> get _visibleResults {
    final results = List<SearchResult>.from(_results);
    final referenceTime = DateTime.now();
    switch (_sort) {
      case _SearchSort.latest:
        results.sort(
          (a, b) => _searchTimeValue(b.postTime, referenceTime)
              .compareTo(_searchTimeValue(a.postTime, referenceTime)),
        );
        return results;
      case _SearchSort.hot:
        results.sort(
          (a, b) => _searchHotScore(b).compareTo(_searchHotScore(a)),
        );
        return results;
    }
  }

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
    final visibleResults = _visibleResults;

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
                child: Row(
                  children: [
                    Expanded(
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
                              style: TextStyle(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        style: theme.textTheme.labelLarge,
                      ),
                    ),
                    const SizedBox(width: 10),
                    SegmentedButton<_SearchSort>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: _SearchSort.latest,
                          label: Text('最新'),
                        ),
                        ButtonSegment(
                          value: _SearchSort.hot,
                          label: Text('最热'),
                        ),
                      ],
                      selected: {_sort},
                      onSelectionChanged: (selection) {
                        setState(() => _sort = selection.first);
                      },
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
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
                itemCount: visibleResults.length + 1,
                itemBuilder: (context, index) {
                  if (index == visibleResults.length) {
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
                  final result = visibleResults[index];
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

int _searchHotScore(SearchResult result) {
  final views = _searchCountValue(result.viewCount);
  final replies = _searchCountValue(result.replyCount);
  final likes = _searchCountValue(result.likeCount);
  // 回复和点赞比单纯浏览更能代表互动热度。
  return views + replies * 8 + likes * 5;
}

int _searchCountValue(String? raw) {
  final text = (raw ?? '').trim().toLowerCase().replaceAll(',', '');
  if (text.isEmpty) return 0;
  final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(text);
  final value = double.tryParse(match?.group(1) ?? '') ?? 0;
  final multiplier = text.contains('万') || text.contains('w')
      ? 10000
      : text.contains('千') || text.contains('k')
          ? 1000
          : 1;
  return (value * multiplier).round();
}

int _searchTimeValue(String? raw, DateTime referenceTime) {
  final text = (raw ?? '').trim();
  if (text.isEmpty) return 0;
  final now = referenceTime;

  if (text.contains('刚刚')) return now.millisecondsSinceEpoch;
  final relative = RegExp(r'(\d+)\s*(分钟|小时|天|周|个月|月|年)前')
      .firstMatch(text);
  if (relative != null) {
    final amount = int.tryParse(relative.group(1) ?? '') ?? 0;
    final unit = relative.group(2);
    final duration = switch (unit) {
      '分钟' => Duration(minutes: amount),
      '小时' => Duration(hours: amount),
      '天' => Duration(days: amount),
      '周' => Duration(days: amount * 7),
      '个月' || '月' => Duration(days: amount * 30),
      '年' => Duration(days: amount * 365),
      _ => Duration.zero,
    };
    return now.subtract(duration).millisecondsSinceEpoch;
  }

  final normalized = text
      .replaceAll('年', '-')
      .replaceAll('月', '-')
      .replaceAll('日', ' ')
      .replaceAll('/', '-');
  final fullDate = RegExp(
    r'(\d{4})-(\d{1,2})-(\d{1,2})(?:\s+(\d{1,2}):(\d{1,2}))?',
  ).firstMatch(normalized);
  if (fullDate != null) {
    return DateTime(
      int.parse(fullDate.group(1)!),
      int.parse(fullDate.group(2)!),
      int.parse(fullDate.group(3)!),
      int.tryParse(fullDate.group(4) ?? '') ?? 0,
      int.tryParse(fullDate.group(5) ?? '') ?? 0,
    ).millisecondsSinceEpoch;
  }

  final shortDate = RegExp(
    r'(\d{1,2})-(\d{1,2})(?:\s+(\d{1,2}):(\d{1,2}))?',
  ).firstMatch(normalized);
  if (shortDate != null) {
    return DateTime(
      now.year,
      int.parse(shortDate.group(1)!),
      int.parse(shortDate.group(2)!),
      int.tryParse(shortDate.group(3) ?? '') ?? 0,
      int.tryParse(shortDate.group(4) ?? '') ?? 0,
    ).millisecondsSinceEpoch;
  }
  return 0;
}
