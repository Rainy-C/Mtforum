import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../data/portal_parser.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import 'thread_detail_page.dart';
import 'thread_editor_page.dart';

class CommunityPage extends StatefulWidget {
  const CommunityPage({super.key});

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage> {
  final _api = ApiService.instance;

  List<ForumGroup> _groups = PortalParser.defaultForumGroups();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading) {
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final groups = await _api.getForumGroups();
      if (!mounted) {
        return;
      }
      setState(() => _groups = groups);
    } catch (e) {
      if (mounted) {
        setState(() => _error = '社区加载失败：$e');
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar.large(
              title: const Text('社区'),
              pinned: true,
              actions: [
                IconButton(
                  tooltip: '刷新',
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            if (_loading && _groups.isEmpty)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null && _groups.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.forum_outlined,
                          size: 48,
                          color: colors.outline,
                        ),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 14),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                sliver: SliverList.builder(
                  itemCount: _groups.length,
                  itemBuilder: (context, index) {
                    final group = _groups[index];

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
                            child: Row(
                              children: [
                                Container(
                                  width: 4,
                                  height: 18,
                                  decoration: BoxDecoration(
                                    color: colors.primary,
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  group.name,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${group.boards.length}',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: colors.outline,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final columns =
                                  constraints.maxWidth >= 700 ? 3 : 2;
                              final ratio =
                                  constraints.maxWidth >= 700 ? 2.3 : 1.75;

                              return GridView.builder(
                                padding: EdgeInsets.zero,
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  mainAxisSpacing: 8,
                                  crossAxisSpacing: 8,
                                  childAspectRatio: ratio,
                                ),
                                itemCount: group.boards.length,
                                itemBuilder: (context, boardIndex) {
                                  final board = group.boards[boardIndex];
                                  return _BoardCard(
                                    board: board,
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ForumThreadsPage(
                                          board: board,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BoardCard extends StatelessWidget {
  final ForumBoard board;
  final VoidCallback onTap;

  const _BoardCard({
    required this.board,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Material(
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(11),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: board.iconUrl == null
                    ? Icon(
                        Icons.forum_outlined,
                        color: colors.primary,
                      )
                    : CachedNetworkImage(
                        imageUrl: board.iconUrl!,
                        fit: BoxFit.contain,
                        errorWidget: (_, __, ___) => Icon(
                          Icons.forum_outlined,
                          color: colors.primary,
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  board.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 19,
                color: colors.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ForumThreadsPage extends StatefulWidget {
  final ForumBoard board;

  const ForumThreadsPage({
    super.key,
    required this.board,
  });

  @override
  State<ForumThreadsPage> createState() => _ForumThreadsPageState();
}

class _ForumThreadsPageState extends State<ForumThreadsPage> {
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
    _loadFirst();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_loadingMore || !_hasMore || !_scrollController.hasClients) {
      return;
    }

    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 260) {
      _loadMore();
    }
  }

  Future<void> _loadFirst() async {
    if (_loading) {
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final items = await _api.getForumThreads(
        fid: widget.board.fid,
        page: 1,
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _threads
          ..clear()
          ..addAll(items);
        _page = 1;
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

  Future<void> _createThread() async {
    if (!_api.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先登录后再发帖')),
      );
      return;
    }

    final result = await Navigator.push<ThreadSubmitResult>(
      context,
      MaterialPageRoute(
        builder: (_) => ThreadEditorPage.newThread(
          fid: widget.board.fid,
          forumName: widget.board.name,
        ),
      ),
    );

    if (!mounted || result == null || !result.success) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );
    await _loadFirst();
    if (!mounted) return;

    final tid = result.tid;
    if (tid != null && tid.isNotEmpty) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ThreadDetailPage(tid: tid)),
      );
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) {
      return;
    }

    setState(() => _loadingMore = true);

    try {
      final next = _page + 1;
      final items = await _api.getForumThreads(
        fid: widget.board.fid,
        page: next,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        if (items.isEmpty) {
          _hasMore = false;
          return;
        }

        final existing = _threads.map((item) => item.tid).toSet();
        _threads.addAll(
          items.where((item) => !existing.contains(item.tid)),
        );
        _page = next;
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
    final colors = theme.colorScheme;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _loadFirst,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              title: Text(widget.board.name),
              pinned: true,
              actions: [
                IconButton(
                  tooltip: '发布新帖',
                  onPressed: _createThread,
                  icon: const Icon(Icons.add_comment_outlined),
                ),
              ],
            ),
            if (_loading && _threads.isEmpty)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null && _threads.isEmpty)
              SliverFillRemaining(
                child: Center(child: Text(_error!)),
              )
            else if (_threads.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Text(
                    '暂无帖子',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.outline,
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 18),
                sliver: SliverList.builder(
                  itemCount: _threads.length + 1,
                  itemBuilder: (context, index) {
                    if (index == _threads.length) {
                      return _loadingMore
                          ? const Padding(
                              padding: EdgeInsets.all(18),
                              child: Center(
                                child: CircularProgressIndicator(),
                              ),
                            )
                          : const SizedBox(height: 8);
                    }

                    final thread = _threads[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        contentPadding: const EdgeInsets.fromLTRB(
                          12,
                          7,
                          8,
                          7,
                        ),
                        title: Text(
                          thread.title ?? '未知标题',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Text(
                            [
                              if (thread.authorName?.isNotEmpty == true)
                                thread.authorName!,
                              if (thread.lastReplyTime?.isNotEmpty == true)
                                thread.lastReplyTime!,
                              if (thread.replyCount?.isNotEmpty == true)
                                '${thread.replyCount} 回复',
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ThreadDetailPage(
                              tid: thread.tid,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
