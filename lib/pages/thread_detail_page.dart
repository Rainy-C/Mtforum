import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/smiley_catalog.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/user_level_badge.dart';
import 'account/user_profile_page.dart';
import 'thread_editor_page.dart';

class ThreadDetailPage extends StatefulWidget {
  final String tid;
  const ThreadDetailPage({super.key, required this.tid});

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

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_detail == null || _loadingMore || !_hasMore) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 260) {
      _loadMore();
    }
  }

  Future<void> _loadData() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await _api.getThreadDetail(widget.tid, page: 1);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _page = 1;
        _hasMore = detail.posts.isNotEmpty;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '加载失败：$e');
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
        slivers: [
          SliverAppBar(
            pinned: true,
            title: Text(
              detail?.title ?? '帖子详情',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              IconButton(
                tooltip: '刷新',
                onPressed: _loading ? null : _loadData,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          if (_loading && detail == null)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null && detail == null)
            SliverFillRemaining(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 14),
                      FilledButton(onPressed: _loadData, child: const Text('重试')),
                    ],
                  ),
                ),
              ),
            )
          else if (detail != null && detail.posts.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.article_outlined, size: 44),
                    const SizedBox(height: 12),
                    const Text('没有解析到楼层内容'),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _loadData, child: const Text('重新加载')),
                  ],
                ),
              ),
            )
          else if (detail != null)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 90),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index == detail.posts.length) {
                      if (_loadingMore) {
                        return const Padding(
                          padding: EdgeInsets.all(18),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      if (!_hasMore) {
                        return Padding(
                          padding: const EdgeInsets.all(18),
                          child: Center(
                            child: Text(
                              '没有更多了',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    }

                    final post = detail.posts[index];
                    return _PostCard(
                      post: post,
                      onReply: () => _showReply(post: post),
                      onEdit: _canEdit(post) ? () => _editPost(post) : null,
                      onImageTap: (imageIndex) =>
                          _openImages(post.images, imageIndex),
                    );
                  },
                  childCount: detail.posts.length + 1,
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: detail == null
          ? null
          : SafeArea(
              top: false,
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 10, 8),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: _toggleLike,
                        icon: Icon(
                          _liked ? Icons.thumb_up_rounded : Icons.thumb_up_outlined,
                        ),
                      ),
                      IconButton(
                        onPressed: _toggleFavorite,
                        icon: Icon(
                          _favorited
                              ? Icons.bookmark_rounded
                              : Icons.bookmark_border_rounded,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: () => _showReply(),
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text('写回复…'),
                          style: FilledButton.styleFrom(
                            alignment: Alignment.centerLeft,
                            minimumSize: const Size(0, 48),
                            maximumSize: const Size(double.infinity, 48),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class _PostCard extends StatelessWidget {
  final Post post;
  final VoidCallback onReply;
  final VoidCallback? onEdit;
  final ValueChanged<int> onImageTap;

  const _PostCard({
    required this.post,
    required this.onReply,
    this.onEdit,
    required this.onImageTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final content = post.content.trim();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colors.outlineVariant,
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
                      if (post.authorLevel != null ||
                          post.postTime != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (post.authorLevel != null &&
                                  post.authorLevel!.trim().isNotEmpty)
                                UserLevelBadge(
                                  text: post.authorLevel!,
                                ),
                              if (post.postTime != null)
                                Text(
                                  post.postTime!,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colors.outline,
                                  ),
                                ),
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
            if (post.replyToName != null) ...[
              const SizedBox(height: 9),
              Text(
                '回复 @${post.replyToName}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.primary,
                ),
              ),
            ],
            if (post.richContent.isNotEmpty) ...[
              const SizedBox(height: 10),
              _RichContentView(
                contents: post.richContent,
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
            if (post.images.isNotEmpty &&
                !post.richContent.any(
                  (item) => item.type == PostContentType.image,
                )) ...[
              const SizedBox(height: 10),
              _PostImages(images: post.images, onTap: onImageTap),
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

class _RichContentView extends StatelessWidget {
  final List<PostContent> contents;
  final ValueChanged<String>? onImageTap;

  const _RichContentView({
    required this.contents,
    this.onImageTap,
  });

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return;
    }

    await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
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

        case PostContentType.audio:
          flushInline();
          if (content.url != null) {
            widgets.add(
              _MediaCard(
                icon: Icons.audiotrack_rounded,
                title: '音频',
                subtitle: content.url!,
                actionLabel: '播放',
                onTap: () => _openUrl(content.url!),
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
                onTap: () => _openUrl(content.url!),
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
                onTap: () => _openUrl(content.url!),
              ),
            );
          }
      }
    }

    flushInline();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
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
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return;
    }

    await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final baseStyle = theme.textTheme.bodyMedium?.copyWith(height: 1.55);
    final spans = <InlineSpan>[];

    for (final content in widget.contents) {
      switch (content.type) {
        case PostContentType.text:
          spans.add(
            TextSpan(
              text: content.text,
              style: baseStyle,
            ),
          );

        case PostContentType.bold:
          spans.add(
            TextSpan(
              text: content.text,
              style: baseStyle?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          );

        case PostContentType.link:
          final url = content.url;
          if (url == null || url.isEmpty) {
            spans.add(TextSpan(text: content.text, style: baseStyle));
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
              style: baseStyle?.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.w500,
                decoration: TextDecoration.underline,
                decorationColor: colors.primary.withValues(alpha: 0.72),
                decorationThickness: 1,
              ),
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

    return SelectionArea(
      child: RichText(
        text: TextSpan(
          style: baseStyle,
          children: spans,
        ),
      ),
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
      r'|\b(?:apt|apk|yum|dnf|pacman)\s+(?:install|update)\b'
      r'|\bexport\s+[A-Za-z_][A-Za-z0-9_]*='
      r'|\$\{?[A-Za-z_][A-Za-z0-9_]*\}?',
      multiLine: true,
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
                    minLines: 3,
                    maxLines: 6,
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
