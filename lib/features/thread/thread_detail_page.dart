import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/smiley_catalog.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../services/comment_thread_service.dart';
import '../../services/comment_filter_service.dart';
import '../../widgets/app_state_view.dart';
import '../../widgets/user_level_badge.dart';
import '../../routes/forum_link_router.dart';
import '../../pages/account/user_profile_page.dart';
import '../../pages/thread_editor_page.dart';
import 'thread_controller.dart';
import 'thread_state.dart';

part 'widgets/post_card.dart';
part 'widgets/post_content.dart';
part 'widgets/code_block.dart';
part 'widgets/attachment_card.dart';
part 'widgets/image_gallery.dart';
part 'widgets/reply_composer.dart';
part 'widgets/smiley_picker.dart';
part 'widgets/reply_sheet.dart';
part 'comments/comment_sheet.dart';

Future<({PostEditorForm form, PostAttachmentUploadResult attachment})?>
    _pickAndUploadReplyImage({
  required String tid,
  required String fid,
  String? repquotePid,
  PostEditorForm? currentForm,
}) async {
  final file = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    imageQuality: 88,
    maxWidth: 2560,
    maxHeight: 2560,
  );
  if (file == null) return null;

  final api = ApiService.instance;
  final form = currentForm ??
      await api.getReplyPostForm(
        tid: tid,
        fid: fid,
        repquotePid: repquotePid,
      );
  final attachment = await api.uploadPostImage(
    form: form,
    bytes: await file.readAsBytes(),
    fileName: file.name,
    referer: '${ApiService.baseUrl}/thread-$tid-1-1.html',
  );
  if (!attachment.success || attachment.aid.isEmpty) {
    throw StateError(attachment.message);
  }
  return (form: form, attachment: attachment);
}

void _insertAtSelection(TextEditingController controller, String text) {
  final value = controller.value;
  final selection = value.selection;
  final valid = selection.isValid && selection.start >= 0 && selection.end >= 0;
  final start = valid ? selection.start : value.text.length;
  final end = valid ? selection.end : start;
  final next = value.text.replaceRange(start, end, text);
  controller.value = TextEditingValue(
    text: next,
    selection: TextSelection.collapsed(offset: start + text.length),
    composing: TextRange.empty,
  );
}

String _replyError(Object error) => error.toString().replaceFirst(
      RegExp(r'^(Bad state|StateError|Exception):\s*'),
      '',
    );

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

  /// 业务状态（帖子数据、分页、错误）统一由控制器持有。
  late final ThreadDetailController _controller;

  // 点赞 / 收藏是纯交互状态，只影响两个图标，独立 setState 即可，
  // 不需要让整个页面跟着帖子数据一起重建。
  bool _liked = false;
  bool _favorited = false;

  @override
  void initState() {
    super.initState();
    _controller = ThreadDetailController(
      tid: widget.tid,
      targetPid: widget.targetPid,
      targetUrl: widget.targetUrl,
    );
    unawaited(_loadData());
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 首屏加载 + 定位楼层自动展开评论区。
  Future<void> _loadData() async {
    await _controller.load();
    if (!mounted) return;
    _openLocatedCommentsIfNeeded();
  }

  /// 外部分享链接进入时，自动弹出评论区并定位到目标楼层。
  void _openLocatedCommentsIfNeeded() {
    final located = _controller.locatedDetail;
    if (located == null || _controller.targetCommentsOpened) return;
    final pid = widget.targetPid?.trim() ?? '';
    if (pid.isEmpty) return;
    _controller.markTargetCommentsOpened();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showComments(detailOverride: located, targetPid: pid);
    });
  }

  Future<void> _loadMore() => _controller.loadMore();

  /// 长按顶栏标题复制完整标题。
  ///
  /// 顶栏受宽度限制只能省略号显示，而 `detail.title` 是解析出来的完整标题，
  /// 所以复制到剪贴板的是完整文本。
  Future<void> _copyTitle(String? title) async {
    final value = (title ?? '').trim();
    if (value.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已复制标题'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _showComments({
    ThreadDetail? detailOverride,
    String? targetPid,
  }) async {
    final detail = detailOverride ?? _controller.state.detail;
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
        hasMore: () => locatingTarget ? false : _controller.state.hasMore,
        isLoadingMore: () => _controller.state.loadingMore,
        onLoadMore: locatingTarget ? () async {} : _loadMore,
        onRefresh: locatingTarget
            ? () => _controller.refreshLocatedPage(detail)
            : _controller.refreshFirstPage,
        canEdit: _controller.canEdit,
        onEdit: _editPost,
        onImageTap: (post, index) => _openImages(post.images, index),
      ),
    );
  }

  void _showReply({Post? post}) {
    final detail = _controller.state.detail;
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

  bool _canEdit(Post post) => _controller.canEdit(post);

  Future<void> _editPost(Post post) async {
    final detail = _controller.state.detail;
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
    // 只有帖子数据（控制器状态）变化时才重建 Scaffold；
    // 点赞 / 收藏这类局部交互不经过这里。
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    final s = _controller.state;
    final detail = s.detail;
    return Scaffold(
      body: CustomScrollView(
        controller: _scrollController,
        cacheExtent: 800,
        slivers: [
          SliverAppBar(
            pinned: true,
            // 长按标题复制。顶栏标题是省略号显示的，复制的是完整标题原文。
            title: GestureDetector(
              onLongPress: detail == null
                  ? null
                  : () => _copyTitle(detail.title),
              child: Text(
                detail?.title ?? '帖子详情',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
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
                onPressed: s.loading ? null : _loadData,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          if (s.loading && detail == null)
            const SliverFillRemaining(
              child: AppStateView.loading(),
            )
          else if (s.error != null && detail == null)
            SliverFillRemaining(
              child: AppStateView.error(
                message: s.error!,
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
