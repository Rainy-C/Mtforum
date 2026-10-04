part of '../thread_detail_page.dart';

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
  bool _uploadingImage = false;
  bool _showSmileys = false;
  bool _showFilteredComments = false;
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
  PostEditorForm? _replyForm;
  final List<PostAttachmentUploadResult> _replyAttachments = [];

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
    if (!mounted) return;
    setState(() {
      if (_filteredOutComments.isEmpty) _showFilteredComments = false;
    });
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

  List<Post> get _rawComments => _threadComments(widget.detail);

  bool _isCommentFiltered(Post post) {
    if (!_commentFilter.commentsEnabled || !_commentFilter.hasRules) {
      return false;
    }
    // 从通知定位进来的目标楼层始终可见，避免过滤规则破坏跳转。
    if (post.pid == widget.initialTargetPid) return false;
    return _commentFilter.matches(post.content);
  }

  List<Post> get _filteredOutComments => _rawComments
      .where(_isCommentFiltered)
      .toList(growable: false);

  List<Post> get _filteredComments => _rawComments
      .where((post) => !_isCommentFiltered(post))
      .toList(growable: false);

  List<Post> get _comments {
    final source =
        _showFilteredComments ? _filteredOutComments : _filteredComments;
    final comments = List<Post>.from(source);
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
    final chronological =
        _showFilteredComments ? _rawComments : _filteredComments;
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
          compactFloor: true,
          hideQuotedContext: parent != null || post.replyToName != null,
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

  Future<void> _pickReplyImage() async {
    if (_sending || _uploadingImage) return;
    if (!ApiService.instance.isLoggedIn) {
      _ensureLogin();
      return;
    }
    setState(() {
      _uploadingImage = true;
      _showSmileys = false;
    });
    try {
      final result = await _pickAndUploadReplyImage(
        tid: widget.detail.tid,
        fid: widget.detail.fid,
        repquotePid: _replyTarget?.pid,
        currentForm: _replyForm,
      );
      if (!mounted || result == null) return;
      _replyForm = result.form;
      _replyAttachments.add(result.attachment);
      _insertAtSelection(
        _composerController,
        '[attachimg]${result.attachment.aid}[/attachimg]\n',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('图片已上传并插入评论')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('图片上传失败：${_replyError(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

  Future<void> _sendComment() async {
    if (_sending || _uploadingImage) return;
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
        replyForm: _replyForm,
        uploadedAttachmentAids:
            _replyAttachments.map((attachment) => attachment.aid),
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
        _replyForm = null;
        _replyAttachments.clear();
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
    final rawCommentCount = _rawComments.length;
    final filteredCommentCount = _filteredOutComments.length;
    final allCommentsFiltered = rawCommentCount > 0 &&
        !_showFilteredComments &&
        comments.isEmpty;
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
        !_uploadingImage &&
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
                            _showFilteredComments
                                ? '已过滤评论'
                                : widget.initialTargetPid
                                            ?.trim()
                                            .isNotEmpty ==
                                        true
                                    ? '已定位到回复'
                                    : '评论区',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            _showFilteredComments
                                ? '共 $filteredCommentCount 条·点击返回查看全部评论'
                                : _loadingAll
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
                      onPressed: _loadingAll ||
                              _targetMode ||
                              _showFilteredComments
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
              const SizedBox(height: 4),
              if (filteredCommentCount > 0)
                Material(
                  color: colors.surfaceContainerLow,
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _showFilteredComments = !_showFilteredComments;
                      });
                      if (_scrollController.hasClients) {
                        _scrollController.jumpTo(
                          _scrollController.position.minScrollExtent,
                        );
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
                      child: Row(
                        children: [
                          Icon(
                            _showFilteredComments
                                ? Icons.arrow_back_rounded
                                : Icons.filter_alt_outlined,
                            size: 18,
                            color: colors.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _showFilteredComments
                                  ? '正在查看 $filteredCommentCount 条已过滤评论'
                                  : '已过滤 $filteredCommentCount 条评论',
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                          Text(
                            _showFilteredComments ? '返回评论' : '查看',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: colors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: colors.primary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
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
                                  ? '点击顶部“已过滤”查看隐藏内容'
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
                        padding: const EdgeInsets.fromLTRB(10, 6, 10, 18),
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
                uploadingImage: _uploadingImage,
                attachmentCount: _replyAttachments.length,
                canSend: canSend,
                showSmileys: _showSmileys,
                replyTargetName: _replyTarget?.authorName,
                onTapInput: _hideSmileysForKeyboard,
                onToggleSmileys: _toggleSmileys,
                onPickImage: _pickReplyImage,
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
