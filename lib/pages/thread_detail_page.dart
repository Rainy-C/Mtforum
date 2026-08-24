import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/smiley_catalog.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/comment_thread_service.dart';
import '../services/comment_filter_service.dart';
import '../widgets/app_state_view.dart';
import '../widgets/user_level_badge.dart';
import '../routes/forum_link_router.dart';
import 'account/user_profile_page.dart';
import 'thread_editor_page.dart';

Future<void> _openPostLink(BuildContext context, String rawUrl) async {
  final target = resolveForumLink(rawUrl);

  switch (target.kind) {
    case ForumLinkKind.thread:
      if (!context.mounted || target.id == null) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          settings: RouteSettings(name: '/thread/${target.id}'),
          builder: (_) => ThreadDetailPage(
            tid: target.id!,
            targetPid: target.pid,
            targetUrl: target.url,
          ),
        ),
      );
      return;

    case ForumLinkKind.user:
      if (!context.mounted || target.id == null) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          settings: RouteSettings(name: '/user/${target.id}'),
          builder: (_) => UserProfilePage(uid: target.id!),
        ),
      );
      return;

    case ForumLinkKind.external:
      final uri = Uri.tryParse(target.url);
      if (uri == null) return;
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
  }
}

class ThreadDetailPage extends StatefulWidget {
  final String tid;
  final String? targetPid;
  final String? targetUrl;

  const ThreadDetailPage({
    super.key,
    required this.tid,
    this.targetPid,
    this.targetUrl,
  });

  @override
  State<ThreadDetailPage> createState() => _ThreadDetailPageState();
}

class _ThreadDetailPageState extends State<ThreadDetailPage> {
  final _api = ApiService.instance;
  final _scrollController = ScrollController();

  ThreadDetail? _detail;
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  int _page = 1;
  bool _liked = false;
  bool _favorited = false;
  bool _targetCommentsOpened = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }


  Future<void> _loadData() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final targetPid = widget.targetPid?.trim() ?? '';
      final targetUrl = widget.targetUrl?.trim() ?? '';
      late final ThreadDetail detail;
      ThreadDetail? targetDetail;
      if (targetPid.isNotEmpty && targetUrl.isNotEmpty) {
        final results = await Future.wait<ThreadDetail>([
          _api.getThreadDetail(widget.tid, page: 1),
          _api.getThreadDetailAtPost(
            tid: widget.tid,
            pid: targetPid,
            targetUrl: targetUrl,
          ),
        ]);
        detail = results.first;
        targetDetail = results.last;
      } else {
        detail = await _api.getThreadDetail(widget.tid, page: 1);
      }
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _page = 1;
        _hasMore = detail.posts.isNotEmpty;
      });
      if (targetDetail != null && !_targetCommentsOpened) {
        _targetCommentsOpened = true;
        final locatedDetail = targetDetail;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _showComments(
            detailOverride: locatedDetail,
            targetPid: targetPid,
          );
        });
      }
    } catch (e) {
      if (mounted) {
        final message = e is StateError ? e.message : '加载失败：$e';
        setState(() => _error = message);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _detail == null) return;
    setState(() => _loadingMore = true);
    try {
      final nextPage = _page + 1;
      final next = await _api.getThreadDetail(widget.tid, page: nextPage);
      final existing = _detail!.posts.map((e) => e.pid).toSet();
      final additions = next.posts.where((e) => !existing.contains(e.pid)).toList();
      if (!mounted) return;
      setState(() {
        if (additions.isEmpty) {
          _hasMore = false;
        } else {
          _detail!.posts.addAll(additions);
          _page = nextPage;
        }
      });
    } catch (_) {
      // 下一页加载失败不破坏当前内容。
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _showComments({
    ThreadDetail? detailOverride,
    String? targetPid,
  }) async {
    final detail = detailOverride ?? _detail;
    if (detail == null || detail.posts.isEmpty) return;
    final locatingTarget = targetPid?.trim().isNotEmpty == true;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _CommentsSheet(
        detail: detail,
        initialTargetPid: targetPid,
        hasMore: () => locatingTarget ? false : _hasMore,
        isLoadingMore: () => _loadingMore,
        onLoadMore: locatingTarget ? () async {} : _loadMore,
        onRefresh: locatingTarget
            ? () => _refreshLocatedComments(detail)
            : _refreshCommentsInPlace,
        canEdit: _canEdit,
        onEdit: _editPost,
        onImageTap: (post, index) => _openImages(post.images, index),
      ),
    );
  }

  Future<void> _refreshLocatedComments(ThreadDetail detail) async {
    final pid = widget.targetPid?.trim() ?? '';
    final url = widget.targetUrl?.trim() ?? '';
    if (pid.isEmpty || url.isEmpty) return;
    final refreshed = await _api.getThreadDetailAtPost(
      tid: widget.tid,
      pid: pid,
      targetUrl: url,
    );
    final refreshedPosts = List<Post>.from(refreshed.posts);
    detail.posts
      ..clear()
      ..addAll(refreshedPosts);
  }

  Future<void> _refreshCommentsInPlace() async {
    final current = _detail;
    if (current == null) return;

    final refreshed = await _api.getThreadDetail(widget.tid, page: 1);
    if (!mounted) return;

    setState(() {
      current.posts
        ..clear()
        ..addAll(refreshed.posts);
      _page = 1;
      _hasMore = refreshed.posts.isNotEmpty;
    });
  }

  void _showReply({Post? post}) {
    final detail = _detail;
    if (detail == null) return;
    if (!_api.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先登录后再回复')),
      );
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ReplySheet(
        tid: detail.tid,
        fid: detail.fid,
        noticeauthor: detail.noticeauthor,
        repquotePid: post?.pid,
        replyToName: post?.authorName,
        onReplied: _loadData,
      ),
    );
  }

  bool _canEdit(Post post) {
    final detail = _detail;
    if (detail == null || !_api.isLoggedIn) return false;
    final uid = detail.currentUid.trim();
    return uid.isNotEmpty && uid != '0' && post.authorUid == uid;
  }

  Future<void> _editPost(Post post) async {
    final detail = _detail;
    if (detail == null || !_canEdit(post)) return;

    final result = await Navigator.push<ThreadSubmitResult>(
      context,
      MaterialPageRoute(
        builder: (_) => ThreadEditorPage.edit(
          fid: detail.fid,
          tid: detail.tid,
          pid: post.pid,
          page: post.page,
          editSubject: post.isOp,
        ),
      ),
    );

    if (!mounted || result == null || !result.success) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );
    await _loadData();
  }

  Future<void> _toggleLike() async {
    if (!_api.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先登录')),
      );
      return;
    }
    final next = !_liked;
    setState(() => _liked = next);
    final ok = await _api.recommend(widget.tid, cancel: !next);
    if (!ok && mounted) setState(() => _liked = !next);
  }

  Future<void> _toggleFavorite() async {
    if (!_api.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先登录')),
      );
      return;
    }
    final next = !_favorited;
    setState(() => _favorited = next);
    final ok = await _api.favorite(widget.tid, cancel: !next);
    if (!mounted) return;
    if (!ok) setState(() => _favorited = !next);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? (next ? '已收藏' : '已取消收藏') : '操作失败')),
    );
  }

  void _openImages(List<String> images, int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _FullScreenImageViewer(
          images: images,
          initialIndex: index,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    return Scaffold(
      body: CustomScrollView(
        controller: _scrollController,
        cacheExtent: 800,
        slivers: [
          SliverAppBar(
            pinned: true,
            title: Text(
              detail?.title ?? '帖子详情',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              if (detail != null)
                IconButton(
                  tooltip: _liked ? '取消点赞' : '点赞',
                  onPressed: _toggleLike,
                  icon: Icon(
                    _liked ? Icons.thumb_up_rounded : Icons.thumb_up_outlined,
                  ),
                ),
              if (detail != null)
                IconButton(
                  tooltip: _favorited ? '取消收藏' : '收藏',
                  onPressed: _toggleFavorite,
                  icon: Icon(
                    _favorited
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_border_rounded,
                  ),
                ),
              IconButton(
                tooltip: '刷新',
                onPressed: _loading ? null : _loadData,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          if (_loading && detail == null)
            const SliverFillRemaining(
              child: AppStateView.loading(),
            )
          else if (_error != null && detail == null)
            SliverFillRemaining(
              child: AppStateView.error(
                message: _error!,
                onRetry: _loadData,
              ),
            )
          else if (detail != null && detail.posts.isEmpty)
            SliverFillRemaining(
              child: AppStateView.error(
                message: '没有解析到楼层内容',
                onRetry: _loadData,
              ),
            )
          else if (detail != null)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Builder(
                    builder: (context) {
                      final op = _threadOp(detail);
                      return RepaintBoundary(
                        child: _PostCard(
                          post: op,
                          highlighted: false,
                          onReply: () => _showReply(post: op),
                          onEdit: _canEdit(op) ? () => _editPost(op) : null,
                          onImageTap: (imageIndex) =>
                              _openImages(op.images, imageIndex),
                        ),
                      );
                    },
                  ),
                ]),
              ),
            ),
        ],
      ),
      floatingActionButton: detail == null
          ? null
          : FloatingActionButton.extended(
              heroTag: 'thread-comments-${widget.tid}',
              onPressed: () => _showComments(),
              icon: const Icon(Icons.forum_rounded),
              label: const Text('评论区'),
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}

Post _threadOp(ThreadDetail detail) {
  for (final post in detail.posts) {
    if (post.isOp) return post;
  }
  return detail.posts.first;
}

Post? _findPost(List<Post> posts, String pid) {
  if (pid.isEmpty) return null;
  for (final post in posts) {
    if (post.pid == pid) return post;
  }
  return null;
}

List<Post> _threadComments(ThreadDetail detail) {
  if (detail.posts.isEmpty) return const <Post>[];
  final hasOp = detail.posts.any((post) => post.isOp);
  if (!hasOp) return List<Post>.from(detail.posts, growable: false);
  return detail.posts.where((post) => !post.isOp).toList(growable: false);
}

class _CommentsSheet extends StatefulWidget {
  final ThreadDetail detail;
  final String? initialTargetPid;
  final bool Function() hasMore;
  final bool Function() isLoadingMore;
  final Future<void> Function() onLoadMore;
  final Future<void> Function() onRefresh;
  final bool Function(Post post) canEdit;
  final ValueChanged<Post> onEdit;
  final void Function(Post post, int index) onImageTap;

  const _CommentsSheet({
    required this.detail,
    this.initialTargetPid,
    required this.hasMore,
    required this.isLoadingMore,
    required this.onLoadMore,
    required this.onRefresh,
    required this.canEdit,
    required this.onEdit,
    required this.onImageTap,
  });

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  static const _commentReverseOrderKey = 'thread_comment_reverse_order';

  final _scrollController = ScrollController();
  final _composerController = _SmileyEditingController();
  final _composerFocusNode = FocusNode();
  final _commentFilter = CommentFilterService.instance;
  final _commentThreadService = const CommentThreadService();
  final _targetCommentKey = GlobalKey();
  final Map<String, GlobalKey> _commentKeys = {};

  bool _loadingAll = false;
  bool _loadAllFailed = false;
  bool _sending = false;
  bool _showSmileys = false;
  bool _reverseOrder = false;
  late int _minLoadedPage;
  late int _maxLoadedPage;
  bool _hasPreviousTargetPage = false;
  bool _hasNextTargetPage = true;
  bool _loadingPreviousTargetPage = false;
  bool _loadingNextTargetPage = false;
  bool _previousTargetPageFailed = false;
  bool _nextTargetPageFailed = false;
  bool _targetWindowPrimed = false;
  String? _contextHighlightPid;
  Post? _replyTarget;

  bool get _targetMode =>
      widget.initialTargetPid?.trim().isNotEmpty == true;

  @override
  void initState() {
    super.initState();
    _commentFilter.addListener(_onFilterChanged);
    _commentFilter.load();
    _composerController.addListener(_onComposerChanged);
    _scrollController.addListener(_onTargetWindowScroll);
    _resetTargetWindowState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (_targetMode) {
        await _primeTargetWindow();
      } else {
        await _restoreCommentOrder();
        if (!mounted) return;
        await _loadAllComments();
      }
    });
  }

  @override
  void dispose() {
    _commentFilter.removeListener(_onFilterChanged);
    _composerController.removeListener(_onComposerChanged);
    _scrollController.dispose();
    _composerController.dispose();
    _composerFocusNode.dispose();
    super.dispose();
  }

  void _onFilterChanged() {
    if (mounted) setState(() {});
  }

  void _resetTargetWindowState() {
    final page = widget.detail.page < 1 ? 1 : widget.detail.page;
    _minLoadedPage = page;
    _maxLoadedPage = page;
    _hasPreviousTargetPage = page > 1;
    _hasNextTargetPage = true;
    _loadingPreviousTargetPage = false;
    _loadingNextTargetPage = false;
    _previousTargetPageFailed = false;
    _nextTargetPageFailed = false;
    _targetWindowPrimed = false;
  }

  ({String pid, double top})? _captureViewportAnchor() {
    if (!_scrollController.hasClients) return null;
    final viewportContext =
        _scrollController.position.context.notificationContext;
    final viewport = viewportContext?.findRenderObject();
    if (viewport is! RenderBox || !viewport.hasSize) return null;
    final viewportTop = viewport.localToGlobal(Offset.zero).dy;

    ({String pid, double top})? best;
    var bestDistance = double.infinity;
    for (final post in _comments) {
      final key = post.pid == widget.initialTargetPid
          ? _targetCommentKey
          : _commentKeys[post.pid];
      final renderObject = key?.currentContext?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) continue;
      final top = renderObject.localToGlobal(Offset.zero).dy - viewportTop;
      final bottom = top + renderObject.size.height;
      if (bottom <= 0 || top >= viewport.size.height) continue;
      final distance = top.abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        best = (pid: post.pid, top: top);
      }
    }
    return best;
  }

  Future<void> _restoreViewportAnchor(
    ({String pid, double top})? anchor,
  ) async {
    if (anchor == null) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_scrollController.hasClients) return;

    final viewportContext =
        _scrollController.position.context.notificationContext;
    final viewport = viewportContext?.findRenderObject();
    final key = anchor.pid == widget.initialTargetPid
        ? _targetCommentKey
        : _commentKeys[anchor.pid];
    final renderObject = key?.currentContext?.findRenderObject();
    if (viewport is! RenderBox ||
        renderObject is! RenderBox ||
        !viewport.hasSize ||
        !renderObject.hasSize) {
      return;
    }

    final viewportTop = viewport.localToGlobal(Offset.zero).dy;
    final currentTop = renderObject.localToGlobal(Offset.zero).dy - viewportTop;
    final delta = currentTop - anchor.top;
    if (delta.abs() < 0.5) return;
    _scrollController.jumpTo(
      (_scrollController.position.pixels + delta)
          .clamp(
            _scrollController.position.minScrollExtent,
            _scrollController.position.maxScrollExtent,
          )
          .toDouble(),
    );
  }

  void _onTargetWindowScroll() {
    if (!_targetMode || !_targetWindowPrimed ||
        !_scrollController.hasClients) {
      return;
    }

    final position = _scrollController.position;
    if (position.pixels <= 220 && _hasPreviousTargetPage) {
      _loadTargetPage(previous: true);
    }
    if (position.extentAfter <= 320 && _hasNextTargetPage) {
      _loadTargetPage(previous: false);
    }
  }

  Future<void> _primeTargetWindow() async {
    if (!_targetMode) return;

    // 目标页前后各预取一页，让目标楼层一开始就有上下文；后续滚动时再
    // 分别向前、向后增量加载，不再被 findpost 返回的单页限制住。
    if (_hasPreviousTargetPage) {
      await _loadTargetPage(previous: true, preservePosition: false);
    }
    if (!mounted) return;
    await _loadTargetPage(previous: false, preservePosition: false);
    if (!mounted) return;

    _targetWindowPrimed = true;
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) await _scrollToTargetComment();
  }

  Future<void> _loadTargetPage({
    required bool previous,
    bool preservePosition = true,
  }) async {
    if (!_targetMode) return;
    if (previous) {
      if (_loadingPreviousTargetPage || !_hasPreviousTargetPage) return;
    } else if (_loadingNextTargetPage || !_hasNextTargetPage) {
      return;
    }

    final page = previous ? _minLoadedPage - 1 : _maxLoadedPage + 1;
    if (page < 1) {
      if (mounted) setState(() => _hasPreviousTargetPage = false);
      return;
    }

    final anchor = preservePosition ? _captureViewportAnchor() : null;
    var contentChanged = false;

    setState(() {
      if (previous) {
        _loadingPreviousTargetPage = true;
        _previousTargetPageFailed = false;
      } else {
        _loadingNextTargetPage = true;
        _nextTargetPageFailed = false;
      }
    });

    try {
      final next = await ApiService.instance.getThreadDetail(
        widget.detail.tid,
        page: page,
      );
      if (!mounted) return;

      final existing = widget.detail.posts.map((post) => post.pid).toSet();
      final additions = next.posts
          .where((post) => existing.add(post.pid))
          .toList(growable: false);
      contentChanged = additions.isNotEmpty;

      setState(() {
        if (additions.isEmpty) {
          if (previous) {
            _hasPreviousTargetPage = false;
          } else {
            _hasNextTargetPage = false;
          }
          return;
        }

        if (previous) {
          widget.detail.posts.insertAll(0, additions);
          _minLoadedPage = page;
          _hasPreviousTargetPage = page > 1;
        } else {
          widget.detail.posts.addAll(additions);
          _maxLoadedPage = page;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (previous) {
          _previousTargetPageFailed = true;
        } else {
          _nextTargetPageFailed = true;
        }
      });
    } finally {
      if (mounted) {
        setState(() {
          if (previous) {
            _loadingPreviousTargetPage = false;
          } else {
            _loadingNextTargetPage = false;
          }
        });
      }
    }
    if (contentChanged) await _restoreViewportAnchor(anchor);
  }

  Future<void> _refreshLoadedTargetWindow() async {
    final anchor = _captureViewportAnchor();
    final refreshedPosts = <Post>[];
    final seen = <String>{};

    // 只刷新用户当前已经浏览到的页窗，不重新退回通知最初定位页。
    // 分批请求避免一次性并发过多，同时保留第 100 楼一类阅读进度。
    final pages = <int>[
      for (var page = _minLoadedPage; page <= _maxLoadedPage; page++) page,
    ];
    for (var start = 0; start < pages.length; start += 3) {
      final end = (start + 3).clamp(0, pages.length).toInt();
      final details = await Future.wait(
        pages.sublist(start, end).map(
              (page) => ApiService.instance.getThreadDetail(
                widget.detail.tid,
                page: page,
              ),
            ),
      );
      for (final detail in details) {
        for (final post in detail.posts) {
          if (seen.add(post.pid)) refreshedPosts.add(post);
        }
      }
    }
    if (!mounted || refreshedPosts.isEmpty) return;

    setState(() {
      widget.detail.posts
        ..clear()
        ..addAll(refreshedPosts);
      _targetWindowPrimed = true;
    });
    await _restoreViewportAnchor(anchor);
  }

  List<Post> get _filteredComments {
    var comments = _threadComments(widget.detail);
    if (_commentFilter.commentsEnabled && _commentFilter.hasKeywords) {
      comments = comments
          .where(
            (post) =>
                post.pid == widget.initialTargetPid ||
                !_commentFilter.matches(post.content),
          )
          .toList(growable: false);
    }
    return comments;
  }

  List<Post> get _comments {
    final comments = List<Post>.from(_filteredComments);
    if (_targetMode || !_reverseOrder) return comments;
    return comments.reversed.toList(growable: false);
  }

  Future<void> _scrollToTargetComment() async {
    var targetContext = _targetCommentKey.currentContext;
    if (targetContext == null && _scrollController.hasClients) {
      final comments = _comments;
      final index = comments.indexWhere(
        (post) => post.pid == widget.initialTargetPid,
      );
      if (index >= 0) {
        // 评论卡片高度不固定，不能用“楼层数 × 固定高度”定位。按目标在
        // 当前窗口中的比例多次校准，让 Sliver 在每次布局后修正总高度估算。
        for (var attempt = 0; attempt < 3 && targetContext == null; attempt++) {
          final itemIndex = index + (_targetMode ? 1 : 0);
          final itemCount = comments.length + (_targetMode ? 2 : 1);
          final fraction = itemCount <= 1 ? 0.0 : itemIndex / (itemCount - 1);
          final estimated =
              _scrollController.position.maxScrollExtent * fraction;
          _scrollController.jumpTo(
            estimated
                .clamp(
                  _scrollController.position.minScrollExtent,
                  _scrollController.position.maxScrollExtent,
                )
                .toDouble(),
          );
          await WidgetsBinding.instance.endOfFrame;
          targetContext = _targetCommentKey.currentContext;
        }
      }
    }
    if (targetContext == null) return;
    await Scrollable.ensureVisible(
      targetContext,
      alignment: 0.14,
      duration: const Duration(milliseconds: 460),
      curve: Curves.easeInOutCubic,
    );
  }

  Future<void> _restoreCommentOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      final reverse = prefs.getBool(_commentReverseOrderKey) ?? false;
      if (reverse != _reverseOrder) {
        setState(() => _reverseOrder = reverse);
      }
    } catch (_) {
      // 排序偏好读取失败不影响评论区使用，默认保持正序。
    }
  }

  Future<void> _setCommentOrder(bool reverse) async {
    if (_targetMode) return;
    if (_reverseOrder == reverse) return;

    setState(() => _reverseOrder = reverse);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_commentReverseOrderKey, reverse);
    } catch (_) {
      // 偏好保存失败只影响下次默认排序，不影响当前排序。
    }

    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_scrollController.hasClients) return;
    _scrollController.jumpTo(_scrollController.position.minScrollExtent);
  }

  void _onComposerChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadAllComments() async {
    if (_loadingAll) return;
    setState(() {
      _loadingAll = true;
      _loadAllFailed = false;
    });

    try {
      while (mounted && widget.hasMore()) {
        if (widget.isLoadingMore()) {
          await Future<void>.delayed(const Duration(milliseconds: 40));
          continue;
        }

        final beforeCount = _threadComments(widget.detail).length;
        await widget.onLoadMore();
        if (!mounted) return;
        final afterCount = _threadComments(widget.detail).length;

        if (afterCount <= beforeCount) {
          if (widget.hasMore()) _loadAllFailed = true;
          break;
        }
      }
    } finally {
      if (mounted) {
        setState(() => _loadingAll = false);
      }
    }
  }

  Widget _buildCommentCard(Post post) {
    final targetPid = widget.initialTargetPid?.trim() ?? '';
    final targeted = post.pid == targetPid;
    final contextHighlighted = post.pid == _contextHighlightPid;
    final chronological = _filteredComments;
    final parentPid = _commentThreadService.resolveParentPid(
      post,
      chronological,
    );
    final parent = parentPid == null
        ? null
        : _findPost(chronological, parentPid);
    final itemKey = targeted
        ? _targetCommentKey
        : _commentKeys.putIfAbsent(post.pid, () => GlobalKey());

    return Container(
      key: itemKey,
      child: RepaintBoundary(
        child: _PostCard(
          post: post,
          replyParent: parent,
          hideQuotedContext: parent != null,
          highlighted: targeted || contextHighlighted,
          onReplyContextTap:
              parent == null ? null : () => _scrollToLoadedComment(parent.pid),
          onReply: () => _startReply(post),
          onEdit: widget.canEdit(post)
              ? () {
                  Navigator.pop(context);
                  Future.microtask(() => widget.onEdit(post));
                }
              : null,
          onImageTap: (imageIndex) => widget.onImageTap(post, imageIndex),
        ),
      ),
    );
  }

  Future<void> _scrollToLoadedComment(String pid) async {
    final comments = _comments;
    final index = comments.indexWhere((post) => post.pid == pid);
    if (index < 0 || !_scrollController.hasClients) return;
    if (mounted) setState(() => _contextHighlightPid = pid);

    BuildContext? targetContext = pid == widget.initialTargetPid
        ? _targetCommentKey.currentContext
        : _commentKeys[pid]?.currentContext;
    for (var attempt = 0; attempt < 3 && targetContext == null; attempt++) {
      final itemIndex = index + (_targetMode ? 1 : 0);
      final itemCount = comments.length + (_targetMode ? 2 : 1);
      final fraction = itemCount <= 1 ? 0.0 : itemIndex / (itemCount - 1);
      _scrollController.jumpTo(
        (_scrollController.position.maxScrollExtent * fraction)
            .clamp(
              _scrollController.position.minScrollExtent,
              _scrollController.position.maxScrollExtent,
            )
            .toDouble(),
      );
      await WidgetsBinding.instance.endOfFrame;
      targetContext = pid == widget.initialTargetPid
          ? _targetCommentKey.currentContext
          : _commentKeys[pid]?.currentContext;
    }
    if (targetContext == null) {
      if (mounted && _contextHighlightPid == pid) {
        setState(() => _contextHighlightPid = null);
      }
      return;
    }
    await Scrollable.ensureVisible(
      targetContext,
      alignment: 0.18,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeInOutCubic,
    );
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (mounted && _contextHighlightPid == pid) {
      setState(() => _contextHighlightPid = null);
    }
  }

  Widget _buildCommentsTail({
    required ThemeData theme,
    required ColorScheme colors,
    required bool loading,
    required bool hasMore,
  }) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_loadAllFailed && hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Center(
          child: FilledButton.tonalIcon(
            onPressed: _loadAllComments,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('重新加载全部评论'),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: Text(
          '已加载全部评论',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.outline,
          ),
        ),
      ),
    );
  }

  Widget _buildTargetWindowEdge({
    required ThemeData theme,
    required ColorScheme colors,
    required bool previous,
  }) {
    final loading = previous
        ? _loadingPreviousTargetPage
        : _loadingNextTargetPage;
    final failed = previous
        ? _previousTargetPageFailed
        : _nextTargetPageFailed;
    final hasPage = previous
        ? _hasPreviousTargetPage
        : _hasNextTargetPage;

    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 14),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (failed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: TextButton.icon(
            onPressed: () => _loadTargetPage(previous: previous),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(previous ? '重试加载更早楼层' : '重试加载后续楼层'),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Text(
          hasPage
              ? (previous ? '继续上滑加载更早楼层' : '继续下滑加载后续楼层')
              : (previous ? '已到最早楼层' : '已到最后楼层'),
          style: theme.textTheme.bodySmall?.copyWith(color: colors.outline),
        ),
      ),
    );
  }

  void _ensureLogin() {
    if (ApiService.instance.isLoggedIn) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('请先登录后再评论')),
    );
  }

  void _startReply(Post post) {
    if (!ApiService.instance.isLoggedIn) {
      _ensureLogin();
      return;
    }
    setState(() {
      _replyTarget = post;
      _showSmileys = false;
    });
    _composerFocusNode.requestFocus();
  }

  void _cancelReply() {
    setState(() => _replyTarget = null);
  }

  void _toggleSmileys() {
    if (!ApiService.instance.isLoggedIn) {
      _ensureLogin();
      return;
    }
    if (_showSmileys) {
      setState(() => _showSmileys = false);
      _composerFocusNode.requestFocus();
      return;
    }
    _composerFocusNode.unfocus();
    setState(() => _showSmileys = true);
  }

  void _hideSmileysForKeyboard() {
    if (!ApiService.instance.isLoggedIn) {
      _ensureLogin();
      return;
    }
    if (_showSmileys) setState(() => _showSmileys = false);
  }

  void _insertSmiley(String url) {
    final marker = SmileyCatalog.markerForUrl(url);
    if (marker == null) return;

    final value = _composerController.value;
    final selection = value.selection;
    final hasSelection = selection.isValid &&
        selection.start >= 0 &&
        selection.end >= 0;
    final start = hasSelection ? selection.start : value.text.length;
    final end = hasSelection ? selection.end : start;
    final nextText = value.text.replaceRange(start, end, marker);
    final nextOffset = start + marker.length;

    _composerController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextOffset),
      composing: TextRange.empty,
    );
  }

  Future<void> _sendComment() async {
    if (_sending) return;
    if (!ApiService.instance.isLoggedIn) {
      _ensureLogin();
      return;
    }

    final editorValue = _composerController.text.trim();
    if (editorValue.isEmpty) return;
    final message = SmileyCatalog.toForumBbCode(editorValue).trim();
    if (message.isEmpty) return;

    setState(() => _sending = true);
    try {
      final target = _replyTarget;
      final result = await ApiService.instance.replyThread(
        tid: widget.detail.tid,
        fid: widget.detail.fid,
        noticeauthor: widget.detail.noticeauthor,
        message: message,
        repquotePid: target?.pid,
      );

      if (!mounted) return;
      if (!result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.message)),
        );
        return;
      }

      _composerController.clear();
      setState(() {
        _replyTarget = null;
        _showSmileys = false;
      });
      _composerFocusNode.unfocus();

      try {
        if (_targetMode) {
          await _refreshLoadedTargetWindow();
        } else {
          await widget.onRefresh();
          if (!mounted) return;
          await _loadAllComments();
        }
      } catch (_) {
        // 回复已成功时，刷新失败不应把发送结果判成失败。
      }
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('评论成功')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('评论失败：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final media = MediaQuery.of(context);
    final comments = _comments;
    final rawCommentCount = _threadComments(widget.detail).length;
    final allCommentsFiltered = rawCommentCount > 0 && comments.isEmpty;
    final loading = _loadingAll ||
        widget.isLoadingMore() ||
        (_targetMode &&
            (_loadingPreviousTargetPage || _loadingNextTargetPage));
    final hasMore = _targetMode
        ? _hasPreviousTargetPage || _hasNextTargetPage
        : widget.hasMore();
    final loggedIn = ApiService.instance.isLoggedIn;
    final canSend = loggedIn &&
        !_sending &&
        _composerController.text.trim().isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: FractionallySizedBox(
        heightFactor: 0.92,
        child: Material(
          color: colors.surface,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 8, 10),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: colors.secondaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.forum_rounded,
                        color: colors.onSecondaryContainer,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.initialTargetPid?.trim().isNotEmpty == true
                                ? '已定位到回复'
                                : '评论区',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            _loadingAll
                                ? '正在加载全部评论…'
                                : comments.isEmpty
                                    ? (allCommentsFiltered
                                        ? '已过滤 $rawCommentCount 条评论'
                                        : '暂无评论')
                                    : _targetMode
                                        ? '已加载 ${comments.length} 条 · '
                                            '第 $_minLoadedPage-$_maxLoadedPage 页'
                                        : '${comments.length} 条评论 · '
                                            '${_reverseOrder ? '倒序' : '正序'}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: _targetMode
                          ? '定位模式按楼层正序显示'
                          : (_reverseOrder
                              ? '当前倒序，点击切换正序'
                              : '当前正序，点击切换倒序'),
                      onPressed: _loadingAll || _targetMode
                          ? null
                          : () => _setCommentOrder(!_reverseOrder),
                      icon: Icon(
                        _reverseOrder
                            ? Icons.arrow_downward_rounded
                            : Icons.arrow_upward_rounded,
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Divider(color: colors.outlineVariant, height: 1),
              Expanded(
                child: comments.isEmpty && !loading && !hasMore
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.chat_bubble_outline_rounded,
                              size: 42,
                              color: colors.outline,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              allCommentsFiltered ? '评论已被过滤' : '还没有评论',
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              allCommentsFiltered
                                  ? '当前评论均命中过滤关键词'
                                  : '来发表第一条评论吧',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.outline,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
                        itemCount: comments.length + (_targetMode ? 2 : 1),
                        itemBuilder: (context, index) {
                          if (_targetMode && index == 0) {
                            return _buildTargetWindowEdge(
                              theme: theme,
                              colors: colors,
                              previous: true,
                            );
                          }

                          final commentIndex =
                              _targetMode ? index - 1 : index;
                          if (commentIndex == comments.length) {
                            if (_targetMode) {
                              return _buildTargetWindowEdge(
                                theme: theme,
                                colors: colors,
                                previous: false,
                              );
                            }
                            return _buildCommentsTail(
                              theme: theme,
                              colors: colors,
                              loading: loading,
                              hasMore: hasMore,
                            );
                          }
                          return _buildCommentCard(comments[commentIndex]);
                        },
                      ),
              ),
              _CommentComposer(
                controller: _composerController,
                focusNode: _composerFocusNode,
                loggedIn: loggedIn,
                sending: _sending,
                canSend: canSend,
                showSmileys: _showSmileys,
                replyTargetName: _replyTarget?.authorName,
                onTapInput: _hideSmileysForKeyboard,
                onToggleSmileys: _toggleSmileys,
                onCancelReply: _cancelReply,
                onSend: _sendComment,
                onSmileySelected: _insertSmiley,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommentComposer extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool loggedIn;
  final bool sending;
  final bool canSend;
  final bool showSmileys;
  final String? replyTargetName;
  final VoidCallback onTapInput;
  final VoidCallback onToggleSmileys;
  final VoidCallback onCancelReply;
  final VoidCallback onSend;
  final ValueChanged<String> onSmileySelected;

  const _CommentComposer({
    required this.controller,
    required this.focusNode,
    required this.loggedIn,
    required this.sending,
    required this.canSend,
    required this.showSmileys,
    required this.replyTargetName,
    required this.onTapInput,
    required this.onToggleSmileys,
    required this.onCancelReply,
    required this.onSend,
    required this.onSmileySelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Material(
      color: colors.surfaceContainerLow,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: colors.outlineVariant),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (replyTargetName?.trim().isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 0, 2, 6),
                child: Row(
                  children: [
                    Icon(
                      Icons.reply_rounded,
                      size: 16,
                      color: colors.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '回复 @$replyTargetName',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '取消回复',
                      visualDensity: VisualDensity.compact,
                      onPressed: onCancelReply,
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                  ],
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: '表情',
                  isSelected: showSmileys,
                  onPressed: loggedIn ? onToggleSmileys : null,
                  icon: Icon(
                    showSmileys
                        ? Icons.keyboard_rounded
                        : Icons.sentiment_satisfied_alt_rounded,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    readOnly: !loggedIn,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.newline,
                    onTap: onTapInput,
                    decoration: InputDecoration(
                      hintText: loggedIn
                          ? (replyTargetName?.trim().isNotEmpty == true
                              ? '回复 @$replyTargetName…'
                              : '写下你的评论…')
                          : '登录后参与评论',
                      filled: true,
                      fillColor: colors.surfaceContainerHighest,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: '发送',
                  onPressed: canSend ? onSend : null,
                  icon: sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                ),
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              child: showSmileys
                  ? Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: SizedBox(
                        height: 220,
                        child: _SmileyPicker(
                          onSelected: onSmileySelected,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _PostCard extends StatelessWidget {
  final Post post;
  final Post? replyParent;
  final bool highlighted;
  final bool hideQuotedContext;
  final VoidCallback? onReplyContextTap;
  final VoidCallback onReply;
  final VoidCallback? onEdit;
  final ValueChanged<int> onImageTap;

  const _PostCard({
    required this.post,
    this.replyParent,
    this.highlighted = false,
    this.hideQuotedContext = false,
    this.onReplyContextTap,
    required this.onReply,
    this.onEdit,
    required this.onImageTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final visibleRichContent = hideQuotedContext
        ? post.richContent
            .where(
              (item) =>
                  item.type != PostContentType.quote &&
                  item.type != PostContentType.richQuote,
            )
            .toList(growable: false)
        : post.richContent;
    final content = hideQuotedContext
        ? _contentWithoutQuotedContext(post)
        : post.content.trim();
    final postTime = post.postTime?.trim() ?? '';
    final replyParentFloor = replyParent == null
        ? ''
        : (_floorText(replyParent!.floor).isEmpty
            ? '原评论'
            : _floorText(replyParent!.floor));
    final richImageUrls = visibleRichContent
        .where((item) => item.type == PostContentType.image)
        .map((item) => item.url)
        .whereType<String>()
        .toSet();
    final detachedImages = post.images
        .where(
          (url) =>
              !richImageUrls.contains(url) &&
              !SmileyCatalog.isForumSmileyUrl(url),
        )
        .toList(growable: false);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: highlighted
          ? Color.alphaBlend(
              colors.primary.withValues(alpha: 0.10),
              colors.surfaceContainerLow,
            )
          : colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: highlighted ? colors.primary : colors.outlineVariant,
          width: highlighted ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (post.isOp) ...[
                  Container(
                    width: 3,
                    height: 34,
                    decoration: BoxDecoration(
                      color: colors.primary,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                InkWell(
                  customBorder: const CircleBorder(),
                  onTap: post.authorUid == null
                      ? null
                      : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => UserProfilePage(
                                uid: post.authorUid!,
                              ),
                            ),
                          ),
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: colors.surfaceContainerHighest,
                    backgroundImage: post.avatarUrl == null
                        ? null
                        : CachedNetworkImageProvider(post.avatarUrl!),
                    child: post.avatarUrl == null
                        ? Text(_initial(post.authorName))
                        : null,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              post.authorName ?? '匿名',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (post.isOp) ...[
                            const SizedBox(width: 6),
                            _Pill(text: '楼主', primary: true),
                          ],
                        ],
                      ),
                      if ((post.authorLevel?.trim().isNotEmpty ?? false) ||
                          postTime.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 5,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (post.authorLevel != null &&
                                  post.authorLevel!.trim().isNotEmpty)
                                UserLevelBadge(
                                  text: post.authorLevel!,
                                ),
                              if (postTime.isNotEmpty)
                                _PostTimeLabel(time: postTime),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _Pill(text: _floorText(post.floor)),
              ],
            ),
            if (replyParent != null) ...[
              const SizedBox(height: 9),
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: onReplyContextTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: colors.primaryContainer.withValues(alpha: 0.42),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.subdirectory_arrow_left_rounded,
                        size: 16,
                        color: colors.primary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '回复 $replyParentFloor '
                          '@${replyParent!.authorName ?? post.replyToName ?? '用户'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: colors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.my_location_rounded,
                        size: 15,
                        color: colors.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ] else if (post.replyToName != null) ...[
              const SizedBox(height: 9),
              Text(
                '回复 @${post.replyToName}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.primary,
                ),
              ),
            ],
            if (visibleRichContent.isNotEmpty) ...[
              const SizedBox(height: 10),
              _RichContentView(
                contents: visibleRichContent,
                onImageTap: (url) {
                  final index = post.images.indexOf(url);
                  if (index >= 0) {
                    onImageTap(index);
                  }
                },
              ),
            ] else if (content.isNotEmpty) ...[
              const SizedBox(height: 10),
              SelectableText(
                content,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
              ),
            ],
            if (post.hiddenHint != null && post.hiddenHint!.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: colors.tertiaryContainer.withValues(alpha: 0.30),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 16,
                      color: colors.onTertiaryContainer,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        post.hiddenHint!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onTertiaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (detachedImages.isNotEmpty) ...[
              const SizedBox(height: 10),
              _PostImages(
                images: detachedImages,
                onTap: (index) {
                  final originalIndex = post.images.indexOf(detachedImages[index]);
                  if (originalIndex >= 0) {
                    onImageTap(originalIndex);
                  }
                },
              ),
            ],
            if (!post.isOp || onEdit != null) ...[
              const SizedBox(height: 2),
              Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onEdit != null)
                      TextButton.icon(
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: const Text('编辑'),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    if (!post.isOp)
                      TextButton.icon(
                        onPressed: onReply,
                        icon: const Icon(Icons.reply_rounded, size: 16),
                        label: const Text('回复'),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _contentWithoutQuotedContext(Post post) {
    var value = post.content.trim();
    final quoted = post.replyQuoteText?.trim() ?? '';
    if (quoted.isNotEmpty) {
      final index = value.indexOf(quoted);
      if (index >= 0) {
        value = value.substring(index + quoted.length).trim();
      }
    }
    return value;
  }

  String _initial(String? name) {
    final value = name?.trim() ?? '';
    return value.isEmpty ? '?' : value.substring(0, 1);
  }

  String _floorText(String? floor) {
    if (floor == null || floor.isEmpty) return '';
    if (floor == '1') return '楼主';
    return '$floor楼';
  }
}

class _PostTimeLabel extends StatelessWidget {
  final String time;

  const _PostTimeLabel({required this.time});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Semantics(
      label: '评论时间 $time',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.schedule_rounded,
            size: 13,
            color: colors.outline,
          ),
          const SizedBox(width: 3),
          Text(
            time,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w500,
              height: 1.15,
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final bool primary;

  const _Pill({required this.text, this.primary = false});

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: primary ? colors.primaryContainer : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: primary ? colors.onPrimaryContainer : colors.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

Color? _parseBbColor(String? raw) {
  if (raw == null) return null;
  var value = raw.trim().toLowerCase();
  if (value.isEmpty) return null;
  const named = <String, Color>{
    'black': Colors.black,
    'white': Colors.white,
    'red': Colors.red,
    'green': Colors.green,
    'blue': Colors.blue,
    'yellow': Colors.yellow,
    'orange': Colors.orange,
    'purple': Colors.purple,
    'pink': Colors.pink,
    'grey': Colors.grey,
    'gray': Colors.grey,
    'cyan': Colors.cyan,
    'teal': Colors.teal,
  };
  if (named.containsKey(value)) return named[value];

  final rgb = RegExp(
    r'^rgba?\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})',
  ).firstMatch(value);
  if (rgb != null) {
    return Color.fromARGB(
      255,
      (int.tryParse(rgb.group(1)!) ?? 0).clamp(0, 255).toInt(),
      (int.tryParse(rgb.group(2)!) ?? 0).clamp(0, 255).toInt(),
      (int.tryParse(rgb.group(3)!) ?? 0).clamp(0, 255).toInt(),
    );
  }

  value = value.replaceFirst('#', '');
  if (value.length == 3) {
    value = value.split('').map((part) => '$part$part').join();
  }
  if (!RegExp(r'^[0-9a-f]{6}([0-9a-f]{2})?$').hasMatch(value)) return null;
  final parsed = int.tryParse(value, radix: 16);
  if (parsed == null) return null;
  return value.length == 8
      ? Color.fromARGB(
          parsed & 0xff,
          (parsed >> 24) & 0xff,
          (parsed >> 16) & 0xff,
          (parsed >> 8) & 0xff,
        )
      : Color(0xff000000 | parsed);
}

class _RichContentView extends StatelessWidget {
  final List<PostContent> contents;
  final ValueChanged<String>? onImageTap;

  const _RichContentView({
    required this.contents,
    this.onImageTap,
  });

  Future<void> _openUrl(BuildContext context, String url) async {
    await _openPostLink(context, url);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final widgets = <Widget>[];
    final inline = <PostContent>[];

    void flushInline() {
      if (inline.isEmpty) {
        return;
      }

      widgets.add(
        _InlineRichText(
          contents: List<PostContent>.from(inline),
        ),
      );
      inline.clear();
    }

    for (final content in contents) {
      switch (content.type) {
        case PostContentType.text:
        case PostContentType.bold:
        case PostContentType.link:
        case PostContentType.emoji:
          inline.add(content);

        case PostContentType.image:
          flushInline();

          final url = content.url;
          if (url == null || url.isEmpty) {
            break;
          }

          widgets.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: GestureDetector(
                onTap: () => onImageTap?.call(url),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.fitWidth,
                    placeholder: (_, __) => Container(
                      constraints: const BoxConstraints(minHeight: 140),
                      color: colors.surfaceContainerHigh,
                      alignment: Alignment.center,
                      child: const CircularProgressIndicator(),
                    ),
                    errorWidget: (_, __, ___) => Container(
                      height: 120,
                      color: colors.surfaceContainerHighest,
                      alignment: Alignment.center,
                      child: const Icon(Icons.broken_image_outlined),
                    ),
                  ),
                ),
              ),
            ),
          );

        case PostContentType.quote:
          flushInline();
          widgets.add(
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(vertical: 6),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
                border: Border(
                  left: BorderSide(
                    color: colors.primary,
                    width: 3,
                  ),
                ),
              ),
              child: SelectableText(
                content.text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ),
          );

        case PostContentType.richQuote:
          flushInline();
          if (content.children.isEmpty) {
            break;
          }
          widgets.add(
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(vertical: 6),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
                border: Border(
                  left: BorderSide(
                    color: colors.primary,
                    width: 3,
                  ),
                ),
              ),
              child: _InlineRichText(
                contents: content.children,
              ),
            ),
          );

        case PostContentType.code:
          flushInline();
          widgets.add(
            _CodeBlock(code: content.text),
          );

        case PostContentType.free:
          flushInline();
          widgets.add(
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(vertical: 6),
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: colors.secondaryContainer.withValues(alpha: 0.40),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: colors.onSecondaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SelectableText(
                      content.text,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSecondaryContainer,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );

        case PostContentType.attachment:
          flushInline();
          widgets.add(
            _AttachmentCard(
              name: content.text.trim().isEmpty ? '附件' : content.text.trim(),
              url: content.url,
              onOpen: content.url == null || content.url!.isEmpty
                  ? null
                  : () => _openUrl(context, content.url!),
            ),
          );

        case PostContentType.table:
          flushInline();
          if (content.tableRows.isNotEmpty) {
            widgets.add(
              _TableBlock(
                rows: content.tableRows,
                headerRows: content.tableHeaderRows,
              ),
            );
          }

        case PostContentType.divider:
          flushInline();
          widgets.add(
            Divider(
              height: 24,
              thickness: 1,
              color: colors.outlineVariant,
            ),
          );

        case PostContentType.aligned:
          flushInline();
          if (content.children.isNotEmpty) {
            final alignment = switch (content.alignment) {
              'center' => Alignment.center,
              'right' => Alignment.centerRight,
              _ => Alignment.centerLeft,
            };
            widgets.add(
              Align(
                alignment: alignment,
                child: _RichContentView(
                  contents: content.children,
                  onImageTap: onImageTap,
                ),
              ),
            );
          }

        case PostContentType.list:
          flushInline();
          if (content.children.isNotEmpty) {
            widgets.add(
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                child: _RichContentView(
                  contents: content.children,
                  onImageTap: onImageTap,
                ),
              ),
            );
          }

        case PostContentType.audio:
          flushInline();
          if (content.url != null) {
            widgets.add(
              _MediaCard(
                icon: Icons.audiotrack_rounded,
                title: '音频',
                subtitle: content.url!,
                actionLabel: '播放',
                onTap: () => _openUrl(context, content.url!),
              ),
            );
          }

        case PostContentType.video:
          flushInline();
          if (content.url != null) {
            widgets.add(
              _MediaCard(
                icon: Icons.play_circle_outline_rounded,
                title: '视频',
                subtitle: content.url!,
                actionLabel: '播放',
                onTap: () => _openUrl(context, content.url!),
              ),
            );
          }

        case PostContentType.flash:
          flushInline();
          if (content.url != null) {
            widgets.add(
              _MediaCard(
                icon: Icons.extension_off_outlined,
                title: 'Flash 内容',
                subtitle: 'Android 已不原生支持 Flash · 点击尝试外部打开',
                actionLabel: '打开',
                onTap: () => _openUrl(context, content.url!),
              ),
            );
          }
      }
    }

    flushInline();

    // 让整段帖子正文进入同一个选择区域，普通文字、引用、链接前后
    // 的内容都可以长按框选/复制；图片和链接点击行为保持不变。
    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: widgets,
      ),
    );
  }
}

class _InlineRichText extends StatefulWidget {
  final List<PostContent> contents;

  const _InlineRichText({
    required this.contents,
  });

  @override
  State<_InlineRichText> createState() => _InlineRichTextState();
}

class _InlineRichTextState extends State<_InlineRichText> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  Future<void> _openUrl(String url) async {
    await _openPostLink(context, url);
  }

  @override
  void didUpdateWidget(_InlineRichText oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 只在内容真正变化时才重建手势识别器，避免每次 build 都 dispose+重建导致闪烁。
    if (!_sameContents(oldWidget.contents, widget.contents)) {
      _disposeRecognizers();
    }
  }

  bool _sameContents(List<PostContent> a, List<PostContent> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].type != b[i].type ||
          a[i].text != b[i].text ||
          a[i].url != b[i].url ||
          a[i].isBold != b[i].isBold ||
          a[i].isItalic != b[i].isItalic ||
          a[i].isUnderline != b[i].isUnderline ||
          a[i].isStrikethrough != b[i].isStrikethrough ||
          a[i].color != b[i].color ||
          a[i].backgroundColor != b[i].backgroundColor ||
          a[i].fontFamily != b[i].fontFamily ||
          a[i].fontSizeScale != b[i].fontSizeScale) {
        return false;
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final baseStyle = theme.textTheme.bodyMedium?.copyWith(height: 1.55);
    final spans = <InlineSpan>[];

    TextStyle? contentStyle(PostContent content, {bool link = false}) {
      final decorations = <TextDecoration>[];
      if (content.isUnderline || link) decorations.add(TextDecoration.underline);
      if (content.isStrikethrough) decorations.add(TextDecoration.lineThrough);
      final parsedColor = _parseBbColor(content.color);
      final parsedBackground = _parseBbColor(content.backgroundColor);
      return baseStyle?.copyWith(
        color: parsedColor ?? (link ? colors.primary : null),
        backgroundColor: parsedBackground,
        fontWeight: content.isBold || content.type == PostContentType.bold
            ? FontWeight.w700
            : null,
        fontStyle: content.isItalic ? FontStyle.italic : null,
        decoration: decorations.isEmpty
            ? null
            : TextDecoration.combine(decorations),
        decorationColor: parsedColor ?? (link ? colors.primary : null),
        decorationThickness: decorations.isEmpty ? null : 1,
        fontFamily: content.fontFamily,
        fontSize: content.fontSizeScale == null || baseStyle?.fontSize == null
            ? null
            : baseStyle!.fontSize! * content.fontSizeScale!,
      );
    }

    for (final content in widget.contents) {
      switch (content.type) {
        case PostContentType.text:
          spans.add(
            TextSpan(
              text: content.text,
              style: contentStyle(content),
            ),
          );

        case PostContentType.bold:
          spans.add(
            TextSpan(
              text: content.text,
              style: contentStyle(content),
            ),
          );

        case PostContentType.link:
          final url = content.url;
          if (url == null || url.isEmpty) {
            spans.add(TextSpan(text: content.text, style: contentStyle(content)));
            continue;
          }

          final recognizer = TapGestureRecognizer()
            ..onTap = () => _openUrl(url);
          _recognizers.add(recognizer);

          spans.add(
            TextSpan(
              text: content.text,
              recognizer: recognizer,
              mouseCursor: SystemMouseCursors.click,
              style: contentStyle(content, link: true),
            ),
          );

        case PostContentType.emoji:
          final url = content.url;
          if (url == null || url.isEmpty) {
            continue;
          }

          spans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: CachedNetworkImage(
                  imageUrl: url,
                  width: 22,
                  height: 22,
                  errorWidget: (_, __, ___) =>
                      const SizedBox(width: 22, height: 22),
                ),
              ),
            ),
          );

        default:
          break;
      }
    }

    return RichText(
      text: TextSpan(
        style: baseStyle,
        children: spans,
      ),
      selectionRegistrar: SelectionContainer.maybeOf(context),
      selectionColor: colors.primary.withValues(alpha: 0.24),
    );
  }
}

class _CodeBlock extends StatelessWidget {
  final String code;

  const _CodeBlock({
    required this.code,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final language = _CodeSyntax.detect(code);
    final languageColor = _CodeSyntax.languageColor(
      language,
      theme.brightness,
    );

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: colors.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 7, 6, 5),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: languageColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  language.label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: '复制代码',
                  visualDensity: VisualDensity.compact,
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: code),
                    );

                    if (!context.mounted) {
                      return;
                    }

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('代码已复制'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                  icon: const Icon(
                    Icons.copy_rounded,
                    size: 17,
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: colors.outlineVariant,
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: SelectableText.rich(
              _CodeSyntax.highlight(
                code,
                language: language,
                context: context,
              ),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
                height: 1.48,
                color: colors.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CodeLanguage {
  final String id;
  final String label;

  const _CodeLanguage(this.id, this.label);
}

class _CodeSyntax {
  static const _plain = _CodeLanguage('plain', '代码');
  static const _cpp = _CodeLanguage('cpp', 'C / C++');
  static const _java = _CodeLanguage('java', 'Java');
  static const _kotlin = _CodeLanguage('kotlin', 'Kotlin');
  static const _dart = _CodeLanguage('dart', 'Dart');
  static const _python = _CodeLanguage('python', 'Python');
  static const _shell = _CodeLanguage('shell', 'Shell');
  static const _javascript = _CodeLanguage('javascript', 'JavaScript');
  static const _typescript = _CodeLanguage('typescript', 'TypeScript');
  static const _rust = _CodeLanguage('rust', 'Rust');
  static const _go = _CodeLanguage('go', 'Go');
  static const _json = _CodeLanguage('json', 'JSON');
  static const _xml = _CodeLanguage('xml', 'HTML / XML');
  static const _sql = _CodeLanguage('sql', 'SQL');
  static const _smali = _CodeLanguage('smali', 'Smali');

  static _CodeLanguage detect(String code) {
    final text = code.trim();
    final lower = text.toLowerCase();

    if (text.isEmpty) {
      return _plain;
    }

    if (RegExp(
      r'(^|\n)\s*\.(?:class|super|method|end method|locals|registers)\b'
      r'|invoke-(?:virtual|static|direct)'
      r'|Landroid/',
      multiLine: true,
      caseSensitive: false,
    ).hasMatch(text)) {
      return _smali;
    }

    if (RegExp(
      r'(^|\n)\s*#!\s*/(?:usr/)?bin/(?:ba)?sh\b'
      r'|(^|\n)\s*(?:git\s+clone|npx|npm|pnpm|yarn|curl|wget|adb|fastboot|flutter|dart|python(?:3)?|pip(?:3)?|docker|cargo|gradle|\.\/gradlew)\b'
      r'|\b(?:apt|apk|yum|dnf|pacman)\s+(?:install|update)\b'
      r'|\bexport\s+[A-Za-z_][A-Za-z0-9_]*='
      r'|\$\{?[A-Za-z_][A-Za-z0-9_]*\}?',
      multiLine: true,
      caseSensitive: false,
    ).hasMatch(text)) {
      return _shell;
    }

    if (RegExp(
      r'\bfun\s+[A-Za-z_]\w*\s*\('
      r'|\b(?:val|var)\s+[A-Za-z_]\w*'
      r'|\boverride\s+fun\b'
      r'|\bdata\s+class\b',
    ).hasMatch(text)) {
      return _kotlin;
    }

    if (lower.contains('package:flutter/') ||
        (RegExp(r'\bWidget\s+build\s*\(').hasMatch(text) &&
            RegExp(r'\b(?:final|const)\s+[A-Za-z_]\w*\s*=').hasMatch(text))) {
      return _dart;
    }

    if (RegExp(
      r'\bpublic\s+(?:final\s+)?class\b'
      r'|\bstatic\s+void\s+main\s*\('
      r'|\bimport\s+java\.',
    ).hasMatch(text)) {
      return _java;
    }

    if (RegExp(
      r'^\s*#include\s*[<"]'
      r'|\bstd::'
      r'|\b(?:int|void)\s+main\s*\('
      r'|\b(?:printf|cout|cin)\b',
      multiLine: true,
    ).hasMatch(text)) {
      return _cpp;
    }

    if (RegExp(
      r'\bfn\s+main\s*\('
      r'|\blet\s+mut\b'
      r'|\bprintln!\s*\('
      r'|\buse\s+std::',
    ).hasMatch(text)) {
      return _rust;
    }

    if (RegExp(
      r'(^|\n)\s*package\s+main\b'
      r'|\bfunc\s+main\s*\('
      r'|\bfmt\.(?:Print|Printf|Println)\b',
      multiLine: true,
    ).hasMatch(text)) {
      return _go;
    }

    if (RegExp(
      r'\binterface\s+[A-Za-z_]\w*'
      r'|\btype\s+[A-Za-z_]\w*\s*='
      r'|:\s*(?:string|number|boolean|unknown|never)\b',
    ).hasMatch(text)) {
      return _typescript;
    }

    if (RegExp(
      r'\b(?:const|let)\s+[A-Za-z_$][\w$]*\s*='
      r'|=>'
      r'|\bconsole\.(?:log|error|warn)\s*\('
      r'|\bfunction\s+[A-Za-z_$][\w$]*\s*\(',
    ).hasMatch(text)) {
      return _javascript;
    }

    if (RegExp(
      r'''(^|\n)\s*(?:def|class)\s+[A-Za-z_]\w*|\bif\s+__name__\s*==\s*["']__main__["']|(^|\n)\s*from\s+[A-Za-z_.]+\s+import\s+''',
      multiLine: true,
    ).hasMatch(text)) {
      return _python;
    }

    if (RegExp(
      r'^\s*<\??(?:!doctype|html|[A-Za-z_][\w:.-]*)'
      r'|</[A-Za-z_][\w:.-]*>',
      caseSensitive: false,
    ).hasMatch(text)) {
      return _xml;
    }

    if (RegExp(r'^\s*[\{\[]').hasMatch(text) &&
        RegExp(r'"[^"]+"\s*:').hasMatch(text)) {
      return _json;
    }

    if (RegExp(
      r'\bselect\b[\s\S]+\bfrom\b'
      r'|\binsert\s+into\b'
      r'|\bupdate\b[\s\S]+\bset\b'
      r'|\bcreate\s+table\b',
      caseSensitive: false,
    ).hasMatch(text)) {
      return _sql;
    }

    return _plain;
  }

  static Color languageColor(
    _CodeLanguage language,
    Brightness brightness,
  ) {
    final dark = brightness == Brightness.dark;

    return switch (language.id) {
      'cpp' => dark ? const Color(0xFF76D7FF) : const Color(0xFF00658A),
      'java' => dark ? const Color(0xFFFFB77A) : const Color(0xFF8B4B00),
      'kotlin' => dark ? const Color(0xFFC7A7FF) : const Color(0xFF6541A5),
      'dart' => dark ? const Color(0xFF67D9E8) : const Color(0xFF006874),
      'python' => dark ? const Color(0xFFFFD86B) : const Color(0xFF745B00),
      'shell' => dark ? const Color(0xFF8DDA91) : const Color(0xFF246A2B),
      'javascript' => dark ? const Color(0xFFFFD54F) : const Color(0xFF705D00),
      'typescript' => dark ? const Color(0xFF82B8FF) : const Color(0xFF245EA7),
      'rust' => dark ? const Color(0xFFFFA87A) : const Color(0xFF8E3D12),
      'go' => dark ? const Color(0xFF70D7E8) : const Color(0xFF00677A),
      'json' => dark ? const Color(0xFFC5E478) : const Color(0xFF516A00),
      'xml' => dark ? const Color(0xFFFF9EC1) : const Color(0xFF9B345F),
      'sql' => dark ? const Color(0xFFB8C7FF) : const Color(0xFF40558D),
      'smali' => dark ? const Color(0xFFFF8F8F) : const Color(0xFF9D2C2C),
      _ => dark ? const Color(0xFF9DA7B7) : const Color(0xFF5F6876),
    };
  }

  static TextSpan highlight(
    String code, {
    required _CodeLanguage language,
    required BuildContext context,
  }) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    final keywordColor =
        dark ? const Color(0xFF82B1FF) : const Color(0xFF245EA7);
    final stringColor =
        dark ? const Color(0xFFC3E88D) : const Color(0xFF4F6D00);
    final commentColor =
        dark ? const Color(0xFF788493) : const Color(0xFF727B88);
    final numberColor =
        dark ? const Color(0xFFFFA07A) : const Color(0xFF9A471F);
    final annotationColor =
        dark ? const Color(0xFFC792EA) : const Color(0xFF7451A6);
    final functionColor =
        dark ? const Color(0xFFFFD580) : const Color(0xFF775A00);
    final typeColor =
        dark ? const Color(0xFF89DDFF) : const Color(0xFF00677A);

    final keywords = _keywordsFor(language.id);
    final spans = <TextSpan>[];
    final tokenPattern = RegExp(
      r'''(/\*[\s\S]*?\*/|//[^\n]*|<!--[\s\S]*?-->|#[^\n]*|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`|\b0x[0-9A-Fa-f]+\b|\b\d+(?:\.\d+)?\b|@[A-Za-z_]\w*|\b[A-Za-z_]\w*\b)''',
      multiLine: true,
    );

    var cursor = 0;

    for (final match in tokenPattern.allMatches(code)) {
      if (match.start > cursor) {
        spans.add(
          TextSpan(
            text: code.substring(cursor, match.start),
          ),
        );
      }

      final token = match.group(0)!;
      TextStyle? style;

      final isHashComment = token.startsWith('#') &&
          (language.id == 'python' || language.id == 'shell');

      if (token.startsWith('//') ||
          token.startsWith('/*') ||
          token.startsWith('<!--') ||
          isHashComment) {
        style = TextStyle(
          color: commentColor,
          fontStyle: FontStyle.italic,
        );
      } else if (token.startsWith('"') ||
          token.startsWith("'") ||
          token.startsWith('`')) {
        style = TextStyle(color: stringColor);
      } else if (RegExp(r'^(?:0x[0-9A-Fa-f]+|\d+(?:\.\d+)?)$')
          .hasMatch(token)) {
        style = TextStyle(color: numberColor);
      } else if (token.startsWith('@') ||
          (token.startsWith('#') && !isHashComment)) {
        style = TextStyle(color: annotationColor);
      } else if (_isKeyword(keywords, token, language.id)) {
        style = TextStyle(
          color: keywordColor,
          fontWeight: FontWeight.w600,
        );
      } else if (const {
        'true',
        'false',
        'null',
        'nil',
        'None',
        'undefined',
      }.contains(token)) {
        style = TextStyle(color: numberColor);
      } else {
        final after = code.substring(match.end);
        final before =
            match.start > 0 ? code.substring(0, match.start) : '';

        if (language.id == 'xml' &&
            RegExp(r'<\/?\s*$').hasMatch(before)) {
          style = TextStyle(
            color: keywordColor,
            fontWeight: FontWeight.w600,
          );
        } else if (RegExp(r'^\s*\(').hasMatch(after)) {
          style = TextStyle(color: functionColor);
        } else if (RegExp(r'^[A-Z][A-Za-z0-9_]*$').hasMatch(token)) {
          style = TextStyle(color: typeColor);
        }
      }

      spans.add(
        TextSpan(
          text: token,
          style: style ?? TextStyle(color: colors.onSurface),
        ),
      );

      cursor = match.end;
    }

    if (cursor < code.length) {
      spans.add(
        TextSpan(
          text: code.substring(cursor),
        ),
      );
    }

    return TextSpan(children: spans);
  }

  static bool _isKeyword(
    Set<String> keywords,
    String token,
    String language,
  ) {
    if (language == 'sql') {
      return keywords.contains(token.toUpperCase());
    }
    return keywords.contains(token);
  }

  static Set<String> _keywordsFor(String language) {
    switch (language) {
      case 'cpp':
        return const {
          'alignas', 'alignof', 'auto', 'bool', 'break', 'case', 'catch',
          'char', 'class', 'const', 'constexpr', 'continue', 'default',
          'delete', 'do', 'double', 'else', 'enum', 'explicit', 'extern',
          'false', 'float', 'for', 'friend', 'if', 'inline', 'int', 'long',
          'namespace', 'new', 'nullptr', 'operator', 'private', 'protected',
          'public', 'return', 'short', 'signed', 'sizeof', 'static', 'struct',
          'switch', 'template', 'this', 'throw', 'true', 'try', 'typedef',
          'typename', 'union', 'unsigned', 'using', 'virtual', 'void',
          'volatile', 'while',
        };
      case 'java':
        return const {
          'abstract', 'assert', 'boolean', 'break', 'byte', 'case', 'catch',
          'char', 'class', 'const', 'continue', 'default', 'do', 'double',
          'else', 'enum', 'extends', 'final', 'finally', 'float', 'for', 'if',
          'implements', 'import', 'instanceof', 'int', 'interface', 'long',
          'native', 'new', 'package', 'private', 'protected', 'public',
          'return', 'short', 'static', 'strictfp', 'super', 'switch',
          'synchronized', 'this', 'throw', 'throws', 'transient', 'try',
          'void', 'volatile', 'while',
        };
      case 'kotlin':
        return const {
          'as', 'break', 'class', 'continue', 'do', 'else', 'false', 'for',
          'fun', 'if', 'in', 'interface', 'is', 'null', 'object', 'package',
          'return', 'super', 'this', 'throw', 'true', 'try', 'typealias',
          'typeof', 'val', 'var', 'when', 'while', 'by', 'catch',
          'constructor', 'delegate', 'dynamic', 'field', 'file', 'finally',
          'get', 'import', 'init', 'param', 'property', 'receiver', 'set',
          'setparam', 'where',
        };
      case 'dart':
        return const {
          'abstract', 'as', 'assert', 'async', 'await', 'base', 'break',
          'case', 'catch', 'class', 'const', 'continue', 'covariant',
          'default', 'deferred', 'do', 'dynamic', 'else', 'enum', 'export',
          'extends', 'extension', 'external', 'factory', 'false', 'final',
          'finally', 'for', 'Function', 'get', 'hide', 'if', 'implements',
          'import', 'in', 'interface', 'is', 'late', 'library', 'mixin',
          'new', 'null', 'of', 'on', 'operator', 'part', 'required',
          'rethrow', 'return', 'sealed', 'set', 'show', 'static', 'super',
          'switch', 'sync', 'this', 'throw', 'true', 'try', 'typedef', 'var',
          'void', 'when', 'while', 'with', 'yield',
        };
      case 'python':
        return const {
          'and', 'as', 'assert', 'async', 'await', 'break', 'class',
          'continue', 'def', 'del', 'elif', 'else', 'except', 'False',
          'finally', 'for', 'from', 'global', 'if', 'import', 'in', 'is',
          'lambda', 'None', 'nonlocal', 'not', 'or', 'pass', 'raise',
          'return', 'True', 'try', 'while', 'with', 'yield',
        };
      case 'shell':
        return const {
          'case', 'do', 'done', 'elif', 'else', 'esac', 'export', 'fi',
          'for', 'function', 'if', 'in', 'local', 'readonly', 'return',
          'then', 'until', 'while',
        };
      case 'javascript':
      case 'typescript':
        return const {
          'async', 'await', 'break', 'case', 'catch', 'class', 'const',
          'continue', 'debugger', 'default', 'delete', 'do', 'else', 'export',
          'extends', 'false', 'finally', 'for', 'function', 'if', 'import',
          'in', 'instanceof', 'let', 'new', 'null', 'return', 'static',
          'super', 'switch', 'this', 'throw', 'true', 'try', 'typeof', 'var',
          'void', 'while', 'with', 'yield', 'interface', 'type', 'implements',
          'private', 'protected', 'public', 'readonly', 'unknown', 'never',
          'string', 'number', 'boolean',
        };
      case 'rust':
        return const {
          'as', 'break', 'const', 'continue', 'crate', 'else', 'enum',
          'extern', 'false', 'fn', 'for', 'if', 'impl', 'in', 'let', 'loop',
          'match', 'mod', 'move', 'mut', 'pub', 'ref', 'return', 'self',
          'Self', 'static', 'struct', 'super', 'trait', 'true', 'type',
          'unsafe', 'use', 'where', 'while',
        };
      case 'go':
        return const {
          'break', 'case', 'chan', 'const', 'continue', 'default', 'defer',
          'else', 'fallthrough', 'for', 'func', 'go', 'goto', 'if', 'import',
          'interface', 'map', 'package', 'range', 'return', 'select',
          'struct', 'switch', 'type', 'var',
        };
      case 'sql':
        return const {
          'ALTER', 'AND', 'AS', 'ASC', 'BEGIN', 'BY', 'CASE', 'CREATE',
          'DELETE', 'DESC', 'DISTINCT', 'DROP', 'ELSE', 'END', 'FROM',
          'GROUP', 'HAVING', 'IN', 'INNER', 'INSERT', 'INTO', 'JOIN', 'LEFT',
          'LIMIT', 'NOT', 'NULL', 'ON', 'OR', 'ORDER', 'OUTER', 'RIGHT',
          'SELECT', 'SET', 'TABLE', 'THEN', 'UNION', 'UPDATE', 'VALUES',
          'WHEN', 'WHERE',
        };
      case 'smali':
        return const {
          'class', 'super', 'method', 'end', 'locals', 'registers', 'field',
          'annotation', 'prologue', 'line', 'param', 'public', 'private',
          'protected', 'static', 'final', 'native', 'abstract', 'synthetic',
          'constructor', 'return', 'new', 'instance', 'invoke', 'virtual',
          'direct', 'move', 'result', 'const', 'string',
        };
      default:
        return const <String>{};
    }
  }
}

class _AttachmentCard extends StatelessWidget {
  final String name;
  final String? url;
  final VoidCallback? onOpen;

  const _AttachmentCard({
    required this.name,
    required this.url,
    required this.onOpen,
  });

  IconData _iconForName(String value) {
    final lower = value.toLowerCase();
    if (RegExp(r'\.(?:zip|rar|7z|tar|gz|xz)$').hasMatch(lower)) {
      return Icons.folder_zip_outlined;
    }
    if (RegExp(r'\.(?:apk|apks|xapk)$').hasMatch(lower)) {
      return Icons.android_rounded;
    }
    if (RegExp(r'\.(?:txt|md|log|json|xml|yaml|yml|ini|conf)$')
        .hasMatch(lower)) {
      return Icons.description_outlined;
    }
    if (RegExp(r'\.(?:pdf)$').hasMatch(lower)) {
      return Icons.picture_as_pdf_outlined;
    }
    return Icons.attach_file_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _iconForName(name),
              size: 21,
              color: colors.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  name,
                  maxLines: 2,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (url != null && url!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    '论坛附件',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.outline,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 6),
          IconButton.filledTonal(
            tooltip: onOpen == null ? '附件地址不可用' : '打开附件',
            onPressed: onOpen,
            icon: const Icon(Icons.open_in_new_rounded, size: 19),
          ),
        ],
      ),
    );
  }
}

class _TableBlock extends StatelessWidget {
  final List<List<String>> rows;
  final int headerRows;

  const _TableBlock({
    required this.rows,
    required this.headerRows,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final columnCount = rows.fold<int>(
      0,
      (max, row) => row.length > max ? row.length : max,
    );
    if (columnCount == 0) {
      return const SizedBox.shrink();
    }

    final normalizedRows = rows
        .map(
          (row) => List<String>.generate(
            columnCount,
            (index) => index < row.length ? row[index] : '',
          ),
        )
        .toList(growable: false);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: TableBorder.all(
            color: colors.outlineVariant,
            width: 1,
          ),
          children: [
            for (var rowIndex = 0;
                rowIndex < normalizedRows.length;
                rowIndex++)
              TableRow(
                decoration: BoxDecoration(
                  color: rowIndex < headerRows
                      ? colors.primaryContainer.withValues(alpha: 0.55)
                      : (rowIndex.isOdd
                          ? colors.surfaceContainerHighest
                              .withValues(alpha: 0.42)
                          : colors.surfaceContainerLow),
                ),
                children: [
                  for (final cell in normalizedRows[rowIndex])
                    ConstrainedBox(
                      constraints: const BoxConstraints(
                        minWidth: 84,
                        maxWidth: 280,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 9,
                        ),
                        child: SelectableText(
                          cell,
                          style: theme.textTheme.bodySmall?.copyWith(
                            height: 1.45,
                            fontWeight: rowIndex < headerRows
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: rowIndex < headerRows
                                ? colors.onPrimaryContainer
                                : colors.onSurface,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _MediaCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onTap;

  const _MediaCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: [
          Icon(icon, color: colors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.outline,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onTap,
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}

class _PostImages extends StatelessWidget {
  final List<String> images;
  final Function(int) onTap;
  const _PostImages({required this.images, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (images.length == 1) {
      return GestureDetector(
        onTap: () => onTap(0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: CachedNetworkImage(
            imageUrl: images.first, fit: BoxFit.cover,
            placeholder: (_, __) => Container(height: 200, color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Center(child: CircularProgressIndicator())),
            errorWidget: (_, __, ___) => const SizedBox.shrink()),
        ),
      );
    }
    return GridView.builder(
      shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 6, mainAxisSpacing: 6),
      itemCount: images.length,
      itemBuilder: (context, index) => GestureDetector(
        onTap: () => onTap(index),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CachedNetworkImage(
            imageUrl: images[index], fit: BoxFit.cover,
            placeholder: (_, __) => Container(color: Theme.of(context).colorScheme.surfaceContainerHighest),
            errorWidget: (_, __, ___) => Container(color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Icon(Icons.broken_image_outlined))),
        ),
      ),
    );
  }
}

/// 全屏图片查看器（支持缩放、滑动）
class _FullScreenImageViewer extends StatefulWidget {
  final List<String> images;
  final int initialIndex;
  const _FullScreenImageViewer({required this.images, required this.initialIndex});

  @override
  State<_FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<_FullScreenImageViewer> {
  late int _currentIndex;
  late PageController _controller;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        PhotoViewGallery.builder(
          pageController: _controller,
          itemCount: widget.images.length,
          onPageChanged: (i) => setState(() => _currentIndex = i),
          builder: (context, index) => PhotoViewGalleryPageOptions(
            imageProvider: CachedNetworkImageProvider(widget.images[index]),
            minScale: PhotoViewComputedScale.contained,
            maxScale: PhotoViewComputedScale.covered * 3,
            heroAttributes: PhotoViewHeroAttributes(tag: 'image_$index'),
          ),
          backgroundDecoration: const BoxDecoration(color: Colors.black),
          loadingBuilder: (_, __) => const Center(child: CircularProgressIndicator(color: Colors.white)),
        ),
        // 顶部关闭按钮
        Positioned(top: MediaQuery.of(context).padding.top + 8, right: 16,
          child: IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 28),
            onPressed: () => Navigator.pop(context)),
        ),
        // 底部页码
        if (widget.images.length > 1)
          Positioned(bottom: MediaQuery.of(context).padding.bottom + 16, left: 0, right: 0,
            child: Center(child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(16)),
              child: Text('${_currentIndex + 1} / ${widget.images.length}',
                style: const TextStyle(color: Colors.white, fontSize: 14))))),
      ]),
    );
  }
}

class _SmileyEditingController extends TextEditingController {
  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final spans = <InlineSpan>[];
    final buffer = StringBuffer();

    void flushText() {
      if (buffer.isEmpty) {
        return;
      }
      spans.add(
        TextSpan(
          text: buffer.toString(),
          style: style,
        ),
      );
      buffer.clear();
    }

    for (final codeUnit in text.codeUnits) {
      final url = SmileyCatalog.urlForCodeUnit(codeUnit);
      if (url == null) {
        buffer.writeCharCode(codeUnit);
        continue;
      }

      flushText();
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: CachedNetworkImage(
              imageUrl: url,
              width: 26,
              height: 26,
              fit: BoxFit.contain,
              errorWidget: (_, __, ___) => const SizedBox(
                width: 26,
                height: 26,
                child: Icon(
                  Icons.sentiment_satisfied_alt_rounded,
                  size: 20,
                ),
              ),
            ),
          ),
        ),
      );
    }

    flushText();

    return TextSpan(
      style: style,
      children: spans,
    );
  }
}

class _ReplySheet extends StatefulWidget {
  final String tid, fid, noticeauthor;
  final String? repquotePid, replyToName;
  final VoidCallback onReplied;

  const _ReplySheet({
    required this.tid,
    required this.fid,
    required this.noticeauthor,
    this.repquotePid,
    this.replyToName,
    required this.onReplied,
  });

  @override
  State<_ReplySheet> createState() => _ReplySheetState();
}

class _ReplySheetState extends State<_ReplySheet> {
  final _controller = _SmileyEditingController();
  final _focusNode = FocusNode();

  bool _sending = false;
  bool _showSmileys = false;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _toggleSmileys() {
    if (_showSmileys) {
      setState(() => _showSmileys = false);
      _focusNode.requestFocus();
      return;
    }

    _focusNode.unfocus();
    setState(() => _showSmileys = true);
  }

  void _hideSmileysForKeyboard() {
    if (_showSmileys) {
      setState(() => _showSmileys = false);
    }
  }

  void _insertSmiley(String url) {
    final marker = SmileyCatalog.markerForUrl(url);
    if (marker == null) {
      return;
    }

    final value = _controller.value;
    final selection = value.selection;
    final hasSelection = selection.isValid &&
        selection.start >= 0 &&
        selection.end >= 0;

    final start = hasSelection ? selection.start : value.text.length;
    final end = hasSelection ? selection.end : start;

    final nextText = value.text.replaceRange(start, end, marker);
    final nextOffset = start + marker.length;

    _controller.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextOffset),
      composing: TextRange.empty,
    );
  }

  Future<void> _send() async {
    final editorValue = _controller.text.trim();
    if (editorValue.isEmpty) {
      return;
    }

    final message = SmileyCatalog.toForumBbCode(editorValue).trim();
    if (message.isEmpty) {
      return;
    }

    setState(() => _sending = true);

    try {
      final result = await ApiService.instance.replyThread(
        tid: widget.tid,
        fid: widget.fid,
        noticeauthor: widget.noticeauthor,
        message: message,
        repquotePid: widget.repquotePid,
      );

      if (!mounted) {
        return;
      }

      if (result.success) {
        widget.onReplied();
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('回复成功'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('回复失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final media = MediaQuery.of(context);

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: media.size.height * 0.82,
          ),
          child: Material(
            color: colors.surface,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.replyToName != null
                              ? '回复 @${widget.replyToName}'
                              : '回复帖子',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '关闭',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    minLines: 1,
                    maxLines: 8,
                    autofocus: true,
                    onTap: _hideSmileysForKeyboard,
                    decoration: InputDecoration(
                      hintText: widget.replyToName != null
                          ? '回复 @${widget.replyToName}...'
                          : '输入回复内容...',
                      filled: true,
                      fillColor: colors.surfaceContainerHighest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      IconButton.filledTonal(
                        tooltip: '表情',
                        isSelected: _showSmileys,
                        onPressed: _toggleSmileys,
                        icon: Icon(
                          _showSmileys
                              ? Icons.keyboard_rounded
                              : Icons.sentiment_satisfied_alt_rounded,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _showSmileys
                              ? '点击表情插入到当前光标位置'
                              : '支持 QQ / COMCOM 表情',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.outline,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: _sending ? null : _send,
                        icon: _sending
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.send_rounded, size: 18),
                        label: const Text('发送'),
                      ),
                    ],
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    child: _showSmileys
                        ? Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: SizedBox(
                              height: 286,
                              child: _SmileyPicker(
                                onSelected: _insertSmiley,
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SmileyPicker extends StatelessWidget {
  final ValueChanged<String> onSelected;

  const _SmileyPicker({
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return DefaultTabController(
      length: SmileyCatalog.packs.length,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Column(
          children: [
            TabBar(
              dividerHeight: 1,
              tabs: [
                for (final pack in SmileyCatalog.packs)
                  Tab(text: '${pack.title}  ${pack.urls.length}'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  for (final pack in SmileyCatalog.packs)
                    _SmileyGrid(
                      urls: pack.urls,
                      onSelected: onSelected,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmileyGrid extends StatelessWidget {
  final List<String> urls;
  final ValueChanged<String> onSelected;

  const _SmileyGrid({
    required this.urls,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 58,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: urls.length,
      itemBuilder: (context, index) {
        final url = urls[index];

        return Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => onSelected(url),
            child: Center(
              child: CachedNetworkImage(
                imageUrl: url,
                width: 34,
                height: 34,
                fit: BoxFit.contain,
                placeholder: (_, __) => SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: colors.outline,
                  ),
                ),
                errorWidget: (_, __, ___) => Icon(
                  Icons.broken_image_outlined,
                  size: 20,
                  color: colors.outline,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
